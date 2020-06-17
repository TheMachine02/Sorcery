; this header reside in thread memory
; DONT TOUCH ANYTHING YOU DONT WANT TO BREAK IN THIS HEADER
; Atomic is UTERLY important while writing to it
; you can read pid, ppid, irq (but it will not be a *safe value, meaning it can change the next instruction
; for safety dont touch anything here except PID and PPID ;
define	KERNEL_THREAD_HEADER			$00
define	KERNEL_THREAD_PID			$00
define	KERNEL_THREAD_NEXT			$01
define	KERNEL_THREAD_PREVIOUS			$04
define	KERNEL_THREAD_PPID			$07
define	KERNEL_THREAD_IRQ			$08
define	KERNEL_THREAD_STATUS			$09
define	KERNEL_THREAD_PRIORITY			$0A
define	KERNEL_THREAD_QUANTUM			$0B
; static thread data that can be manipulated freely ;
; within it's own thread ... don't manipulate other thread memory, it's not nice ;
; define	KERNEL_THREAD_STACK_LIMIT		$0C
; define	KERNEL_THREAD_STACK			$0F
define	KERNEL_THREAD_HEAP			$12
define	KERNEL_THREAD_TIME			$15
; some stuff ;
define	KERNEL_THREAD_ERRNO			$18
define  KERNEL_THREAD_SIGNAL_MASK		$19
; timer ;
define	KERNEL_THREAD_TIMER			$1D
define	KERNEL_THREAD_TIMER_COUNT		$1D
define	KERNEL_THREAD_TIMER_NEXT		$20
define	KERNEL_THREAD_TIMER_PREVIOUS		$23
define	KERNEL_THREAD_TIMER_SIGEVENT		$26
define	KERNEL_THREAD_TIMER_EV_SIGNOTIFY	$26
define	KERNEL_THREAD_TIMER_EV_SIGNO		$27
define	KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION	$28
define	KERNEL_THREAD_TIMER_EV_NOTIFY_THREAD	$2B
define	KERNEL_THREAD_TIMER_EV_VALUE		$2E
; union with thread sigval ;
define	KERNEL_THREAD_SIGNAL			$2E
define	KERNEL_THREAD_EV_SIG			$2E
define	KERNEL_THREAD_EV_SIG_POINTER		$2F
; other ;
define	KERNEL_THREAD_NICE			$32
define	KERNEL_THREAD_ATTRIBUTE			$33
define	KERNEL_THREAD_JOINED			$34	; joined thread waiting for exit()
; priority waiting list
define	KERNEL_THREAD_LIST_PRIORITY		$35
define	KERNEL_THREAD_LIST			$36

; io waiting queue
define	KERNEL_THREAD_IO			$39

define	KERNEL_THREAD_STACK_LIMIT		$3A
define	KERNEL_THREAD_STACK			$3D
define	KERNEL_THREAD_FILE_DESCRIPTOR		$40
; up to $100, table is 192 bytes or 64 descriptor, 3 reserved as stdin, stdout, stderr ;
; 61 descriptors usables ;

define	KERNEL_THREAD_HEADER_SIZE		$100
define	KERNEL_THREAD_STACK_SIZE		4096	; 3964 bytes usable
define	KERNEL_THREAD_HEAP_SIZE			4096
define	KERNEL_THREAD_FILE_DESCRIPTOR_MAX	64
define	KERNEL_THREAD_IDLE			KERNEL_THREAD
define	KERNEL_THREAD_MQUEUE_COUNT		5
define	KERNEL_THREAD_MQUEUE_SIZE		20

define  THREAD_ONCE_INIT			$FE
define	THREAD_JOIGNABLE			0

define	TASK_READY				0
define	TASK_INTERRUPTIBLE			1	; can be waked up by signal
define	TASK_STOPPED				2	; can be waked by signal only SIGCONT, state of SIGSTOP / SIGTSTP
define	TASK_ZOMBIE				3
define	TASK_UNINTERRUPTIBLE			4
define	TASK_IDLE				255	; special for the scheduler

define	SCHED_PRIO_MAX				0
define	SCHED_PRIO_MIN				12
define	NICE_PRIO_MIN				12
define	NICE_PRIO_MAX				-12

; multilevel priority queue ;
define	kthread_mqueue_0			$D00400
define	kthread_mqueue_0_size			$D00400
define	kthread_mqueue_0_current		$D00401
define	kthread_mqueue_1			$D00404
define	kthread_mqueue_1_size			$D00404
define	kthread_mqueue_1_current		$D00405
define	kthread_mqueue_2			$D00408
define	kthread_mqueue_2_size			$D00408
define	kthread_mqueue_2_current		$D00409
define	kthread_mqueue_3			$D0040C
define	kthread_mqueue_3_size			$D0040C
define	kthread_mqueue_3_current		$D0040D
; retire queue ;
define	kthread_queue_retire			$D00410
define	kthread_queue_retire_size		$D00410
define	kthread_queue_retire_current		$D00411
; timer queue
define	klocal_timer_queue			$D00414
define 	klocal_timer_size			$D00414
define	klocal_timer_current			$D00415

define	kthread_need_reschedule			$D00100
define	kthread_current				$D00101

; please respect these for kinterrupt optimizations ;
assert kthread_current = kthread_need_reschedule + 1
assert kthread_need_reschedule and $FF = 0

; 130 and up is free
; 64 x 4 bytes, D00200 to D00300
define	kthread_pid_map			$D00200

kthread:
.init:
	di
	ld	hl, kthread_mqueue_0
	ld	(hl), l
	ld	de, kthread_mqueue_0 + 1
	ld	bc, KERNEL_THREAD_MQUEUE_SIZE - 1
	ldir
	ld	hl, kthread_need_reschedule
	ld	(hl), e
	inc	hl
	ld	de, KERNEL_THREAD
	ld	(hl), de
; copy idle thread (ie, kernel thread. Stack is kernel stack, code is init kernel)
	ld	hl, .IHEADER
	ld	de, KERNEL_THREAD
	ld	bc, .IHEADER_END - .IHEADER
	ldir
	ld	hl, kthread_pid_map
; permission of thread (thread 0 is all mighty) >> or maybe process ID in the futur and THREAD_PID being TID
	ld	(hl), $01
	inc	hl
	ld	de, KERNEL_THREAD_IDLE
	ld	(hl), de
	inc	hl
	inc	hl
	inc	hl
	ld	(hl), c
	ld	de, kthread_pid_map+5
	ld	c, 251
	ldir
	ret

.yield=kscheduler.yield
	
.create_no_mem:
	call	kmm.thread_unmap
.create_no_pid:
	ld	l, EAGAIN
.create_errno:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), l
; restore register and pop all the stack
	exx
	tstei
	lea	iy, ix+0
	pop	ix
	pop	af
	scf
	sbc	hl, hl
	ret

