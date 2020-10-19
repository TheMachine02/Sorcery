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
define	KERNEL_THREAD_STACK_LIMIT		$0C
define	KERNEL_THREAD_BREAK			$0C
define	KERNEL_THREAD_STACK			$0F
define	KERNEL_THREAD_HEAP			$12
define	KERNEL_THREAD_TIME			$15
; some stuff ;
define	KERNEL_THREAD_ERRNO			$18
define  KERNEL_THREAD_SIGNAL_MASK		$19
; timer ;
define	KERNEL_THREAD_TIMER			$1D
define	KERNEL_THREAD_TIMER_FLAGS		$1D
define	KERNEL_THREAD_TIMER_NEXT		$1E
define	KERNEL_THREAD_TIMER_PREVIOUS		$21
define	KERNEL_THREAD_TIMER_COUNT		$24
define	KERNEL_THREAD_TIMER_SIGEVENT		$27
define	KERNEL_THREAD_TIMER_EV_SIGNOTIFY	$27
define	KERNEL_THREAD_TIMER_EV_SIGNO		$28
define	KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION	$29
define	KERNEL_THREAD_TIMER_EV_NOTIFY_THREAD	$2C
define	KERNEL_THREAD_TIMER_EV_VALUE		$2F
; union with thread sigval ;
define	KERNEL_THREAD_SIGNAL			$2F
define	KERNEL_THREAD_EV_SIG			$2F
define	KERNEL_THREAD_EV_SIG_POINTER		$30
; other ;
define	KERNEL_THREAD_NICE			$33
define	KERNEL_THREAD_ATTRIBUTE			$34
define	KERNEL_THREAD_JOINED			$35	; joined thread waiting for exit()
; thread waiting ;
define	KERNEL_THREAD_IO			$36
define	KERNEL_THREAD_LIST_DATA			$36
define	KERNEL_THREAD_LIST_NEXT			$37
define	KERNEL_THREAD_LIST_PREVIOUS		$3A
define	KERNEL_THREAD_PROFIL_STRUCTURE		$3D
define	KERNEL_THREAD_WORKING_DIRECTORY		$40	; pointer to the directory inode
define	KERNEL_THREAD_TIME_CHILD		$43
define	KERNEL_THREAD_FILE_DESCRIPTOR		$46	; file descriptor table, TODO : move it to allocated kmem_cache
; up to $100, table is 189 bytes or 23 descriptor, 3 reserved as stdin, stdout, stderr ;
; 21 descriptors usables ;

define	KERNEL_THREAD_HEADER_SIZE		$100
define	KERNEL_THREAD_STACK_SIZE		8192	; 3964 bytes usable
define	KERNEL_THREAD_FILE_DESCRIPTOR_MAX	22
define	KERNEL_THREAD_MQUEUE_COUNT		5
define	KERNEL_THREAD_MQUEUE_SIZE		20

define	THREAD_JOIGNABLE			0
define	THREAD_PROFIL				1

define	TASK_READY				0
define	TASK_INTERRUPTIBLE			1	; can be waked up by signal
define	TASK_UNINTERRUPTIBLE			2
define	TASK_STOPPED				3	; can be waked by signal only SIGCONT, state of SIGSTOP / SIGTSTP
define	TASK_ZOMBIE				4
define	TASK_IDLE				255	; special for the scheduler

define	SCHED_PRIO_MAX				0
define	SCHED_PRIO_MIN				12
define	NICE_PRIO_MIN				19
define	NICE_PRIO_MAX				-20

define	ROOT_USER				$01

define	WNOHANG					1
define	WUNTRACED				2
define	WCONTINUED				4

kthread:

.create_no_mem:
	call	kmm.thread_unmap
.create_no_pid:
	ld	l, EAGAIN
.create_errno:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), l
; restore register and pop all the stack
	exx
	ei
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
; please note that you can't call create thread in a interrupt disabled context
	ld	a, i
	push	af
	push	ix
	di
; save hl, de, bc registers
	exx
	lea	ix, iy+0
	call	.reserve_pid
	jr	c, .create_no_pid
	ld	bc, (KERNEL_THREAD_STACK_SIZE/KERNEL_MM_PAGE_SIZE) or (KERNEL_MM_GFP_USER shl 8)
	call	kmm.thread_map
	jr	c, .create_no_mem
; hl is adress    
	ex	de, hl
	ld	iy, 0
	add	iy, de
