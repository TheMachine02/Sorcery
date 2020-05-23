; this header reside in thread memory
; DONT TOUCH ANYTHING YOU DONT WANT TO BREAK IN THIS HEADER
; Atomic is UTERLY important while writing to it
; you can read pid, ppid, irq (but it will not be a *safe value, meaning it can change the next instruction
; for safety dont touch anything here except PID and PPID ;
define	KERNEL_THREAD_HEADER			0x00
define	KERNEL_THREAD_PID			0x00
define	KERNEL_THREAD_NEXT			0x01
define	KERNEL_THREAD_PREVIOUS			0x04
define	KERNEL_THREAD_PPID			0x07
define	KERNEL_THREAD_IRQ			0x08
define	KERNEL_THREAD_STATUS			0x09
; static thread data that can be manipulated freely ;
; within it's own thread ... don't manipulate other thread memory, it's not nice ;
define	KERNEL_THREAD_STACK_LIMIT		0x0A
define	KERNEL_THREAD_STACK			0x0D
define	KERNEL_THREAD_HEAP			0x10
define	KERNEL_THREAD_TIME			0x13
define	KERNEL_THREAD_ERRNO			0x16
define	KERNEL_THREAD_SIGNAL			0x17
define	KERNEL_THREAD_SIGNAL_CODE		0x17
define	KERNEL_THREAD_SIGNAL_MESSAGE		0x18
define  KERNEL_THREAD_SIGNAL_MASK		0x1B
define	KERNEL_THREAD_TIMER			0x1F
define	KERNEL_THREAD_TIMER_COUNT		0x1F
define	KERNEL_THREAD_TIMER_NEXT		0x20
define	KERNEL_THREAD_TIMER_PREVIOUS		0x23
define	KERNEL_THREAD_TIMER_CALLBACK		0x26

define	KERNEL_THREAD_DESCRIPTOR_TABLE		0x2F
; up to 0x80, table is 81 bytes or 27 descriptor, 3 reserved as stdin, stdout, stderr ;
; 24 descriptors usables ;

define	KERNEL_THREAD_HEADER_SIZE		0x80
define	KERNEL_THREAD_STACK_SIZE		4096	; 3964 bytes usable
define	KERNEL_THREAD_HEAP_SIZE			4096
define	KERNEL_THREAD_DESCRIPTOR_TABLE_SIZE	24
define	KERNEL_THREAD_IDLE			KERNEL_THREAD

define	TASK_READY				0
define	TASK_INTERRUPTIBLE			1    ; can be waked up by signal
define	TASK_STOPPED				2    ; can be waked by signal only SIGCONT, state of SIGSTOP / SIGTSTP

define	kthread_queue_active			0xD00100
define	kthread_queue_active_size		0xD00100
define	kthread_queue_active_current		0xD00101

define	kthread_queue_retire			0xD00104
define	kthread_queue_retire_size		0xD00104
define	kthread_queue_retire_current		0xD00105

define	kthread_need_reschedule			0xD00108
define	kthread_current				0xD00109

; 130 and up is free
; 64 x 4 bytes, D00200 to D00300
define	kthread_pid_bitmap			0xD00200

kthread:
.init:
	tstdi
	ld	de, NULL
	ld	hl, kthread_queue_active
	ld	(hl), e
	inc	hl
	ld	(hl), de
	ld	hl, kthread_queue_retire
	ld	(hl), e
	inc	hl
	ld	(hl), de
	ld	de, KERNEL_THREAD
	ld	(kthread_current), de
	ld	a, e
	ld	(kthread_need_reschedule), a
; copy idle thread (ie, kernel thread. Stack is kernel stackh, code is init kernel)
	ld	hl, .IHEADER
	ld	de, KERNEL_THREAD
	ld	bc, .IHEADER_END - .IHEADER
	ldir
	ld	hl, kthread_pid_bitmap
	ld	de, kthread_pid_bitmap+1
	ld	(hl), 0
	ld	bc, 255
	ldir
	ld	(hl), 0x01  ; permission ring 1 (thread 0 is all mighty)
	inc	hl
	ld	de, KERNEL_THREAD_IDLE
	ld	(kthread_pid_bitmap), de
	retei

.yield=kscheduler.yield
	
.create_no_mem:
.create_no_pid:
	ld	l, EAGAIN
.create_errno:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), l
; restore register and pop all the stack
	exx
	tstei
	pop	ix
	pop	iy
	pop	af
	scf
	sbc	hl, hl
	ret

