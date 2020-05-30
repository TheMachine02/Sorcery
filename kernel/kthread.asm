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
; static thread data that can be manipulated freely ;
; within it's own thread ... don't manipulate other thread memory, it's not nice ;
define	KERNEL_THREAD_STACK_LIMIT		$0B
define	KERNEL_THREAD_STACK			$0E
define	KERNEL_THREAD_HEAP			$11
define	KERNEL_THREAD_TIME			$14
define	KERNEL_THREAD_ERRNO			$17
define	KERNEL_THREAD_SIGNAL			$18
define	KERNEL_THREAD_EV_SIG			$18
define	KERNEL_THREAD_EV_SIG_POINTER		$19
define  KERNEL_THREAD_SIGNAL_MASK		$1C
define	KERNEL_THREAD_TIMER			$20
define	KERNEL_THREAD_TIMER_COUNT		$20
define	KERNEL_THREAD_TIMER_NEXT		$21
define	KERNEL_THREAD_TIMER_PREVIOUS		$24
define	KERNEL_THREAD_TIMER_EV_SIGNOTIFY	$27
define	KERNEL_THREAD_TIMER_EV_SIGNO		$28
define	KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION	$29
define	KERNEL_THREAD_FILE_DESCRIPTOR		$2F
; up to $80, table is 81 bytes or 27 descriptor, 3 reserved as stdin, stdout, stderr ;
; 24 descriptors usables ;

define	KERNEL_THREAD_HEADER_SIZE		$80
define	KERNEL_THREAD_STACK_SIZE		4096	; 3964 bytes usable
define	KERNEL_THREAD_HEAP_SIZE			4096
define	KERNEL_THREAD_FILE_DESCRIPTOR_MAX	27
define	KERNEL_THREAD_IDLE			KERNEL_THREAD

define	TASK_READY				0
define	TASK_INTERRUPTIBLE			1    ; can be waked up by signal
define	TASK_STOPPED				2    ; can be waked by signal only SIGCONT, state of SIGSTOP / SIGTSTP

define	SCHED_PRIO_MAX				0
define	SCHED_PRIO_MIN				63

define  KERNEL_THREAD_ONCE_INIT			$FE

define	kthread_queue_active			$D00100
define	kthread_queue_active_size		$D00100
define	kthread_queue_active_current		$D00101

define	kthread_queue_retire			$D00104
define	kthread_queue_retire_size		$D00104
define	kthread_queue_retire_current		$D00105

define	kthread_need_reschedule			$D00108
define	kthread_current				$D00109

; 130 and up is free
; 64 x 4 bytes, D00200 to D00300
define	kthread_pid_bitmap			$D00200

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
	xor	a, a
	ld	(kthread_need_reschedule), a
; copy idle thread (ie, kernel thread. Stack is kernel stack, code is init kernel)
	ld	hl, .IHEADER
	ld	de, KERNEL_THREAD
	ld	bc, .IHEADER_END - .IHEADER
	ldir
	ld	hl, kthread_pid_bitmap
; permission of thread (thread 0 is all mighty) >> or maybe process ID in the futur and THREAD_PID being TID
	ld	(hl), $01
	inc	hl
	ld	de, KERNEL_THREAD_IDLE
	ld	(hl), de
	inc	hl
	inc	hl
	inc	hl
	ld	(hl), $00
	ld	de, kthread_pid_bitmap+5
	ld	bc, 251
	ldir
	pop	af
	ret	po
	ei
	ret

.yield=kscheduler.yield
	
.create_no_mem:
	call	kmmu.unmap_block_thread
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
; void thread_create(void* thread_entry, void* thread_arg)
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
	ld	hl, KERNEL_MMU_RAM
	ld	b, KERNEL_THREAD_STACK_SIZE/KERNEL_MMU_PAGE_SIZE
	call	kmmu.map_block_thread
	jr	c, .create_no_mem
; hl is adress    
	push	hl
	pop	iy
	ld	b, KERNEL_THREAD_HEAP_SIZE/KERNEL_MMU_PAGE_SIZE
	call	kmmu.map_block_thread
	jr	c, .create_no_mem
	push	hl
	ex	(sp), ix
	ld	(iy+KERNEL_THREAD_PID), a
	ld	(iy+KERNEL_THREAD_IRQ), 0
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
; sig mask ;
	ld	(iy+KERNEL_THREAD_SIGNAL_MASK), 0
	ld	(iy+KERNEL_THREAD_SIGNAL_MASK+1), 0
	ld	(iy+KERNEL_THREAD_SIGNAL_MASK+2), 0
	ld	(iy+KERNEL_THREAD_SIGNAL_MASK+3), 0
; timer ;
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), 0
; stack limit set first ;
	lea	hl, iy + 4
	ld	de, KERNEL_THREAD_HEADER_SIZE
	add	hl, de
; please note write affect memory, so do a + 4 to be safe    
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
; stack ;
	lea	hl, iy - 27
	ld	de, KERNEL_THREAD_STACK_SIZE
	add	hl, de
	ld	(iy+KERNEL_THREAD_STACK), hl
; heap ;
	lea	hl, ix + 0
	ld	(iy+KERNEL_THREAD_HEAP), hl
	ld	de, KERNEL_THREAD_HEAP_SIZE - KERNEL_MEMORY_BLOCK_SIZE
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
	ld	(hl), $FF
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
	ld	(iy-6), hl
	ld	(iy-9), ix
	ld	de, NULL
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
	call	task_switch_interruptible
	pop	hl
	pop	iy
; switch away from current thread to a new active thread
; cause should already have been writed
	jp	task_yield

.resume_from_IRQ:
; resume a thread waiting IRQ
; interrupt should be DISABLED when calling this routine
	push	af
	ld	ix, (iy+KERNEL_THREAD_PREVIOUS)
	ld	a, (iy+KERNEL_THREAD_IRQ)
	ld	(iy+KERNEL_THREAD_IRQ), 0
	or	a, a
	jr	z, .resume_from_IRQ_exit
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_INTERRUPTIBLE
	jr	nz, .resume_from_IRQ_exit
	call	task_switch_running
	ld	a, $FF
	ld	(kthread_need_reschedule), a
.resume_from_IRQ_exit:
	pop	af
	lea	iy, ix+0
; return ix = iy = previous thread in the thread queue
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
	ld	a, $FF
	ld	(kthread_need_reschedule), a
.resume_exit_atomic:
	tstei
.resume_exit:
	pop	hl
	pop	af
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
	di
	ld	sp, (KERNEL_STACK)
; first disable stack protector (load the kernel_stack stack protector)
	ld	a, $B0
	out0	($3A), a
	ld	a, $00
	out0	($3B), a
	ld	a, $D0
	out0	($3C), a
	ld	iy, (kthread_current)
	ld	a, (iy+KERNEL_THREAD_PID)
	push	hl
	call	.free_pid
	pop	hl
; signal parent thread of the end of the child thread
; also send HL as exit code
	ld	c, (iy+KERNEL_THREAD_PPID)
	ld	a, SIGCHLD
	call	kill
; need to free IRQ locked and mutex locked to thread
; de = next thread to be active
; remove from active
	ld	hl, kthread_queue_active
	call	kqueue.remove
; find next to schedule
	ld	a, (hl)
	or	a, a
	inc	hl
	ld	ix, (hl)
	jr	nz, .exit_idle
	ld	ix, KERNEL_THREAD_IDLE
.exit_idle:
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
	call	task_yield
; we are back with interrupt
; this one is risky with interrupts, so disable them the time to do it
	di
	call	task_delete_timer
	ei
	ld	l, (iy+KERNEL_THREAD_TIMER_COUNT)
; times in jiffies left to sleep
	ld	h, TIME_JIFFIES_TO_MS
	mlt	hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	xor	a, a
	ld	l, h
	ld	h, a
	pop	iy
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
	
.IHEADER:
	db	$00		; ID 0 reserved
	dl	NULL		; No next
	dl	NULL		; No prev
	db	NULL		; No PPID
	db	$FF		; IRQ all
	db	TASK_INTERRUPTIBLE	; Status
	db	SCHED_PRIO_MIN
	dl	$D000E0	; Stack will be writed at first unschedule
	dl	$D000A0	; Stack limit
	dl	NULL		; No true heap for idle thread
	dl	NULL		; No friend
	db	NULL
	db	NULL
	dl	NULL
	dl	NULL
	dl	NULL
; descriptor table, initialised to NULL anyway when mapping page...
.IHEADER_END:

; from TASK_STOPPED, TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE to TASK_READY
; may break if not in this state before
; need to be fully atomic
task_switch_running:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
	ld	hl, kthread_queue_retire
	call	kqueue.remove
	ld	l, kthread_queue_active and $FF
	jp	kqueue.insert

; from TASK_READY to TASK_STOPPED
; may break if not in this state before
; need to be fully atomic
task_switch_stopped:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_STOPPED
	ld	hl, kthread_queue_active
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jp	kqueue.insert

; sleep	'a' ms, granularity of about 4,7 ms
task_switch_sleep_ms:
; do  a * (32768/154/1000)
	ld	h, a
	ld	l, TIME_MS_TO_JIFFIES
	mlt	hl
	ld	a, l
	or	a, a
	jr	z, $+3
	inc	h
	ld	a, h
	call	task_add_timer
	
; from TASK_READY to TASK_INTERRUPTIBLE
task_switch_interruptible:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_INTERRUPTIBLE
	ld	hl, kthread_queue_active
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jp	kqueue.insert
	
task_yield = kthread.yield
	
task_add_timer:
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), a
	ld	a, SIGEV_THREAD
	ld	(iy+KERNEL_THREAD_TIMER_EV_SIGNOTIFY), a
	ld	hl, klocal_timer.notify_default
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION), hl
	ld	hl, klocal_timer_queue	
	jp	klocal_timer.insert

task_delete_timer:
	ld	a, (iy+KERNEL_THREAD_TIMER_COUNT)
	or	a, a
	ret	z	; can't disable, already disabled!
	ld	hl, klocal_timer_queue
	jp	klocal_timer.remove
