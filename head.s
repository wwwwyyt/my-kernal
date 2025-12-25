    /* 0.3.0 */    
    /* head.s 包含 32 位保护模式初始化设置代码、时钟中断代码、系统调用中断代码和 2 个任务的代码
	初始化完成后，程序移动到任务 0 处开始执行，并在时钟中断控制下进行任务 0 和任务 1 之间的切换操作 */
	LATCH	 	= 11930	/* 定时器初始计数值，每隔 10 ms 发送一次中断请求 */
	SCRN_SEL	= 0x18	/* 屏幕显示内存段选择符 */
	TSS0_SEL	= 0x20	/* 任务 0 的 TSS 段选择符，索引为 4 */
	LDT0_SEL	= 0x28	/* 任务 0 的 LDT 段选择符，索引为 5 */
	TSS1_SEL	= 0x30	/* 任务 1 的 TSS 段选择符，索引为 6 */
	LDT1_SEL	= 0x38	/* 任务 1 的 LDT 段选择符，索引为 7 */
	TSS2_SEL	= 0x40  /* 任务 2 的 TSS 段选择符，索引为 8 */
	LDT2_SEL	= 0x48  /* 任务 2 的 LDT 段选择符，索引为 9 */

.text
startup_32:
	/* 首先加载数据段寄存器 DS、堆栈段寄存器 SS 和堆栈指针 ESP。所有段的线性基地址都是 0 */
	movl	$0x10, %eax	/* 0x10 是 GDT 中数据段选择符 */
	mov	%ax, %ds
	lss	init_stack, %esp

	/* 在新的位置重新设置 IDT 和 GDT 表 */
	call	setup_idt	/* 设置 IDT */
	call	setup_gdt	/* 设置 GDT */
	movl	$0x10, %eax	/* 在改变 GDT 后重新加载所有段寄存器。此时 eax 低 16 位是 0x10 ？*/
	mov	%ax, %ds	/* 段寄存器 ds 加载 0x10 ？*/
	mov	%ax, %es
	mov	%ax, %fs
	mov	%ax, %gs
	lss	init_stack, %esp	/* 从 %esp 中加载一个什么，到地址 init_stack 处和段寄存器 SS 中 */
	/* 设置 8253 定时芯片。把计数器通道 0 设置为每隔 10 毫秒向中断控制器发送一个中断请求信号 */
	movb	$0x36, %al
	movl	$0x43, %edx
	outb	%al, %dx
	movl	$LATCH, %eax
	movl	$0x40, %edx
	outb	%al, %dx
	movb	%ah, %al
	outb	%al, %dx
	
	/* 在 IDT 表第 8 和第 128（0x80）项处分别设置定时中断门描述符和系统调用陷阱门描述符 */
	/* 中断描述符表 */
	movl	$0x00080000, %eax
	movw	$timer_interrupt, %ax
	movw	$0x8E00, %dx
	movl	$0x08, %ecx
	lea	idt(, %ecx, 8), %esi
	movl	%eax, (%esi)
	movl	%edx, 4(%esi)
	movw	$system_interrupt, %ax
	movw	$0xef00, %dx
	movl	$0x80, %ecx
	lea	idt(, %ecx, 8), %esi
	movl	%eax, (%esi)
	movl	%edx, 4(%esi)

	/* 在堆栈中人工建立中断时的场景 */
	pushfl
	andl	$0xffffbfff, (%esp)
	popfl
	movl	$TSS0_SEL, %eax
	ltr	%ax
	movl	$LDT0_SEL, %eax
	lldt	%ax
	movl	$0, current	/* current 初始设置为 0 */
	sti
	pushl	$0x17
	pushl	$init_stack
	pushfl
	pushl	$0x0f
	pushl	$task0
	iret

	/* 设置 GDT 和 IDT 中描述符项 */
setup_gdt:
	lgdt	lgdt_opcode
	ret
	
setup_idt:
	lea	ignore_int, %edx
	movl	$0x00080000, %eax
	movw	%dx, %ax
	movw	$0x8E00, %dx
	lea	idt, %edi
	mov	$256, %ecx