.create:
; Create a thread
; REGSAFE and ERRNO compliant
; void thread_create(void* entry)
; register IY is entry
; error -1 and c set, 0 and nc otherwise, ERRNO set
; HL, BC, DE copied from current context to the new thread
	push	af
	push	iy
	push	ix
	tstdi
; save hl, de, bc registers
	exx
	lea	ix, iy+0
	call	.reserve_pid
	jr	c, .create_no_pid
	ld	hl, KERNEL_MMU_RAM
	ld	b, KERNEL_THREAD_STACK_SIZE/KERNEL_MMU_PAGE_SIZE + KERNEL_THREAD_HEAP_SIZE/KERNEL_MMU_PAGE_SIZE
	call	kmmu.map_block_thread
	jr	c, .create_no_mem
; hl is adress    
	push	hl
	pop	iy
	ld	(iy+KERNEL_THREAD_PID), a
	ld	(iy+KERNEL_THREAD_IRQ), 0
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
; timer ;
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), 0
; stack limit set first ;
	lea	hl, iy + 4
	ld	de, KERNEL_THREAD_HEADER_SIZE
	add	hl, de
; please note write affect memory, so do a + 4 to be safe    
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
; stack ;
	lea	hl, iy - 24
	ld	de, KERNEL_THREAD_STACK_SIZE
	add	hl, de
	ld	(iy+KERNEL_THREAD_STACK), hl
; heap ;
	lea	hl, iy + 0
	add	hl, de
	ld	(iy+KERNEL_THREAD_HEAP), hl
	push	hl
	ex	(sp), ix
	ld	de, KERNEL_MMU_PAGE_SIZE - KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), de
	ld	de, NULL
	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), de
	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), de
	lea	de, ix+KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), de
	pop	ix
; map the thread to be transparent to the scheduler
; iy is thread adress, a is still PID    
; map the pid
	or	a, a
	sbc	hl, hl
	add	a, a
	add	a, a
	ld	l, a
	ld	de, kthread_pid_bitmap
	add	hl, de
	ld	(hl), 0xFF
	inc	hl
	ld	(hl), iy
; write parent pid    
	ld	hl, (kthread_current)
	ld	a, (hl)
	ld	(iy+KERNEL_THREAD_PPID), a
; setup the queue
; insert the thread to the ready queue
	ld	hl, kthread_queue_active
	call   kqueue.insert
; setup the stack \o/
	ld	de, KERNEL_THREAD_STACK_SIZE
	add	iy, de
	ld	hl, .exit
	ld	(iy-3), hl
	ld	(iy-6), ix
	ld	de, NULL
	ld	(iy-9), de		; ix [NULL] > int argc, char *argv[]
	ld	(iy-12), de		; iy [NULL] > in the future
	ld	(iy-24), de		; af [NULL] > TODO
	exx
	ld	(iy-15), hl
	ld	(iy-18), bc
	ld	(iy-21), de
	tstei
	pop	ix
	pop	iy
	pop	af
	or	a, a
	sbc	hl, hl
	ret
; iy = thread

.wait_on_IRQ:
; suspend till waked by an IRQ
	di
	push	iy
	push	hl
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_IRQ), a
; the process to write the thread state and change the queue should be always a critical section
	call	task_switch_interruptible
; also note that writing THREAD_IRQ doesn't *need to be atomic, but testing is
	pop	hl
	pop	iy
; switch away from current thread to a new active thread
; cause should already have been writed
	jp	.yield