.create:
; Create a thread
; REGSAFE and ERRNO compliant
; int thread_create(void* thread_entry, void* thread_arg)
; register IY is entry, register HL is send to the stack for void* thread_arg
; error -1 and c set, 0 and nc otherwise, ERRNO set
; HL, BC, DE copied from current context to the new thread
; note, for syscall wrapper : need to grap the pid of the thread and ouptput it to a *thread_t id
	push	af
	push	ix
	tstdi
; save hl, de, bc registers
	exx
	lea	ix, iy+0
	call	.reserve_pid
	jr	c, .create_no_pid
	ld	bc, KERNEL_THREAD_STACK_SIZE/KERNEL_MM_PAGE_SIZE
	call	kmm.thread_map
	jr	c, .create_no_mem
; hl is adress    
	push	hl
	pop	iy
	ld	bc, KERNEL_THREAD_HEAP_SIZE/KERNEL_MM_PAGE_SIZE
	call	kmm.thread_map
	jr	c, .create_no_mem
	push	hl
	ex	(sp), ix
	ld	de, NULL
	ld	(iy+KERNEL_THREAD_PID), a
	ld	(iy+KERNEL_THREAD_IRQ), e
	ld	(iy+KERNEL_THREAD_PRIORITY), SCHED_PRIO_MAX
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
	ld	(iy+KERNEL_THREAD_QUANTUM), 1
	ld	(iy+KERNEL_THREAD_NICE), e
	ld	(iy+KERNEL_THREAD_ATTRIBUTE), e
; sig mask ;
	ld	(iy+KERNEL_THREAD_SIGNAL_MASK), de
	ld	(iy+KERNEL_THREAD_SIGNAL_MASK+3), e
; timer ;
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), de
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_THREAD), iy
; stack limit set first ;
	lea	hl, iy + 4
; we are block aligned. Do +256
	inc	h
; please note write affect memory, so do a + 4 to be safe    
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
; heap (début)
	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), de
	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), de
; stack ;
	lea	hl, iy - 27
	ld	d, KERNEL_THREAD_STACK_SIZE/256
	add	hl, de
	ld	(iy+KERNEL_THREAD_STACK), hl
; heap (suite)
	ld	(iy+KERNEL_THREAD_HEAP), ix
	ld	de, KERNEL_THREAD_HEAP_SIZE - KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), de
	lea	de, ix+KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), de
	pop	ix
; map the thread to be transparent to the scheduler
; iy is thread adress, a is still PID    
; map the pid
	add	a, a
	add	a, a
	sbc	hl, hl
	ld	l, a
	ld	de, kthread_pid_map
	add	hl, de
	ld	(hl), $FF
	inc	hl
	ld	(hl), iy
; write parent pid    
	ld	hl, (kthread_current)
	ld	a, (hl)
	ld	(iy+KERNEL_THREAD_PPID), a
; setup the queue
; insert the thread to the ready queue
	ld	hl, kthread_mqueue_0
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call   kqueue.insert_head
; setup the stack \o/
	ld	de, KERNEL_THREAD_STACK_SIZE
	add	iy, de
	ld	hl, .exit
	ld	(iy-6), hl
	ld	(iy-9), ix
	ld	d,e			; ld	de, NULL
	ld	(iy-12), de		; ix [NULL] > int argc, char *argv[]
	ld	(iy-15), de		; iy [NULL] > in the future
	ld	(iy-27), de		; af [NULL] > TODO
	exx
; this can be grab with call __frameset0 \ ld hl, (ix+6) \ pop ix
	ld	(iy-3), hl
; note, we don't care for ASM thread at all, we have hl, bc, de already
	ld	(iy-18), hl
	ld	(iy-21), bc
	ld	(iy-24), de
	tstei
	lea	iy, ix+0
	pop	ix
	pop	af
	or	a, a
	sbc	hl, hl
	ret

.wait_on_IRQ:
; suspend till waked by an IRQ
	di
	push	iy
	push	hl
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_IRQ), a
; the process to write the thread state and change the queue should be always a critical section
	call	task_switch_uninterruptible
	pop	hl
	pop	iy
; switch away from current thread to a new active thread
; cause should already have been writed
	jp	task_yield

.resume_from_IRQ:
; resume a thread waiting IRQ
; interrupt should be DISABLED when calling this routine
; save a
	ld	e, a
	lea	hl, iy+KERNEL_THREAD_IRQ
	ld	a, (hl)
	or	a, a
	jr	z, .resume_from_IRQ_exit
	ld	(hl), 0
	inc	hl
	ld	a, (hl)
	cp	a, TASK_UNINTERRUPTIBLE
	jr	nz, .resume_from_IRQ_exit
	ld	ix, (iy+KERNEL_THREAD_PREVIOUS)
	call	task_switch_running
	ld	a, $FF
	ld	(kthread_need_reschedule), a
	lea	iy, ix+0
.resume_from_IRQ_exit:
; restore a
	ld	a, e
; return ix = iy = previous thread in the thread queue
	or	a, a
	ret
	
.suspend:
; suspend till waked by a signal or by an IRQ (you should have writed the one you are waiting for before though and atomically, also, IRQ signal will be reset by IRQ handler, not by wake
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
	jp	task_yield
	
.resume:
; wake thread (adress iy)
; destroy hl, a (probably more)
	lea	hl, iy+0
	add	hl, de
	or	a, a
	sbc	hl, de
	ret	z
	ld	hl, i
	push	af
; this read need to be atomic !
	ld	a, (iy+KERNEL_THREAD_STATUS)
; can't wake TASK_READY (0) and TASK_STOPPED (2) and TASK_ZOMBIE (3)
	cp	a, TASK_INTERRUPTIBLE
	jr	z, .resume_wake
	cp	a, TASK_UNINTERRUPTIBLE
	jr	nz, .resume_exit
.resume_wake:
	call	task_switch_running
	ld	a, $FF
	ld	(kthread_need_reschedule), a
.resume_exit:
	pop	af
	ret	po
	ei
	ret

.join:
; hl = pthread_id, de pointer to pointer to exit value
	push	ix
	add	hl, hl
	add	hl, hl
	ld	bc, kthread_pid_map
	add	hl, bc
	di
	ld	a, (hl)
	or	a, a
	jr	z, .join_no_thread
	inc	hl
	ld	ix, (hl)
	bit	THREAD_JOIGNABLE, (ix+KERNEL_THREAD_ATTRIBUTE)
	jr	z, .join_detached
	ld	a, (ix+KERNEL_THREAD_JOINED)
	or	a, a
	jr	nz, .join_watching
	ld	iy, (kthread_current)
	lea	hl, ix+0
	lea	bc, iy+0
	or	a, a
	sbc	hl, bc
	jr	z, .join_itself
	ld	a, (bc)
	ld	(ix+KERNEL_THREAD_JOINED), a
; check status
	ld	a, (ix+KERNEL_THREAD_STATUS)
	cp	a, TASK_ZOMBIE
	jr	z, .join_exit
.join_block:
	call	task_switch_interruptible	; we may be waked by signal, etc
	call	task_yield
	di
	ld	a, (ix+KERNEL_THREAD_STATUS)
	cp	a, TASK_ZOMBIE
	jr	nz, .join_block
.join_exit:
	push	de
	lea	iy, ix+0
	call	task_switch_running
	ld	iy, (iy+KERNEL_THREAD_STACK)
	ld	de, (iy+9)	; this is hl
	ei
	pop	hl
	ld	(hl), de
	or	a, a
	sbc	hl, hl
	pop	ix
	ret
.join_no_thread:
	ld	a, ESRCH
	jr	.join_errno
.join_itself:
	ld	a, EDEADLK
	jr	.join_errno
.join_detached:
.join_watching:
	ld	a, EINVAL
.join_errno:
	ei
	ld	(iy+KERNEL_THREAD_ERRNO), a
	or	a, a
	sbc	hl, hl
	ld	l, a
	pop	ix
	ret

.once:
; int pthread_once(pthread_once_t *once_control, void (*init_routine) (void));   
; de point to the init routine, hl point to *once_control, destroy all reg based on the init routine
; return hl=0
; else swap de and hl
	sra	(hl)	; tst and set, that's magiiic
	ex	de, hl
	call	nc, .once_call
	or	a, a
	sbc	hl, hl
	ret
.once_call:
	jp	(hl)
	
.core:

.exit:
; signal parent thread of the end of the child thread
; also send HL as exit code
	di
	ld	iy, (kthread_current)
	bit	THREAD_JOIGNABLE, (iy+KERNEL_THREAD_ATTRIBUTE)
	jr	z, .exit_clean
; if we have a thread * currently * watching, wake it up
	push	hl
	ld	a, (iy+KERNEL_THREAD_JOINED)
	or	a, a
	jr	z, .exit_make_zombie_bunny
	add	a, a
	add	a, a
	sbc	hl, hl
	ld	l, a
	ld	bc, kthread_pid_map
	add	hl, bc
	ld	a, (hl)
; sanity check ;
	or	a, a
	jr	z, .exit_make_zombie_bunny
	push	iy
	inc	hl
	ld	iy, (hl)
; should be sleeping if joined, but anyway, extra check	
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_INTERRUPTIBLE
	call	z, task_switch_running
	pop	iy
.exit_make_zombie_bunny:
	call	task_switch_zombie
	pop	hl
	call	task_yield
.exit_clean:
; interrupts should be definitely stopped here !
	di
	ld	c, (iy+KERNEL_THREAD_PPID)
	ld	a, SIGCHLD
	call	ksignal.kill
; first disable stack protector (load the kernel_stack stack protector)
	ld	a, $B0
	out0	($3A), a
	ld	a, $00
	out0	($3B), a
	ld	a, $D0
	out0	($3C), a
	ld	sp, (KERNEL_STACK)
	ld	a, (iy+KERNEL_THREAD_PID)
	call	.free_pid
; need to free IRQ locked and mutex locked to thread
; TODO ;
; remove from active
	ld	hl, kthread_mqueue_0
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
; find next to schedule
; ie dispatch method from schedule
; b = 16 - l / 4
	push	hl
; unmap the memory of the thread
; this also unmap the stack
	ld	a, (iy+KERNEL_THREAD_PID)
	call	kmm.thread_unmap
; that will reset everything belonging to the thread
	pop	hl
	ld	a, 16
	sub	a, l
	rrca
	rrca
	ld	d, a
	ld	bc, QUEUE_SIZE
	xor	a, a
.exit_dispatch_loop:
	or	a, (hl)
	jr	nz, .exit_dispatch_thread
	add	hl, bc
	dec	d
	jr	nz, .exit_dispatch_loop
	or	a, (hl)
	jp	z, kinterrupt.nmi
; schedule the idle thread
	ld	de, KERNEL_THREAD_IDLE
	jp	kscheduler.context_restore
.exit_dispatch_thread:
	inc	hl
	ld	de, (hl)
; go into the thread directly, without schedule (pop all stack and discard current context)
	jp	kscheduler.context_restore
   	
.sleep:
; hl = time in ms, return 0 is sleept entirely, or approximate time to sleep left
	di
	push	iy
	push	de
	push	af
	ld	iy, (kthread_current)
	call	task_switch_sleep_ms
	call	task_yield
; we are back with interrupt
; this one is risky with interrupts, so disable them the time to do it
	di
	ld	hl, (iy+KERNEL_THREAD_TIMER_COUNT)
	push	hl
	ld	a, l
	or	a, h
	lea	iy, iy+KERNEL_THREAD_TIMER
	call	nz, klocal_timer.remove
	lea	iy, iy-KERNEL_THREAD_TIMER
	ld	hl, NULL
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), hl
	pop	hl
	ei
	ld	e, l
; times in jiffies left to sleep
	ld	d, TIME_JIFFIES_TO_MS
	mlt	de
	ex	de, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ex	de, hl
	xor	a, a
	ld	e, d
	ld	d, a
	ld	l, TIME_JIFFIES_TO_MS
	mlt	hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, de
	pop	af
	pop	de
	pop	iy
	ret
	
.get_pid:
; REGSAFE and ERRNO compliant
; pid_t getpid()
; return value is register hl
	push	af
	ld	hl, (kthread_current)
	ld	a, (hl)
	or	a, a
	sbc	hl, hl
	ld	l, a
	pop	af
	ret
    
.get_ppid:
; REGSAFE and ERRNO compliant
; pid_t getppid()
; return value is register hl
	push	iy
	ld	iy, (kthread_current)
	or	a, a
	sbc	hl, hl
	ld	l, (iy+KERNEL_THREAD_PPID)
	pop	iy
	ret
	
.get_heap_size:
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
	ld	bc, KERNEL_MEMORY_BLOCK_SIZE
	add	hl, bc
	ld	a, (ix+KERNEL_MEMORY_BLOCK_NEXT+2)
	or	a, a
	jr	z, .heap_size_break
	ld	ix, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	jr	.heap_size_loop
.heap_size_break:
; clean out the upper bit
	ld	bc, $800000
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
	ld	hl, kthread_pid_map
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
	add	a, a
	ret	z   ; don't you dare free pid 0 !
	add	a, a
	sbc	hl, hl
	ld	l, a
	ld	de, kthread_pid_map
	add	hl, de
	ld	de, NULL
	ld	(hl), e
	inc	hl
	ld	(hl), de
	ret
	