rp_sidt:
	movl	%eax, (%edi)
	movl	%edx, 4(%edi)
	addl	$8, %edi
	dec	%ecx
	jne	rp_sidt
	lidt	lidt_opcode
	ret

	/* 显示字符 */
write_char:
	push	%gs
	pushl	%ebx
	
	mov	$SCRN_SEL, %ebx
	mov	%bx, %gs
	movl	scr_loc, %bx
	shl	$1, %ebx
	movb	%al, %gs:(%ebx)
	shr	$1, %ebx
	incl	%ebx
	cmpl	$2000, %ebx
	jb	1f
	movl	$0, %ebx
1:	movl	%ebx, scr_loc

	popl	%ebx
	pop	%gs
	ret

	/* 中断处理程序：默认中断、定时中断和系统调用中断 */
	/* 默认中断处理程序，当系统产生其他中断时，在屏幕上打印 “Z” */	
	.align 2
ignore_int:			
	push 	%ds
	pushl	%eax
	movl	$0x10, %eax
	mov	%ax, %ds
	movl	$90, %eax
	call	write_char
	popl	%eax
	pop	%ds
	iret
	
	/* 定时中断处理程序 */
	.align 2
timer_interrupt:
	push %ds
	pushl %eax
	movl $0x10, %eax	/* 首先让 DS 指向内核数据段 */
	mov %ax, %ds
	movb $0x20, %al		/* 然后立刻允许其他硬件中断，即向 8259A 发送 EOI 命令 */
	/* 接着判断当前任务，若是任务 0 则去执行任务 1，若是任务 1 则去执行任务 2 ，若是任务 2 则去执行任务 0 */
	outb %al, $0x20
	movl $1, %eax
	cmpl %eax, current	
	je 1f			/* 当前任务为 1 时，跳转到标号 1 处 */
	cmpl $2, current
	je 2f			/* 当前任务为 2 时，跳转到标号 2 处  */
	
	movl %eax, current	/* 若当前任务是 0，则把 1 存入 current ，并跳转到 1 去执行 */
	ljmp $TSS1_SEL, $0
	jmp 3f
1:	movl $2, current	/* 标号 1：若当前任务是 1，则把 2 存入 current ，并跳转到 2 去执行 */
	ljmp $TSS2_SEL, $0
2:	movl $0, current	/* 标号 2：若当前任务是 2，则把 0 存入 current ，并跳转到 0 去执行 */
	ljmp $TSS0_SEL, $0
3:	popl %eax
	pop %ds
	iret
	
	/* 系统调用 int 0x80 处理程序，功能是显示字符 */
	.align 2
system_interrupt:
	push	%ds
	pushl	%edx
	pushl	%ecx
	pushl	%ebx
	pushl	%eax
	movl	$0x10, %edx
	mov	%dx, %ds
	call	write_char
	popl	%eax
	popl	%ebx
	popl	%ecx
	popl	%edx
	pop	%ds
	iret


current:.long 	0	/* 当前任务号（0 或 1 或 2） */
scr_loc:.long 	0

	.align 2
lidt_opcode:
	.word	256 * 8 - 1		/* 16 位 IDT 表长度，这里的数据是 6 个 0 和 10 个 1 */
	.long	idt			/* 32 位 IDT 基地址 */
lgdt_opcode:
	.word	(end_gdt - gdt) - 1	/* 16 位 GDT 表长度 */
	.long	gdt			/* 32 位 GDT 基地址 */

	.align 3
idt: 	.fill	256, 8, 0		/* IDT 表的数据，256 个 8 字节的 0 */

gdt:					/* GDT 表的数据，从下一行到 end_gdt 之前，每行 8 字节 */
	.quad	0x0000000000000000		/* 系统段描述符 0，保留 */
	.quad	0x00c09a00000007ff		/* 系统段描述符 1，内核代码段 */
	.quad	0x00c09200000007ff		/* 系统段描述符 2，内核数据段 */
	.quad	0x00c0920b80000002		/* 系统段描述符 3，显示段 */
	.word	0x0068, tss0, 0xe900, 0x0	/* TSS0 */
	.word	0x0040, ldt0, 0xe200, 0x0       /* LDT0 */
	.word	0x0068, tss1, 0xe900, 0x0    	/* TSS1 */
	.word	0x0040, ldt1, 0xe200, 0x0	/* LDT1 */
	.word	0x68, tss2, 0xe900, 0x0    	/* TSS2 */
	.word	0x40, ldt2, 0xe200, 0x0		/* LDT2 */
	