; setup the default parameter
	ld	bc, $100
	ld	hl, KERNEL_MM_NULL
	ldir
	ld	(iy+KERNEL_THREAD_QUANTUM), 1
	ld	(iy+KERNEL_THREAD_PID), a
	ld	(iy+KERNEL_THREAD_PRIORITY), c	; SCHED_PRIO_MAX = 0
	ld	(iy+KERNEL_THREAD_STATUS), c	; TASK_READY = 0
	ld	hl, kvfs_root
	ld	(iy+KERNEL_THREAD_WORKING_DIRECTORY), hl
; increase reference count of directory
	ld	c, KERNEL_VFS_INODE_REFERENCE
	add	hl, bc
	inc	(hl)
; sig parameter mask ;
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_THREAD), iy
; we are memory aligned
; please note write affect memory, so do a iy + 256 + 13 stack limit to be safe, boot code need some stack left
; note : we have TLS : Heap : Break = Stack limit : Stack
	lea	hl, iy + 13
	inc	h
; also brk
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
	ld	(iy+KERNEL_THREAD_HEAP), hl
; the stack adress is iy + STACK_SIZE - 27
	lea	hl, iy-27
	ld	bc, KERNEL_THREAD_STACK_SIZE
	add	hl, bc
	ld	(iy+KERNEL_THREAD_STACK), hl
; map the thread to be transparent to the scheduler
; iy is thread adress, a is still PID    
; map the pid
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	ld	(hl), $FF
	inc	hl
	ld	(hl), iy
; write parent pid    
	ld	hl, kthread_current
	lea	de, iy+KERNEL_THREAD_PPID
	ldi
; setup the queue
; insert the thread to the ready queue
	ld	h, ( kthread_mqueue_active and $00FF00 ) shr 8
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call   kqueue.insert_head
; setup the stack \o/
	ld	de, KERNEL_THREAD_STACK_SIZE
	add	iy, de
	ld	hl, .exit
	ld	(iy-6), hl
	ld	(iy-9), ix
	ld	d, e			; ld	de, NULL
	ld	(iy-12), de		; ix [NULL] > int argc, char *argv[] : in the stack
	ld	(iy-15), de		; iy [NULL] > in the future
	ld	(iy-27), de		; af [NULL] > TODO
	exx
; this can be grab with call __frameset0 \ ld hl, (ix+6) \ pop ix
	ld	(iy-3), hl
; note, we don't care for ASM thread at all, we have hl, bc, de already
	ld	(iy-18), hl
	ld	(iy-21), bc
	ld	(iy-24), de
; return iy = new thread
	ld	de, -KERNEL_THREAD_STACK_SIZE
	add	iy, de
	pop	ix
	or	a, a
	sbc	hl, hl
	pop	af
	jp	po, .bb
; try to reschedule immediately
	jp	task_schedule
.bb:
	or	a, a
	ret
	
sysdef _waitpid
.waitpid:
; Ssed to wait for state changes in a child of the calling process, and obtain information about the child whose state has changed. A state change is considered to be: the child terminated; the child was stopped by a signal; or the child was resumed by a signal. In the case of a terminated child, performing a wait allows the system to release the resources associated with the child; if a wait is not performed, then the terminated child remains in a "zombie" state
; pid_t waitpid(pid_t pid, int *status, int options);
; NOT IMPLEMENTED :  < -1 	meaning wait for any child process whose process group ID is equal to the absolute value of pid.
; -1 	meaning wait for any child process.
; NOT IMPLEMENTED : 0 	meaning wait for any child process whose process group ID is equal to that of the calling process.
; > 0 	meaning wait for the child whose process ID is equal to the value of pid. 
; ECHILD; (for wait()) The calling process does not have any unwaited-for children.
; ECHILD; (for waitpid() or waitid()) The process specified by pid (waitpid()) or idtype and id (waitid()) does not exist or is not a child of the calling process. (This can happen for one's own child if the action for SIGCHLD is set to SIG_IGN. See also the Linux Notes section about threads.)
; EINTR ; WNOHANG was not set and an unblocked signal or a SIGCHLD was caught; see signal(7).
; EINVAL ; The options argument was invalid. 
; waitpid(): on success, returns the process ID of the child whose state has changed; if WNOHANG was specified and one or more child(ren) specified by pid exist, but have not yet changed state, then 0 is returned. On error, -1 is returned. 
	ret

sysdef _core
.core:
; write whole process image to a "core" file in reallocated mode
; leaf file format
	ret

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
	add	a, a
	jr	z, .exit_make_zombie_bunny
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
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
	ld	c, (iy+KERNEL_THREAD_PPID)
	ld	a, SIGCHLD
	call	signal.kill
; interrupts should be definitely stopped here !
	di
; first disable stack protector (load the kernel_stack stack protector)
	ld	a, $A8
	out0	($3A), a
	xor	a, a
	out0	($3B), a
	ld	a, $D0
	out0	($3C), a
	ld	sp, (kernel_stack_pointer)
	ld	a, (iy+KERNEL_THREAD_PID)
	call	.free_pid
; need to free IRQ locked and mutex locked to thread
; TODO ;
; remove from active
	ld	hl, kthread_mqueue_active
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
; find next to schedule
; ie dispatch method from schedule
; unmap the memory of the thread
; this also unmap the stack
	ld	a, (iy+KERNEL_THREAD_PID)
	call	kmm.thread_unmap
; that will reset everything belonging to the thread
	ld	bc, QUEUE_SIZE
	ld	a, $FF
	ld	hl, kthread_mqueue_active
	cp	a, (hl)
	jr	nz, .exit_dispatch_thread
	add	hl, bc
	cp	a, (hl)
	jr	nz, .exit_dispatch_thread
	add	hl, bc
	cp	a, (hl)
	jr	nz, .exit_dispatch_thread
	add	hl, bc
	cp	a, (hl)
	jr	nz, .exit_dispatch_thread
	add	hl, bc
	cp	a, (hl)
	jp	z, nmi
; schedule the idle thread
	ld	de, kernel_idle
	jp	kscheduler.context_restore
.exit_dispatch_thread:
	inc	hl
	ld	de, (hl)
; go into the thread directly, without schedule (pop all stack and discard current context)
	jp	kscheduler.context_restore
	
.sleep:
; hl = time in ms, return 0 is sleept entirely, or approximate time to sleep left
; carry is set if we haven't sleep enough time
; note that the kernel will wake you always *after* this time elapsed, or if a not blocked signal reached you
	push	iy
	push	de
	push	af
	ld	iy, (kthread_current)
	di
	call	task_switch_sleep_ms
	call	task_yield
; we are back with interrupt
; this one is risky with interrupts, so disable them the time to do it
	di
	ld	hl, (iy+KERNEL_THREAD_TIMER_COUNT)
	ld	a, l
	or	a, h
	jr	nz, .sleep_intr
	ei
	sbc	hl, hl
	pop	af
	pop	de
	pop	iy
	ret
.sleep_intr:
; we were interrupted by signal
; hl is out pseudo 16 bits counter
; unwind it
	ld	e, l
	dec	h
	inc	hl
	ld	l, e
	ex	de, hl
	lea	iy, iy+KERNEL_THREAD_TIMER
	ld	hl, ktimer_queue
	call	kqueue.remove_head
	lea	iy, iy-KERNEL_THREAD_TIMER
	or	a, a
	sbc	hl, hl
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), hl
	ei
; de is time left, so get ms left
	ld	l, d
	ld	h, TIME_JIFFIES_TO_MS
	ld	d, h
; times in jiffies left to sleep
	mlt	de
	ex	de, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	xor	a, a
	ld	l, h
	ld	h, a
	ex	de, hl
	mlt	hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, de
	pop	af
	pop	de
	pop	iy
	scf
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
	scf
	ret
.reserve_exit:
; carry is reset
	srl	l
	ld	a, l
	rra
	ret

.free_pid:
; free a pid
; this should probably be in critical code section if you don't want BAD STUFF TO HAPPEN
; kinda reserved to ASM
	add	a, a
	ret	z   ; don't you dare free pid 0 !
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	xor	a, a
	ld	(hl), a
	ret

.resume:
; wake thread (adress iy)
; destroy hl, a (probably more)
; resume a waiting thread. This must be called from a thread context and NOT irq. See irq_resume
; Please enforce this restriction as lot of bad thing could happen (well, pausing an interrupt mostly)
	lea	hl, iy+0
	add	hl, de
	or	a, a
	sbc	hl, de
	ret	z
	di
; this read need to be atomic !
	ld	a, (iy+KERNEL_THREAD_STATUS)