.IHEADER:
	db	$00			; ID 0 reserved
	dl	KERNEL_THREAD_IDLE	; No next
	dl	KERNEL_THREAD_IDLE	; No prev
	db	NULL			; No PPID
	db	$FF			; IRQ all
	db	TASK_IDLE		; Status
	db	SCHED_PRIO_MIN		; Special anyway
	db	$FF			; quantum
	dl	$D000E0			; Stack will be writed at first unschedule
	dl	$D000A0			; Stack limit
	dl	NULL			; No true heap for idle thread
	dl	NULL			; No friend
	db	NULL			; Errno
	db	NULL			; Sig
	dl	NULL			; Sig
	dw	NULL, NULL		; Sig mask 
; rest is useless for idle thread
.IHEADER_END:

task_yield = kthread.yield

; from TASK_READY to TASK_UNINTERRUPTIBLE
; may break if not in this state before
; need to be fully atomic
task_switch_uninterruptible:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_UNINTERRUPTIBLE
	ld	hl, kthread_mqueue_0
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jr	kqueue.insert_head

; from TASK_READY to TASK_ZOMBIE
; may break if not in this state before
; need to be fully atomic
task_switch_zombie:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_ZOMBIE
	ld	hl, kthread_mqueue_0
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jr	kqueue.insert_head

; from TASK_READY to TASK_STOPPED
; may break if not in this state before
; need to be fully atomic
task_switch_stopped:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_STOPPED
	ld	hl, kthread_mqueue_0
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jr	kqueue.insert_head

; sleep	'hl' ms, granularity of about 9 ms
task_switch_sleep_ms:
; do  hl * (32768/154/1000)
	ld	e, l
	ld	d, TIME_MS_TO_JIFFIES
	mlt	de
	ld	a, e
	or	a, a
	jr	z, $+3
	inc	d
	ld	e, d
	ld	d, 0
	ld	l, TIME_MS_TO_JIFFIES
	mlt	hl
	add	hl, de
; add timer
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), hl
	ld	(iy+KERNEL_THREAD_TIMER_EV_SIGNOTIFY), SIGEV_THREAD
	ld	hl, klocal_timer.notify_default
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION), hl
	lea	iy, iy+KERNEL_THREAD_TIMER
	call	klocal_timer.insert
	lea	iy, iy-KERNEL_THREAD_TIMER
	
; from TASK_READY to TASK_INTERRUPTIBLE
task_switch_interruptible:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_INTERRUPTIBLE
	ld	hl, kthread_mqueue_0
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jr	kqueue.insert_head

; from TASK_STOPPED, TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE to TASK_READY
; may break if not in this state before
; need to be fully atomic
task_switch_running:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
	ld	hl, kthread_queue_retire
	call	kqueue.remove
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
assert kqueue.insert_head = $
;	jr	kqueue.insert_head