.suspend:
; suspend till waked by a signal or by an IRQ (you should have writed the one you are waiting for before though and atomically)
	di
	push	iy
	push	hl
	ld	iy, (kthread_current)
; the process to write the thread state and change the queue should be always a critical section
	call	task_switch_interruptible
; also note that writing THREAD_IRQ doesn't *need to be atomic, but testing is
	pop	hl
	pop	iy
; switch away from current thread to a new active thread
; cause should already have been writed
	jp	.yield
	
.resume:
; wake thread (adress iy)
; insert in place in the RR list
; return iy = kqueue_current
	push	af
	push	hl
	lea	hl, iy+0
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .resume_exit
	tstdi
	ld	a, (iy+KERNEL_THREAD_STATUS)    ; this read need to be atomic !
	cp	a, TASK_INTERRUPTIBLE
; can't wake TASK_READY (0) and TASK_STOPPED (2)
; range -1 > 1
; if a=2 , nc, if a=255, nc, else c
	jr	nz, .resume_exit_atomic
	call	task_switch_running
	ld	a, 0xFF
	ld	(kthread_need_reschedule), a
.resume_exit_atomic:
	tstei
.resume_exit:
	pop	hl
	pop	af
	ret

.core:

.exit:
	di
	ld	sp, (KERNEL_STACK)
; first disable stack protector (load the kernel_stack stack protector)
	ld	a, 0xA0
	out0	(0x3A), a
	ld	a, 0x00
	out0	(0x3B), a
	ld	a, 0xD0
	out0	(0x3C), a
	ld	iy, (kthread_current)
	ld	a, (iy+KERNEL_THREAD_PID)
	push	hl
	call	.free_pid
	pop	hl
; signal parent thread of the end of the child thread
; also send HL as exit code
	ld	c, (iy+KERNEL_THREAD_PPID)
	ld	a, SIGCHLD
	call	ksignal.kill
; need to free IRQ locked and mutex locked to thread
; de = next thread to be active
	ld	a, (kthread_queue_active_size)
	dec	a
	or	a, a
	ld	ix, (iy+KERNEL_THREAD_NEXT)
	jr	nz, .exit_idle
	ld	ix, KERNEL_THREAD_IDLE
.exit_idle:
; remove from active
	ld	hl, kthread_queue_active
	call	kqueue.remove
; unmap the memory of the thread
; this also unmap the stack
	call	kmmu.unmap_block
; that will reset everything belonging to the thread
; I have my next thread
	ld	(kthread_current), ix
; go into the thread directly, without schedule (pop all stack and discard current context)
	jp	kscheduler.context_restore
   	
.sleep:
; hl = time in ms, return 0 is sleept entirely, or approximate time to sleep left
	di
	push	iy
	ld	iy, (kthread_current)
	ld	a, l	; uint8 only
	call	task_switch_sleep_ms
	pop	iy
	call	.yield
; we are back with interrupt
; this one is risky with interrupts
	di
	call	task_delete_timer
	ei
	ld	l, (iy+KERNEL_THREAD_TIMER_COUNT)
; times in jiffies left to sleep
	ld	h, KERNEL_TIME_JIFFIES_TO_MS
	mlt	hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	xor	a, a
	ld	l, h
	ld	h, a
	ret
	
.get_pid:
; REGSAFE and ERRNO compliant
; pid_t getpid()
; return value is register A
	push	hl
	ld	hl, (kthread_current)
	ld	a, (hl)
	pop	hl
	ret
    
.get_ppid:
; REGSAFE and ERRNO compliant
; pid_t getppid()
; return value is register A
	push	iy
	ld	iy, (kthread_current)
	ld	a, (iy+KERNEL_THREAD_PPID)
	pop	iy
	ret
	
.heap_size:
; parse all block
	push	ix
	push	bc
	ld	ix, (kthread_current)
	ld	ix, (ix+KERNEL_THREAD_HEAP)