end_gdt:
	.fill	128, 4, 0		/* GDT 的剩余部分填充 128 个 4 字节的 0 */
init_stack:				/* 初始堆栈，也就是任务 0 的用户栈 */	
	.long	init_stack	/* 刚进入保护模式时用于加载 SS:ESP 堆栈指针值 */
	.word	0x10		/* init_stack 段基地址（32 位） + 0x10（16位） */

	/* 任务 0 的 LDT 表段中的局部段描述符 */
	.align 3
ldt0:
	.quad 	0x0000000000000000
	.quad 	0x00c0fa00000003ff
	.quad 	0x00c0f200000003ff
	/* 任务 0 的 TSS 段的内容 */
tss0:	.long 	0
	.long	krn_stk0, 0x10
	.long	0, 0, 0, 0, 0
	.long	0, 0, 0, 0, 0
	.long	0, 0, 0, 0, 0
	.long	0, 0, 0, 0, 0, 0
	.long	LDT0_SEL, 0x8000000

	.fill	128, 4, 0
krn_stk0:			/* 任务 0 的内核栈 */

	/* 任务 1 的 LDT 表段内容 */
	.align 3
ldt1:	.quad 	0x0000000000000000
	.quad 	0x00c0fa00000003ff
	.quad 	0x00c0f200000003ff
	/* 任务 1 的 TSS 段的内容 */
tss1:
	.long 	0
	.long	krn_stk1, 0x10
	.long	0, 0, 0, 0, 0
	.long	task1, 0x200
	.long	0, 0, 0, 0
	.long	usr_stk1, 0, 0, 0
	.long	0x17, 0x0f, 0x17, 0x17, 0x17, 0x17
	.long	LDT1_SEL, 0x8000000

	.fill	128, 4, 0
krn_stk1:			/* 任务 1 的内核栈 */

	/* 任务 2 的 LDT 表段内容 */
	.align 3
ldt2:
	.quad 	0x0000000000000000
	.quad 	0x00c0fa00000003ff
	.quad 	0x00c0f200000003ff
	/* 任务 2 的 TSS 段的内容 */
tss2:
	.long 	0
	.long	krn_stk2, 0x10
	.long	0, 0, 0, 0, 0
	.long	task2, 0x200
	.long	0, 0, 0, 0
	.long	usr_stk2, 0, 0, 0
	.long	0x17, 0x0f, 0x17, 0x17, 0x17, 0x17
	.long	LDT2_SEL, 0x8000000

	.fill	128, 4, 0
krn_stk2:			/* 任务 2 的内核栈 */

	/* 任务 0 的代码，显示字符 “A” */
task0:
	movl	$0x17, %eax
	movw	%ax, %ds
	movl	$65, %al
	int	$0x80
	movl	$0xfff, %ecx
1:	loop	1b
	jmp 	task0
	/* 任务 1 的代码，显示字符 “B” */	
task1:
	movl	$0x17, %eax
	movw 	%ax, %ds
	movl	$66, %al
	int	$0x80
	movl	$0xfff, %ecx
1:	loop	1b
	jmp	task1
	.fill	128, 4, 0	/* 任务 1 的用户栈 */
	/* 任务 2 的代码，显示字符 “C” */	
task2:
	movl	$0x17, %eax
	movw 	%ax, %ds
	movl	$67, %al
	int	$0x80
	movl	$0xfff, %ecx
1:	loop	1b
	jmp	task2

	/* 任务 1 的用户栈 */
	.fill	128, 4, 0
usr_stk1:	
	/* 任务 2 的用户栈 */
	.fill	128, 4, 0
usr_stk2:

