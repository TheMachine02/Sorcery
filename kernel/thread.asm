; this header reside in thread memory
; DONT TOUCH ANYTHING YOU DONT WANT TO BREAK IN THIS HEADER
; Atomic is UTERLY important while writing to it
; you can read pid, ppid, irq (but it will not be a *safe value, meaning it can change the next instruction
; for safety dont touch anything here except PID and PPID ;
virtual	at 0
	KERNEL_THREAD_HEADER:
	KERNEL_THREAD_PID:			rb	1
	KERNEL_THREAD_NEXT:			rb	3
	KERNEL_THREAD_PREVIOUS:			rb	3
	KERNEL_THREAD_PPID:			rb	1
	KERNEL_THREAD_IRQ:			rb	1
	KERNEL_THREAD_STATUS:			rb	1
	KERNEL_THREAD_PRIORITY:			rb	1
	KERNEL_THREAD_QUANTUM:			rb	1
; static thread data that can be manipulated freely ;
; within it's own thread ... don't manipulate other thread memory, it's not nice ;
	KERNEL_THREAD_STACK_LIMIT:
	KERNEL_THREAD_BREAK:			rb	3
	KERNEL_THREAD_STACK:			rb	3
	KERNEL_THREAD_HEAP:			rb	3
	KERNEL_THREAD_TIME:			rb	3
	KERNEL_THREAD_TIME_CHILD:		rb	3
; signal stuff ;
	KERNEL_THREAD_SIGNAL_CURRENT:		rb	1
	KERNEL_THREAD_SIGNAL_MASK:		rb	3
	KERNEL_THREAD_SIGNAL_PENDING:		rb	3
	KERNEL_THREAD_SIGNAL_VECTOR:		rb	3	; pointer to slab block
	KERNEL_THREAD_SIGNAL_SAVE:		rb	1	; 1 byte for temporary maskset save when masking signal in handler
; more attribute
	KERNEL_THREAD_NICE:			rb	1	; nice value (used for priority boosting)
	KERNEL_THREAD_ATTRIBUTE:		rb	1	; some flags
; thread waiting ;
	KERNEL_THREAD_IO:
	KERNEL_THREAD_IO_DATA:			rb	1
	KERNEL_THREAD_IO_NEXT:			rb	3
	KERNEL_THREAD_IO_PREVIOUS:		rb	3
; profiling
	KERNEL_THREAD_PROFIL_STRUCTURE:		rb	3	; pointer to profil structure
; directory
	KERNEL_THREAD_WORKING_DIRECTORY:	rb	3	; pointer to the directory inode
	KERNEL_THREAD_ROOT_DIRECTORY:		rb	3	; pointer to the root directory
	KERNEL_THREAD_FILE_DESCRIPTOR:		rb	3	; pointer to file descriptor table
; compat for now
	define	THREAD_COMPAT			1
; 	KERNEL_THREAD_ERRNO:			rb	1
; timer ;
	KERNEL_THREAD_TIMER:
	KERNEL_THREAD_TIMER_FLAGS:		rb	1
	KERNEL_THREAD_TIMER_NEXT:		rb	3
	KERNEL_THREAD_TIMER_PREVIOUS:		rb	3
	KERNEL_THREAD_TIMER_COUNT:		rb	3
	KERNEL_THREAD_TIMER_SIGEVENT:
	KERNEL_THREAD_TIMER_EV_SIGNOTIFY:	rb	1
	KERNEL_THREAD_TIMER_EV_SIGNO:		rb	1
	KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION:	rb	3
	KERNEL_THREAD_TIMER_EV_NOTIFY_THREAD:	rb	3
	KERNEL_THREAD_TIMER_EV_VALUE:
; union with thread sigval ;
	KERNEL_THREAD_SIGNAL:
	KERNEL_THREAD_EV_SIG:			rb	1
	KERNEL_THREAD_EV_SIG_POINTER:		rb	3
assert $ < KERNEL_THREAD_TLS_SIZE
end	virtual

define	KERNEL_THREAD_STACK_SIZE		8192	; all of it usable
define	KERNEL_THREAD_SIGNAL_VECTOR_SIZE	128	; 24*4 bytes
define	KERNEL_THREAD_TLS_SIZE			128	; header
define	KERNEL_THREAD_FILE_DESCRIPTOR_SIZE	256	; 8*32 bytes FD
define	KERNEL_THREAD_FILE_DESCRIPTOR_MAX	32
define	KERNEL_THREAD_MQUEUE_COUNT		5
define	KERNEL_THREAD_MQUEUE_SIZE		20

define	THREAD_PROFIL				0

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

define	ROOT_USER				$FF	; maximal permission, bit 7 is ROOT bit
define	PERMISSION_USER				$01	; minimal permission
define	SUPER_USER_BIT				7

define	WNOHANG					1
define	WUNTRACED				2
define	WCONTINUED				4

kthread:

sysdef _thread
.create:
; Create a thread
; int thread_create(void* thread_entry, void* thread_arg)
; register IY is entry, register HL is send to the stack for void* thread_arg
; NOTE: for syscall wrapper : need to grab the pid of the thread and ouptput it to a *thread_t id
; NOTE: you can't call create thread in a interrupt disabled context, use irq_create for that
	call	.irq_create
	jp	c, user_error
	jp	task_schedule

.__create_no_mem:
	ld	hl, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	call	kmem.cache_free
	ld	hl, (iy+KERNEL_THREAD_FILE_DESCRIPTOR)
	call	kmem.cache_free
	lea	hl, iy+0
	call	kmem.cache_free
	pop	iy
	jr	.__create_no_tls
.__create_no_fd:
	pop	hl
	call	kmem.cache_free
.__create_no_signal:
	pop	hl
	call	kmem.cache_free
.__create_no_tls:
	pop	af
	ld	a, ENOMEM
	jr	.__create_error
.__create_no_pid:
	ld	a, EAGAIN
.__create_error:
; restore register and cleanup
	exx
	rsti
	scf
	ret
	
.irq_create:
	tsti
; save hl, de, bc registers
	exx
	call	.reserve_pid
	jr	c, .__create_no_pid
; a is the allocated PID, save it for latter
	push	af
; allocate the TLS
	ld	hl, kmem_cache_s128
	call	kmem.cache_alloc
	jr	c, .__create_no_tls
	push	hl
	ld	hl, kmem_cache_s128
	call	kmem.cache_alloc
	jr	c, .__create_no_signal
	push	hl
	ld	hl, kmem_cache_s256
	call	kmem.cache_alloc
	jr	c, .__create_no_fd
	pop	bc
	pop	de
; hl = fd, de = tls, bc = signal
	pop	af
	push	af
	push	iy
	ld	iy, 0
	add	iy, de
	ld	(iy+KERNEL_THREAD_SIGNAL_VECTOR), bc
	ld	(iy+KERNEL_THREAD_FILE_DESCRIPTOR), hl
; now we need to allocate the cache
	ld	bc, (KERNEL_THREAD_STACK_SIZE/KERNEL_MM_PAGE_SIZE) or (KERNEL_MM_GFP_USER shl 8)
	call	mm.map_user_pages
	jr	c, .__create_no_mem
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
	ld	(iy+KERNEL_THREAD_HEAP), hl
	ld	de, KERNEL_THREAD_STACK_SIZE - 27
	add	hl, de
	ld	(iy+KERNEL_THREAD_STACK), hl
; setup the stack, all other register are cleared
	ex	de, hl
	ld	ix, 0
	add	ix, de
	exx
	ld	(ix+24), hl
	exx
	ld	hl, .exit
	ld	(ix+21), hl
	pop	hl
	ld	(ix+18), hl
; setup default parameter
	ld	de, $FFFFFF
	ld	(iy+KERNEL_THREAD_SIGNAL_MASK), de
	ld	(iy+KERNEL_THREAD_SIGNAL_CURRENT), 0
	ld	(iy+KERNEL_THREAD_QUANTUM), 1
	ld	(iy+KERNEL_THREAD_PRIORITY), SCHED_PRIO_MAX
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
; directory settings
	ld	ix, (kthread_current)
	ld	a, TASK_IDLE
	cp	a, (ix+KERNEL_THREAD_STATUS)
	jr	z, .__create_directory_root
	ld	hl, (ix+KERNEL_THREAD_WORKING_DIRECTORY)
	ld	(iy+KERNEL_THREAD_WORKING_DIRECTORY), hl
	ld	hl, (ix+KERNEL_THREAD_ROOT_DIRECTORY)
	ld	(iy+KERNEL_THREAD_ROOT_DIRECTORY), hl
	jr	.__create_copy_signal
.__create_directory_root:
	ld	hl, kvfs_root
	ld	(iy+KERNEL_THREAD_WORKING_DIRECTORY), hl
	ld	(iy+KERNEL_THREAD_ROOT_DIRECTORY), hl
; increase reference count of both directory
; TODO : iref the inode (and deref when exiting the thread)
; 	ld	c, KERNEL_VFS_INODE_REFERENCE
; 	add	hl, bc
; 	inc	(hl)
.__create_copy_signal:
; sig parameter mask ;
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_THREAD), iy
	ld	de, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	ld	hl, signal.default_handler
	ld	bc, 24*4
	ldir
	pop	af
	ld	(iy+KERNEL_THREAD_PID), a
; map the thread to be transparent to the scheduler
; iy is thread adress, a is still PID    
; map the pid
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	ld	(hl), PERMISSION_USER
	inc	hl
	ld	(hl), iy
; write parent pid    
	ld	hl, (kthread_current)
	lea	de, iy+KERNEL_THREAD_PPID
	ldi
; setup the queue
; insert the thread to the ready queue
	ld	h, ( kthread_mqueue_active and $00FF00 ) shr 8
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call   kqueue.insert_head
; set reschedule value
	ld	hl, i
	ld	(hl), $80
	exx
	or	a, a
	sbc	hl, hl
	ld	l, a
	rsti
; return hl = pid, iy = new thread handle
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
	jp	.exit

sysdef _exit
.exit:
; signal parent thread of the end of the child thread
; also send HL as exit code
	di
	ld	iy, (kthread_current)
; 	bit	THREAD_JOIGNABLE, (iy+KERNEL_THREAD_ATTRIBUTE)
; 	jr	z, .exit_clean
; ; if we have a thread * currently * watching, wake it up
; 	push	hl
; 	ld	a, (iy+KERNEL_THREAD_JOINED)
; 	add	a, a
; 	jr	z, .exit_make_zombie_bunny
; 	add	a, a
; 	ld	hl, kthread_pid_map
; 	ld	l, a
; 	ld	a, (hl)
; ; sanity check ;
; 	or	a, a
; 	jr	z, .exit_make_zombie_bunny
; 	push	iy
; 	inc	hl
; 	ld	iy, (hl)
; ; should be sleeping if joined, but anyway, extra check	
; 	ld	a, (iy+KERNEL_THREAD_STATUS)
; 	cp	a, TASK_INTERRUPTIBLE
; 	call	z, task_switch_running
; 	pop	iy
; .exit_make_zombie_bunny:
; 	call	task_switch_zombie
; 	pop	hl
; 	call	task_yield
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
	call	mm.drop_user_pages
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
