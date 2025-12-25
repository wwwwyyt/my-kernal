	! boot.s 程序
	! 首先利用 BIOS 中断将内核代码（head.s）加载到 0x10000 处，然后再将其移动到 0 处  
	! 最后进入保护模式，从 0 处开始执行 head.s  


BOOTSEG = 0x07c0		! boot.s 被加载到内存 0x7c00 处  
SYSSEG  = 0x1000		! head.s 先被加载到 0x10000 处，然后移动到 0x0 处  
SYSLEN  = 17			! 内核占用的最多磁盘扇区数（2 到 17 扇区，共 16 个，8KB）  

entry start
start:
	jmpi 	go, #BOOTSEG	! 跳转后，cs 被设为 BOOTSEG  
go:	mov	ax, cs
	mov 	ds, ax		! 让 ds 和 ss 都指向 BOOTSEG  
	mov	ss, ax
	mov 	sp, #0x400	! 设置临时栈指针。什么作用？  

	! 加载内核代码到 0x10000 开始处  
load_system:
	mov	dx, #0x0000
	mov	cx, #0x0002
	mov	ax, #SYSSEG
	mov	es, ax
	xor	bx, bx
	mov	ax, #0x200+SYSLEN
	int	0x13
	jnc	ok_load
die:	jmp	die

	! 把内核代码移动到内存 0 开始处，共移动 8KB  
ok_load:
	cli			! 关中断  
	mov	ax, #SYSSEG
	mov	ds, ax
	xor	ax, ax
	mov	es, ax
	mov	cx, #0x2000
	sub	si, si
	sub	di, di
	rep
	movw		! 执行重复移动指令  
	mov	ax, #BOOTSEG	! 加载 IDT 和 GDT 基地址寄存器 IDTR 和 GDTR  
	mov	ds, ax		! 让 DS 重新指向 0x7c0 段  
	lidt	idt_48		! 加载 IDTR，6 字节操作数：2 字节表长度，4 字节线性基地址  
	lgdt	gdt_48		! 加载 GDTR，6 字节操作数：2 字节表长度，4 字节线性基地址  CR0（机器状态字），进入保护模式
	mov 	ax, #0x0001	! 在 CR0 中设置保护模式标志位 PE（位于 0 位）  
	lmsw	ax
	jmpi	0, 8		! 跳转至段选择符值指定的段中，段选择符值为 8，偏移 0 处  
	! GDT 的内容。其中有 3 个段描述符，第 1 个不用，另 2 个是代码段和数据段的段描述符  
gdt:	.word	0, 0, 0, 0	! 段描述符 0  

	.word	0x07FF		! 段描述符 1  
	.word	0x0000
	.word	0x9A00
	.word	0x00C0

	.word	0x07FF		! 段描述符 2  
	.word	0x0000
	.word	0x9200
	.word	0x00C0
	! LIDT 和 LGDT 指令的 6 字节操作数  
idt_48:	.word	0		! idt 表长度为 0  
	.word	0, 0		! idt 表线性基地址为 0  
gdt_48: .word	0x7ff		! gdt 表长度为 2048 字节  
	.word	0x7c00 + gdt, 0	! gdt 表线性基地址为 0x7c0 段的偏移 gdt 位置处（本代码中 gdt 的物理地址）  
.org 510	! 引导扇区有效标志，必须位于引导扇区最后 2 字节处  
	.word	0xAA55