; can't wake TASK_READY (0) and TASK_STOPPED (3) and TASK_ZOMBIE (4)
	dec	a
	cp	a, TASK_UNINTERRUPTIBLE
	jr	nc, .resume_exit
	call	task_switch_running
; skip the first di of schedule, we are already in disabled state
	jp	task_schedule + 1
.resume_exit:
	ei
	ret

; suspend, wait, resume destroy hl, iy and a	
	
.suspend:
	xor	a, a
.wait:
; wait on an IRQ (or generic suspend if a = NULL)
	di
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_IRQ), a
	or	a, a
	jr	z, .wait_generic_suspend
	ld	a, TASK_UNINTERRUPTIBLE - 1
.wait_generic_suspend:
	inc	a
	ld	(iy+KERNEL_THREAD_STATUS), a
	call	task_switch_paused
; switch away from current thread to a new active thread
	jp	task_yield

.irq_suspend:
	xor	a, a
.irq_wait:
; suspend the current thread, safe from within IRQ
; if a = 0, suspend generic, else suspend waiting the IRQ set by a
	di
	ld	hl, i
	ld	(hl), $80
	inc	hl
	ld	iy, (hl)
	ld	(iy+KERNEL_THREAD_IRQ), a
	or	a, a
	jr	z, .irq_generic_suspend
	ld	a, TASK_UNINTERRUPTIBLE - 1
.irq_generic_suspend:
	inc	a
	ld	(iy+KERNEL_THREAD_STATUS), a
	jr	task_switch_paused

.irq_resume:
; resume a thread from within an irq
; either the thread wait for an IRQ (status TASK_UNINTERRUPTIBLE + IRQ set)
; or the thread is generic paused, so wake it up
	di
	lea	hl, iy+KERNEL_THREAD_IRQ
	cp	a, (hl)
	ret	nz
	inc	hl
	ld	a, (hl)
;  status interruptible or uninterruptible
	dec	a
	cp	a, TASK_UNINTERRUPTIBLE
	ret	nc
	dec	hl
	ld	(hl), $00
	ld	hl, i
	ld	(hl), $80
	jr	task_switch_running

.yield		= kscheduler.yield
task_yield	= kscheduler.yield
task_schedule	= kscheduler.schedule

; from TASK_READY to TASK_UNINTERRUPTIBLE
; may break if not in this state before
; need to be fully atomic
task_switch_uninterruptible:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_UNINTERRUPTIBLE
task_switch_paused:
	ld	hl, kthread_mqueue_active
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jr	kqueue.insert_head

; from TASK_READY to TASK_ZOMBIE
; may break if not in this state before
; need to be fully atomic
task_switch_zombie:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_ZOMBIE
	ld	hl, kthread_mqueue_active
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jr	kqueue.insert_head

; from TASK_READY to TASK_STOPPED
; may break if not in this state before
; need to be fully atomic
task_switch_stopped:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_STOPPED
	ld	hl, kthread_mqueue_active
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
	ld	l, kthread_queue_retire and $FF
	jr	kqueue.insert_head

; sleep	'hl' ms, granularity of about 9 ms
task_switch_sleep_ms:
; do  hl * (32768/154/1000)
	ld	e, l
	ld	d, TIME_MS_TO_JIFFIES
	ld	l, d
	mlt	de
	mlt	hl
	xor	a, a
	sbc	a, e
	ld	e, d
	ld	d, 0
	adc	hl, de
; adapt to a pseudo 16 bits counter
	ld	e, l
	dec	hl
	inc	h
	ld	l, e
; add timer
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), hl
	ld	(iy+KERNEL_THREAD_TIMER_EV_SIGNOTIFY), SIGEV_THREAD
	ld	hl, ktimer.notify_default
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION), hl
	lea	iy, iy+KERNEL_THREAD_TIMER
	ld	hl, ktimer_queue
	call	kqueue.insert_head
	lea	iy, iy-KERNEL_THREAD_TIMER
	
; from TASK_READY to TASK_INTERRUPTIBLE
task_switch_interruptible:
; actual overhead : only jr
	ld	(iy+KERNEL_THREAD_STATUS), TASK_INTERRUPTIBLE
	ld	hl, kthread_mqueue_active
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
; we can consider removing the head of the queue here and update head pointer, since retire order doesn't matter ;
	call	kqueue.remove_head
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
assert kqueue.insert_head = $