; sum of all block is the heap size
	or	a, a
	sbc	hl, hl
.heap_size_loop:
	ld	bc, (ix+KERNEL_MEMORY_BLOCK_DATA)
	add	hl, bc
	ld	a, (ix+KERNEL_MEMORY_BLOCK_NEXT+2)
	or	a, a
	jr	z, .heap_size_break
	ld	ix, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	jr	.heap_size_loop
.heap_size_break:
; clean out the upper bit
	ld	bc, 0x800000
	add	hl, bc
	jr	nc, $-1
	pop	bc
	pop	ix
	ret

; DANGEROUS AREA, helper function ;	
	
.reserve_pid:
; find a free pid
; this should be called in an atomic / critical code section to be sure it will still be free when used
; kinda reserved to ASM
	ld	hl, kthread_pid_bitmap
	ld	de, 4
	ld	b, 64
	xor	a, a
.reserve_parse_map:
	cp	a, (hl)
	jr	z, .reserve_exit
	add	hl, de
	djnz	.reserve_parse_map
.reserve_exit:
	srl	l
	srl	l
	ld	a, l
; carry is reset
; if = zero, then we have an error
	ret	nz
	scf
	ret
    
.free_pid:
; free a pid
; this should probably be in critical code section if you don't want BAD STUFF TO HAPPEN
; kinda reserved to ASM
	or	a, a
	ret	z   ; don't you dare free pid 0 !
	sbc	hl, hl
	add	a, a
	add	a, a
	ld	l, a
	ld	de, kthread_pid_bitmap
	add	hl, de
	ld	de, NULL
	ld	(hl), e
	inc	hl
	ld	(hl), de
	ret

; from TASK_STOPPED, TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE to TASK_READY
; may break if not in this state before
; need to be fully atomic
	
.IHEADER:
	db	0x00		; ID 0 reserved
	dl	NULL		; No next
	dl	NULL		; No prev
	db	NULL		; No PPID
	db	0xFF		; IRQ all
	db	TASK_INTERRUPTIBLE	; Status
	dl	0xD000E0	; Stack will be writed at first unschedule
	dl	0xD000A0	; Stack limit
	dl	NULL		; No true heap for idle thread
	dl	NULL		; No friend
	db	NULL
	db	NULL
	dl	NULL
	dl	NULL
	dl	NULL
; descriptor table, initialised to NULL anyway when mapping page...
.IHEADER_END:

task_switch_running:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
	ld	hl, kthread_queue_retire
	call	kqueue.remove
	ld	hl, kthread_queue_active
	jp	kqueue.insert

; from TASK_READY to TASK_STOPPED
; may break if not in this state before
; need to be fully atomic
task_switch_stopped:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_STOPPED
	ld	hl, kthread_queue_active
	call	kqueue.remove
	ld	hl, kthread_queue_retire
	jp	kqueue.insert

; sleep	'a' ms, granularity of about 4,7 ms
task_switch_sleep_ms:
; do  a * (32768/154/1000)
	ld	h, a
	ld	l, KERNEL_TIME_MS_TO_JIFFIES
	mlt	hl
	ld	a, l
	or	a, a
	jr	z, $+3
	inc	h
	inc	h
	ld	a, h
	call	task_add_timer
	
; from TASK_READY to TASK_INTERRUPTIBLE
task_switch_interruptible:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_INTERRUPTIBLE
	ld	hl, kthread_queue_active
	call	kqueue.remove
	ld	hl, kthread_queue_retire
	jp	kqueue.insert
	
task_add_timer:
	ld	hl, klocal_timer.callback_default
	ld	(iy+KERNEL_THREAD_TIMER_CALLBACK), hl
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), a
	ld	hl, klocal_timer_queue	
	jp	klocal_timer.insert

task_delete_timer:
	ld	a, (iy+KERNEL_THREAD_TIMER_COUNT)
	or	a, a
	ret	z	; can't disable, already disabled!
	ld	hl, klocal_timer_queue
	jp	klocal_timer.remove
