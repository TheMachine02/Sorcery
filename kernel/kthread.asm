; this header reside in thread memory
; DONT TOUCH ANYTHING YOU DONT WANT TO BREAK IN THIS HEADER
; Atomic is UTERLY important while writing to it
; you can read pid, ppid, irq (but it will not be a *safe value, meaning it can change the next instruction
; for safety dont touch anything here except PID and PPID ;
define	KERNEL_THREAD_HEADER_SIZE           0x20
define	KERNEL_THREAD_HEADER                0x00
define	KERNEL_THREAD_PID                   0x00
define	KERNEL_THREAD_NEXT                  0x01
define	KERNEL_THREAD_PREVIOUS              0x04
define	KERNEL_THREAD_PPID                  0x07
define	KERNEL_THREAD_IRQ                   0x08
define	KERNEL_THREAD_STATUS                0x09
; static thread data that can be manipulated freely ;
define	KERNEL_THREAD_STACK_LIMIT           0x0A
define	KERNEL_THREAD_STACK                 0x0D
define	KERNEL_THREAD_HEAP                  0x10
define	KERNEL_THREAD_TIMING                0x13
define	KERNEL_THREAD_ERRNO		    0x16
define	KERNEL_THREAD_SIGNAL_MESSAGE	    0x17
define  KERNEL_THREAD_SIGNAL_MASK	    0x1A
; 8 bytes ;
; signal mask ;
; 0x20 first bytes

define	KERNEL_THREAD_STACK_SIZE            4096

define	KERNEL_THREAD_IDLE                  KERNEL_THREAD

define	TASK_RUNNING             0
define	TASK_INTERRUPTIBLE       1    ; can be waked up by signal
define	TASK_STOPPED             2    ; can be waked by signal only SIGCONT, state of SIGSTOP / SIGTSTP

define	kqueue_active                       0xD00100
define	kqueue_active_size                  0xD00100
define	kqueue_active_current               0xD00101

define	kqueue_retire                       0xD00104
define	kqueue_retire_size                  0xD00104
define	kqueue_retire_current               0xD00105

define	kthread_current                     0xD00108
define	kthread_need_reschedule             0xD0010B

; 130 and up is free
; 64 x 4 bytes, D00200 to D00300
define	kthread_pid_bitmap                  0xD00200

kthread:
.init:
	tstdi
	xor	a, a
	ld	de, NULL
	ld	hl, kqueue_active
	ld	(hl), a
	inc	hl
	ld	(hl), de
	ld	hl, kqueue_retire
	ld	(hl), a
	inc	hl
	ld	(hl), de
	ld	de, KERNEL_THREAD
	ld	(kthread_current), de
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
	
.create_error_free:
	pop	hl
	call	kmmu.unmap_block_thread
.create_error:
	ei
	scf
	ret

.create:
; iy thread code
	tstdi
; push all register into the stack > thread creation preserve all register
; except : IX = THREAD code adress, IY = STACK
; insert it in active list
	exx
	ex	af, af' ; save registers
	lea	ix, iy+0
	call	.reserve_pid
	jr	c, .create_error
	ld	hl, KERNEL_MMU_RAM
	ld	b, KERNEL_THREAD_STACK_SIZE/KERNEL_MMU_PAGE_SIZE
	call	kmmu.map_block_thread
	jr	c, .create_error
; hl is adress    
	push	hl
	push	hl
	pop	iy
	ld	(iy+KERNEL_THREAD_PID), a
	ld	(iy+KERNEL_THREAD_IRQ), 0
	ld	(iy+KERNEL_THREAD_STATUS), TASK_RUNNING
	lea	hl, iy - 24
	ld	de, KERNEL_THREAD_STACK_SIZE
	add	hl, de
	ld	(iy+KERNEL_THREAD_STACK), hl
	lea	hl, iy+KERNEL_THREAD_HEADER_SIZE + 4
; stack protector ;
; please note write affect memory, so do a + 4 to be safe    
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
	call	kmmu.create_heap
	jr	c, .create_error_free
	ld	(iy+KERNEL_THREAD_HEAP), hl
; iy is thread adress, a is still PID    
; map the pid
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
	ld	de, KERNEL_THREAD_STACK_SIZE
	add	iy, de
	ld	hl, .exit
	ld	(iy-3), hl
	ld	(iy-6), ix
	exx
	ex	af, af'
	ld	(iy-9), ix
	ld	(iy-12), iy
	ld	(iy-15), hl
	ld	(iy-18), bc
	ld	(iy-21), de
	push	af
	pop	hl
	ld	(iy-24), hl
	pop	iy
; insert into the active list and yield to this newly created thread
	ld	hl, kqueue_active
	call   kqueue.insert
	retei
; iy = thread
    
.suspend:
; suspend till waked by a signal or by an IRQ (you should have writed the one you are waiting for before though)
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
	jp	kthread.yield
	
.resume:
; wake thread (adress iy)
; insert in place in the RR list
; return iy = kqueue_current
	push	hl
	push	af
	lea	hl, iy+0
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .resume_exit
	tstdi
	ld	a, (iy+KERNEL_THREAD_STATUS)    ; this read need to be atomic !
	cp	a, TASK_INTERRUPTIBLE
; can't wake TASK_RUNNING (0) and TASK_STOPPED (2)
; range -1 > 1
; if a=2 , nc, if a=255, nc, else c
	jr	nz, .resume_exit_atomic
	call	task_switch_running
	ld	a, 0xFF
	ld	(kthread_need_reschedule), a
.resume_exit_atomic:
	tstei
.resume_exit:
	pop af
	pop hl
	ret
	
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
	call	.free_pid
; signal parent thread of the end of the child thread
	ld	c, (iy+KERNEL_THREAD_PPID)
	ld	a, SIGCHLD
	call	ksignal.kill
; need to free IRQ locked and mutex locked to thread
	
; de = next thread to be active
	ld	a, (kqueue_active_size)
	dec	a
	or	a, a
	ld	ix, (iy+KERNEL_THREAD_NEXT)
	jr	nz, .exit_idle
	ld	ix, KERNEL_THREAD_IDLE
.exit_idle:
; remove from active
	ld	hl, kqueue_active
	call	kqueue.remove
; unmap the memory of the thread
; this also unmap the stack
	call	kmmu.unmap_block
; that will reset everything belonging to the thread
; I have my next thread
	ld	(kthread_current), ix
; go into the thread directly, without schedule (pop all stack and discard current context)
	jp	kscheduler.context_restore
   
.core:
	jp	.exit
   
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

; from TASK_STOPPED, TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE to TASK_RUNNING
; may break if not in this state before
; need to be fully atomic
	
.IHEADER:
	db	0x00		; ID 0 reserved
	dl	NULL		; No next
	dl	NULL		; No prev
	db	NULL		; No PPID
	db	0xFF		; IRQ all
	db	TASK_INTERRUPTIBLE	; Status : running
	dl	0xD000A0	; Stack limit
	dl	0xD000E0	; Stack will be writed at first unschedule
	dl	NULL		; No true heap for idle thread
	dl	NULL		; No friend
.IHEADER_END:

task_switch_running:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_RUNNING
	ld	hl, kqueue_retire
	call	kqueue.remove
	ld	hl, kqueue_active
	jp	kqueue.insert

; from TASK_RUNNING to TASK_STOPPED
; may break if not in this state before
; need to be fully atomic
task_switch_stopped:
	ld (iy+KERNEL_THREAD_STATUS), TASK_STOPPED
	ld	hl, kqueue_active
	call	kqueue.remove
	ld	hl, kqueue_retire
	jp	kqueue.insert

; from TASK_RUNNING to TASK_INTERRUPTIBLE
task_switch_interruptible:
	ld (iy+KERNEL_THREAD_STATUS), TASK_INTERRUPTIBLE
	ld	hl, kqueue_active
	call	kqueue.remove
	ld	hl, kqueue_retire
	jp	kqueue.insert
