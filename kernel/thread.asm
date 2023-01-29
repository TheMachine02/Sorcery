; this header reside in thread memory
; DONT TOUCH ANYTHING YOU DONT WANT TO BREAK IN THIS HEADER
; Atomic is UTERLY important while writing to it
; you can read pid, ppid, irq (but it will not be a *safe* value, meaning it can change the next instruction
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
; 	KERNEL_THREAD_SIGNAL_SAVE:		rb	1	; 1 byte for temporary maskset save when masking signal in handler
; more attribute
	KERNEL_THREAD_SUID:			rb	1
	KERNEL_THREAD_RUID:			rb	1
	KERNEL_THREAD_SID:			rb	1
	KERNEL_THREAD_NICE:			rb	1	; nice value (used for priority boosting)
	KERNEL_THREAD_EXIT_FLAGS:		rb	1
	KERNEL_THREAD_EXIT_STATUS:		rb	1
	KERNEL_THREAD_EXIT_SIGNAL:		rb	1
	KERNEL_THREAD_ATTRIBUTE:		rb	1	; some flags value
; vmmu context ;
	KERNEL_THREAD_VMMU_CONTEXT:		rb	28	; bitmap to RAM memory, allowing thread to indicate which memory page they own. On anonymous page, we have reference count, since they might be shared
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
; the real itimer within thread
	KERNEL_THREAD_ITIMER:			rb	16	; timer structure
	
assert $ < KERNEL_THREAD_TLS_SIZE
end	virtual

; pid mapping structure
virtual	at 0
	KERNEL_THREAD_EUID:			rb	1
	KERNEL_THREAD_TLS:			rb	3
end	virtual

; clone structure
virtual	at 0
	CLONE_FLAGS:				rb	1
	CLONE_CHILD_PID:			rb	3	; pointer to store child tid in child memory
	CLONE_PARENT_PID:			rb	3	; pointer to store child tid in parent memory
	CLONE_EXIT_SIGNAL:			rb	1	; signal to deliver to parent
	CLONE_STACK:				rb	3	; stack adress (pointer to lowest)
	CLONE_STACK_SIZE:			rb	3	; stack size (hard to use since the stack will be always not allocated with proper pid)
	CLONE_TLS:				rb	3	; location of tls
end	virtual

define	CLONE_PARENT				1 shl 0		; make the parent of the new child be the same of the calling thread
define	CLONE_SETTLS				1 shl 1		; set tls with tls structure
define	CLONE_CHILD_SETTID			1 shl 2		; set pid within the adress provided
define	CLONE_SIGHAND				1 shl 3		; use signal handler of the parent
define	CLONE_VFORK				1 shl 4		; set vfork in parent thread & pause it
define	CLONE_VM				1 shl 5		; use same memory space (stack) for this thread, (use with VFORK only)
define	CLONE_CLEAR_SIGHAND			1 shl 6		; reset sig handler to all default (incompatible with SIGHAND)
define	CLONE_FILES				1 shl 7		; share fd table

define	CLONE_PARENT_BIT			0		; make the parent of the new child be the same of the calling thread
define	CLONE_SETTLS_BIT			1		; set tls with tls structure
define	CLONE_CHILD_SETTID_BIT			2		; set pid within the adress provided
define	CLONE_SIGHAND_BIT			3		; use signal handler of the parent
define	CLONE_VFORK_BIT				4		; set vfork in parent thread & pause it
define	CLONE_VM_BIT				5		; use same memory space (stack) for this thread, (use with VFORK only)
define	CLONE_CLEAR_SIGHAND_BIT			6		; reset sig handler to all default (incompatible with SIGHAND)
define	CLONE_FILES_BIT				7		; share the fd table

define	KERNEL_THREAD_MAP_SIZE			4
define	KERNEL_THREAD_STACK_SIZE		8192	; all of it usable
define	KERNEL_THREAD_SIGNAL_VECTOR_SIZE	96	; 24*4 bytes
define	KERNEL_THREAD_TLS_SIZE			128	; header
define	KERNEL_THREAD_FILE_DESCRIPTOR_SIZE	256	; 8*32 bytes FD
define	KERNEL_THREAD_FILE_DESCRIPTOR_MAX	32

define	KERNEL_THREAD_MQUEUE_COUNT		5
define	KERNEL_THREAD_MQUEUE_SIZE		20

; thread attribute (bit)
define	THREAD_PROFIL_BIT			0
define	THREAD_VFORK_BIT			1

; task status
define	TASK_READY				0
define	TASK_INTERRUPTIBLE			1	; can be waked up by signal
define	TASK_UNINTERRUPTIBLE			2
define	TASK_STOPPED				3	; can be waked by signal only SIGCONT, state of SIGSTOP / SIGTSTP
define	TASK_ZOMBIE				4
define	TASK_IDLE				255	; special for the scheduler

; priority
define	SCHED_PRIO_MAX				0
define	SCHED_PRIO_MIN				12
define	NICE_PRIO_MIN				19
define	NICE_PRIO_MAX				-20

; wait pid option parameter
define	WNOHANG					1 shl 0
define	WUNTRACED				1 shl 1
define	WCONTINUED				1 shl 2

; exit flags
define	EXITED					1 shl 0
define	SIGNALED				1 shl 1
define	COREDUMP				1 shl 2

kthread:

.create:
; Create a thread
; int thread_create(void* thread_entry, void* thread_arg)
; register IY is entry, register HL is send to the stack for void* thread_arg
; NOTE: for syscall wrapper : need to grab the pid of the thread and ouptput it to a *thread_t id
; NOTE: you can't call create thread in a interrupt disabled context (IRQ), use irq_create for that
	call	.do_create
	ret	c
	jp	task_schedule

.__create_no_mem:
	ld	hl, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	call	kmem.cache_free
	ld	hl, (iy+KERNEL_THREAD_FILE_DESCRIPTOR)
	call	kmem.cache_free
	lea	hl, iy+0
	call	kmem.cache_free
	pop	iy
	pop	af
	jr	.__create_no_tls
.__create_no_fd:
	pop	hl
	call	kmem.cache_free
.__create_no_signal:
	pop	hl
	call	kmem.cache_free
.__create_no_tls:
	ld	hl, -ENOMEM
	jr	.__create_error
.__create_no_pid:
	ld	hl, -EAGAIN
.__create_error:
; restore register and cleanup
	rsti
	scf
	ret

.do_create:
	tsti
; save hl, de, bc registers
	exx
	call	.reserve_pid
	jr	c, .__create_no_pid
; a is the allocated PID, save it for latter
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
; hl = fd, de = tls, bc = signal, a = pid
	push	af
	push	iy
	ld	iy, 0
	add	iy, de
	ld	(iy+KERNEL_THREAD_SIGNAL_VECTOR), bc
	ld	(iy+KERNEL_THREAD_FILE_DESCRIPTOR), hl
; now we need to allocate the cache
	ld	bc, (KERNEL_THREAD_STACK_SIZE/KERNEL_MM_PAGE_SIZE) or (KERNEL_MM_GFP_USER shl 8)
	call	vmmu.map_pages
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
; directory settings (if PID 0 is calling, set directory)
	ld	ix, (kthread_current)
	ld	a, (ix+KERNEL_THREAD_PID)
	or	a, a
	jr	z, .__create_directory_root
	ld	hl, (ix+KERNEL_THREAD_WORKING_DIRECTORY)
	ld	(iy+KERNEL_THREAD_WORKING_DIRECTORY), hl
	ld	hl, (ix+KERNEL_THREAD_ROOT_DIRECTORY)
	ld	(iy+KERNEL_THREAD_ROOT_DIRECTORY), hl
	jr	.__create_directory_reference
.__create_directory_root:
	ld	hl, kvfs_root
	ld	(iy+KERNEL_THREAD_WORKING_DIRECTORY), hl
	ld	(iy+KERNEL_THREAD_ROOT_DIRECTORY), hl
.__create_directory_reference:
; increase reference count of both directory
	ld	ix, (iy+KERNEL_THREAD_ROOT_DIRECTORY)
	inc	(ix+KERNEL_VFS_INODE_REFERENCE)
	ld	ix, (iy+KERNEL_THREAD_WORKING_DIRECTORY)
	inc	(ix+KERNEL_VFS_INODE_REFERENCE)
.__create_copy_signal:
; sig parameter mask ;
	ld	de, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	ld	hl, signal.default_handler
	ld	bc, KERNEL_THREAD_SIGNAL_VECTOR_SIZE
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
	ld	(hl), SUPER_USER
	inc	hl
	ld	(hl), iy
; write parent pid
	ld	hl, (kthread_current)
	lea	de, iy+KERNEL_THREAD_PPID
	ldi
	ld	(iy+KERNEL_THREAD_SUID), SUPER_USER
	ld	(iy+KERNEL_THREAD_RUID), SUPER_USER
	ld	(iy+KERNEL_THREAD_EXIT_SIGNAL), SIGCHLD
; setup the queue
; insert the thread to the ready queue
	ld	hl, kthread_mqueue_active
	call   kqueue.insert_head
	or	a, a
	sbc	hl, hl
	rra
	rra
	ld	l, a
	rsti
; return hl = pid, iy = new thread handle
	or	a, a
	ret

.__clone3_no_stack:
	ld	hl, (iy+KERNEL_THREAD_FILE_DESCRIPTOR)
	call	kmem.cache_free
.__clone3_no_fd:
; need to unallocate signal & tls
	ld	hl, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	dec	(hl)
	call	z, kmem.cache_free
.__clone3_no_signal:
; need to unallocate tls
	lea	hl, iy+0
	call	kmem.cache_free
	ld	hl, -ENOMEM
	ret

; NOTE : to have the clone3 outside of sysdef is wanted since we might call it from kernel space and we still need to syscall framestack in all case
_clone:=$
.clone3:
	push	ix
	push	iy
	push	de
	push	bc
	push	af
	push	hl
	ld	hl, user_return
	ex	(sp), hl
.__clone3_do:
; structure is hl, de is size
	di
	push	hl
	pop	ix
.__clone3_sanitize_input:
	or	a, a
	add	hl, de
	sbc	hl, de
	ld	hl, -EINVAL
	scf
	ret	z
; CLONE_CLEAR_SIGHAND and CLONE_SIGHAND are incompatible
; CLONE_VM need CLONE_VFORK also set
	ld	a, (ix+CLONE_FLAGS)
	bit	CLONE_VM_BIT, a
	jr	z, .__clone3_no_vm
	bit	CLONE_VFORK_BIT, a
	ret	z
.__clone3_no_vm:
	bit	CLONE_SIGHAND_BIT, a
	jr	z, .__clone3_no_sig
	bit	CLONE_CLEAR_SIGHAND_BIT, a
	ret	nz
.__clone3_no_sig:
	call	.reserve_pid
	ld	hl, -EAGAIN
	ret	c
; ix is the clone structure
	bit	CLONE_SETTLS_BIT, (ix+CLONE_FLAGS)
	ld	de, (ix+CLONE_TLS)
	jr	nz, .__clone3_no_tls
	ld	hl, kmem_cache_s128
	call	kmem.cache_alloc
; copy the tls, iy is valid past this point
	ex	de, hl
	ld	hl, -ENOMEM
	ret	c
.__clone3_no_tls:
	ld	iy, 0
	add	iy, de
	ld	hl, (kthread_current)
	ld	bc, KERNEL_THREAD_TLS_SIZE
	ldir
	bit	CLONE_SIGHAND_BIT, (ix+CLONE_FLAGS)
	jr	nz, .__clone3_duplicate_sighand
	ld	hl, kmem_cache_s128
	call	kmem.cache_alloc
	jr	c, .__clone3_no_signal
; copy signal and set it anew in the forked thread
	ex	de, hl
	ld	hl, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	ld	(iy+KERNEL_THREAD_SIGNAL_VECTOR), de
	ex	de, hl
	ld	(hl), 0
	ex	de, hl
	ld	bc, KERNEL_THREAD_SIGNAL_VECTOR_SIZE-1
	inc	de
	inc	hl
	ldir
.__clone3_duplicate_sighand:
	ld	hl, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	inc	(hl)
	ld	hl, kmem_cache_s256
	call	kmem.cache_alloc
	jp	c, .__clone3_no_fd
	ex	de, hl
	ld	hl, (iy+KERNEL_THREAD_FILE_DESCRIPTOR)
	ld	(iy+KERNEL_THREAD_FILE_DESCRIPTOR), de
	ld	bc, KERNEL_THREAD_FILE_DESCRIPTOR_SIZE
	ldir
; iy is thread adress (tls), a is still PID
	ld	(iy+KERNEL_THREAD_PID), a
; map the thread to be transparent to the scheduler
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	ld	(hl), SUPER_USER
	inc	hl
	ld	(hl), iy
; setup default parameter
	ld	de, $000000
	ld	(iy+KERNEL_THREAD_SIGNAL_PENDING), de
	ld	(iy+KERNEL_THREAD_SIGNAL_CURRENT), 0
	ld	(iy+KERNEL_THREAD_QUANTUM), 1
	ld	(iy+KERNEL_THREAD_PRIORITY), SCHED_PRIO_MAX
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
; increase reference count of both directory
; if PID 0 is the one cloning, reset
	ld	hl, (kthread_current)
	ld	a, (hl)
	or	a, a
	jr	z, .__clone3_create_directory_root
	push	ix
	ld	ix, (kthread_current)
	ld	hl, (ix+KERNEL_THREAD_WORKING_DIRECTORY)
	ld	(iy+KERNEL_THREAD_WORKING_DIRECTORY), hl
	ld	hl, (ix+KERNEL_THREAD_ROOT_DIRECTORY)
	ld	(iy+KERNEL_THREAD_ROOT_DIRECTORY), hl
	pop	ix
	jr	.__clone3_directory_reference
.__clone3_create_directory_root:
	ld	hl, kvfs_root
	ld	(iy+KERNEL_THREAD_WORKING_DIRECTORY), hl
	ld	(iy+KERNEL_THREAD_ROOT_DIRECTORY), hl
.__clone3_directory_reference:
; increase reference count of both directory
	push	ix
	ld	ix, (iy+KERNEL_THREAD_ROOT_DIRECTORY)
	inc	(ix+KERNEL_VFS_INODE_REFERENCE)
	ld	ix, (iy+KERNEL_THREAD_WORKING_DIRECTORY)
	inc	(ix+KERNEL_VFS_INODE_REFERENCE)
	pop	ix
; uid
	ld	(iy+KERNEL_THREAD_SUID), SUPER_USER
	ld	(iy+KERNEL_THREAD_RUID), SUPER_USER
; sig parameter mask ;
; set exit signal
	ld	c, (ix+CLONE_EXIT_SIGNAL)
	ld	(iy+KERNEL_THREAD_EXIT_SIGNAL), c
; duplicate vmmu context (NOTE : also reference original stack, but that's okay, maybe FIXME)
	call	vmmu.dup_context
	bit	CLONE_CLEAR_SIGHAND_BIT, (ix+CLONE_FLAGS)
	jr	z, .__clone3_clear_sighand
	ld	de, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	ld	hl, signal.default_handler
	ld	bc, KERNEL_THREAD_SIGNAL_VECTOR_SIZE
	ldir
.__clone3_clear_sighand:
	bit	CLONE_PARENT_BIT, (ix+CLONE_FLAGS)
	jr	nz, .__clone3_duplicate_ppid
	ld	hl, (kthread_current)
	ld	a, (hl)
	ld	(iy+KERNEL_THREAD_PPID), a
.__clone3_duplicate_ppid:
	bit	CLONE_VFORK_BIT, (ix+CLONE_FLAGS)
	jr	z, .__clone3_vfork_thread
	push	iy
	push	ix
	ld	iy, (kthread_current)
	set	THREAD_VFORK_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	call	task_switch_uninterruptible
	pop	ix
	pop	iy
.__clone3_vfork_thread:
; clone VM use the memory space of calling thread
; that mean we use the stack space of the calling thread
	bit	CLONE_VM_BIT, (ix+CLONE_FLAGS)
	ld	a, (iy+KERNEL_THREAD_PID)
	jr	nz, .__clone3_virtual_framestack
	ld	hl, (ix+CLONE_STACK)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .__clone3_allocate_stack
	ex	de, hl
	ld	hl, (ix+CLONE_STACK_SIZE)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .__clone3_allocate_stack
; we have a stack, start de size hl
	ex	de, hl
	call	vmmu.add_context
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
	ld	(iy+KERNEL_THREAD_HEAP), hl
	add	hl, de
	ld	(iy+KERNEL_THREAD_STACK), hl
	jr	.__clone3_virtual_framestack
.__clone3_allocate_stack:
; now, default situation is to create a new stack
	ld	bc, (KERNEL_THREAD_STACK_SIZE/KERNEL_MM_PAGE_SIZE) or (KERNEL_MM_GFP_USER shl 8)
	call	vmmu.map_pages
	jp	c, .__clone3_no_stack
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
	ld	(iy+KERNEL_THREAD_HEAP), hl
	ld	de, KERNEL_THREAD_STACK_SIZE
	add	hl, de
	ld	(iy+KERNEL_THREAD_STACK), hl
.__clone3_virtual_framestack:
; setup stack
	ld	a, (iy+KERNEL_THREAD_PID)
	or	a, a
	sbc	hl, hl
	ld	l, a
	push	hl
	ld	hl, .__clone3_return
	push	hl
; then push a kernel interrupt stack since we will hard switch to child thread
	push	ix
	push	iy
	push	de
	push	bc
	push	af
	push	hl
	or	a, a
	sbc	hl, hl
	add	hl, sp
	ex	de, hl
	or	a, a
	sbc	hl, hl
	add	hl, de
	bit	CLONE_VM_BIT, (ix+CLONE_FLAGS)
	ld	ix, (kthread_current)
	ld	(ix+KERNEL_THREAD_STACK), hl
; so the return stack is all good
	jr	nz, .__clone3_virtual_sp
; now, setup stack of the new thread
	ld	hl, (iy+KERNEL_THREAD_STACK)
	ld	sp, hl
.__clone3_virtual_sp:
; duplicate the kernel frame (from sp+24 for 21 bytes, to sp-24)
	ld	bc, -24
	add	hl, bc
	ld	sp, hl
	ex	de, hl
	ld	bc, 24
	add	hl, bc
	ld	c, 21
	ldir
	ex	de, hl
	ld	de, _exit
	ld	(hl), de
; setup the queue
; insert the thread to the ready queue
	ld	hl, kthread_mqueue_active
	call   kqueue.insert_head
; NOTE : hard switch to vforked thread
; actually valid since a reschedule would change pretty much nothing appart from running the new thread (stack space & userspace are already set)
	ld	(kthread_current), iy
; return 0 since we return to the child
	or	a, a
	sbc	hl, hl
	ret
.__clone3_return:
	pop	hl
	ret

.vfork_structure:
	db	CLONE_VM or CLONE_VFORK
	dl	$0
	dl	$0
	db	SIGCHLD
	dl	$0

_vfork:=$
.vfork:
	push	ix
	push	iy
	push	de
	push	bc
	push	af
	ld	hl, user_return
	push	hl
	ld	hl, .vfork_structure
	jp	.__clone3_do

sysdef _waitpid
; NOTE : technically, can also be used as wait4 but with last argument ignored 
.waitpid:
; pid_t waitpid(pid_t pid, int *status, int options);
; NOT IMPLEMENTED :  < -1 	meaning wait for any child process whose process group ID is equal to the absolute value of pid.
; -1 	meaning wait for any child process.
; NOT IMPLEMENTED : 0 	meaning wait for any child process whose process group ID is equal to that of the calling process.
; > 0 	meaning wait for the child whose process ID is equal to the value of pid. 
; if status is not zero, then status is filled with information
; options can be WNOHANG (option is bc)
	bit	7, h
	jr	z, .__waitpid_watch_schild
.__waitpid_watch_child:
; wait for any child to come up with a excuse
	di
	call	.check_child
	jr	c, .__waitpid_error
; we have at least one child zombie or alive
; check the zombie queue for terminated thread
	ld	hl, kthread_queue_zombie
	ld	a, (hl)
	or	a, a
	jp	p, .__waitpid_check_zombie
	ld	a, c
	and	a, WNOHANG
	jr	nz, .__waitpid_hang
.__waitpid_watch_child_loop:
	di
	ld	hl, kthread_queue_zombie
	ld	a, (hl)
	or	a, a
	jp	p, .__waitpid_check_zombie
	call	.suspend
	jr	.__waitpid_watch_child_loop
.__waitpid_error:
	scf
	ld	hl, -ECHILD
	ret
.__waitpid_hang:
; we return 0 since the PID exist and we are the parent of it
	or	a, a
	sbc	hl, hl
	ret
.__waitpid_watch_schild:
; watch a specific child given by hl
	ld	a, l
	ld	hl, kthread_pid_map
	add	a, a
	add	a, a
	ld	l, a
	inc	hl
	ld	iy, (hl)
	lea	hl, iy+0
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .__waitpid_error
	ld	hl, (kthread_current)
	ld	a, (hl)
	cp	a, (iy+KERNEL_THREAD_PPID)
; if not zero, we are not the parent of the thread
	jr	nz, .__waitpid_error
; we are the parent
; enter atomic state for next step (I don't want status to change between read)
	di
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_ZOMBIE
	jr	z, .__waitpid_reap_zombie
	ld	a, c
	and	a, WNOHANG
	jr	nz, .__waitpid_hang
.__waitpid_watch_schild_loop:
; wait for child signal and check if this is the one we were waiting for
	di
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_ZOMBIE
	jr	z, .__waitpid_reap_zombie
	push	iy
	call	.suspend
	pop	iy
	jr	.__waitpid_watch_schild_loop
.__waitpid_check_zombie:
; we should be atomic when entering here
; better be safe
	di
; parse the list for zombie owned by ourselve
	ld	hl, (kthread_current)
	ld	a, (hl)
	ld	hl, kthread_queue_zombie
	ld	b, (hl)
	inc	hl
	ld	iy, (hl)
	inc	b
.__waitpid_check_zombie_ppid:
	cp	a, (iy+KERNEL_THREAD_PPID)
	jr	z, .__waitpid_reap_zombie
	ld	iy, (iy+KERNEL_THREAD_NEXT)
	djnz	.__waitpid_check_zombie_ppid
; we should never reach here
	jr	.__waitpid_error
; iy is a thread owned by us that need to be reaped !
.__waitpid_reap_zombie:
; the thread (iy) we were waiting for is a zombie
; fill de with status
; and proprely free the thread
; check status buffer
	or	a, a
	sbc	hl, hl
	adc	hl, de
	jr	z, .__waitpid_reap_null
	lea	hl, iy+KERNEL_THREAD_EXIT_FLAGS
	ldi
	ldi
.__waitpid_reap_null:
; increment child time
	ld	hl, (iy+KERNEL_THREAD_TIME)
	ld	ix, (kthread_current)
	ld	de, (ix+KERNEL_THREAD_TIME_CHILD)
	add	hl, de
	ld	(ix+KERNEL_THREAD_TIME_CHILD), hl
; remove thread from zombie queue (node iy, queue zombie)
	ld	hl, kthread_queue_zombie
	call	kqueue.remove
; we need to : free the PID and kmem_cache free the tls
	ld	a, (iy+KERNEL_THREAD_PID)
	push	af
	call	.free_pid
	ei
	lea	hl, iy+KERNEL_THREAD_HEADER
	call	kmem.cache_free
; all good
	pop	af
	or	a, a
	sbc	hl, hl
	ld	l, a
	ret

; NOTE : we don't need syscall wrapper around here since we will never come back from kernelspace
_exit=$
.exit:
	ld	iy, (kthread_current)
; if PID 1 exit,make the system reset
	ld	a, (iy+KERNEL_THREAD_PID)
	dec	a
	jp	z, nmi
	ld	(iy+KERNEL_THREAD_EXIT_FLAGS), EXITED
	ld	(iy+KERNEL_THREAD_EXIT_STATUS), l
.do_exit:
; close all fd
	ld	ix, (iy+KERNEL_THREAD_FILE_DESCRIPTOR)
	ld	b, KERNEL_THREAD_FILE_DESCRIPTOR_MAX
.__exit_close_fd:
	push	bc
	pea	ix+KERNEL_VFS_FILE_DESCRIPTOR_SIZE
	ld	hl, (ix+0)
	add	hl, de
	or	a, a
	sbc	hl, de
	call	nz, kvfs.close
	pop	ix
	pop	bc
	djnz	.__exit_close_fd
; deref both root and cwd inode
	ld	iy, (kthread_current)
	push	iy
	ld	iy, (iy+KERNEL_THREAD_WORKING_DIRECTORY)
	call	kvfs.inode_deref
	pop	iy
	push	iy
	ld	iy, (iy+KERNEL_THREAD_ROOT_DIRECTORY)
	call	kvfs.inode_deref
	pop	iy
; now, zombifie and kill everything
	di
; first, switch to zombie
	call	task_switch_zombie
; send signal
	ld	l, (iy+KERNEL_THREAD_PPID)
	ld	e, (iy+KERNEL_THREAD_EXIT_SIGNAL)
	call	signal.kill
	push	iy
; now, make PID 1 adopt all the children
.__exit_adopt:
	call	.check_child
	jr	c, .__exit_stack
	ld	(iy+KERNEL_THREAD_PPID), 1
	jr	.__exit_adopt
.__exit_stack:
	pop	iy
; now disable stack protector (load the kernel_stack stack protector)
; and also drop the stack of the thread
	ld	sp, (kernel_stack_pointer)
	or	a, a
	sbc	hl, hl
	add	hl, sp
	ld	(iy+KERNEL_THREAD_STACK), hl
	ld	hl, kernel_stack_limit
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
	lea	hl, iy+KERNEL_THREAD_STACK_LIMIT
	ld	bc, $00033A
	otimr
; that will reset the stack belonging to the thread
	ld	a, (iy+KERNEL_THREAD_PID)
	call	vmmu.drop_context
; now cleanup slab space, just keep 128 bytes TLS
	ld	hl, (iy+KERNEL_THREAD_FILE_DESCRIPTOR)
	call	kmem.cache_free
	ld	hl, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
; if signal refcount is zero, we can cleanup
	dec	(hl)
	call	z, kmem.cache_free
; is the SIGCHLD signal is ignored from parent thread ?
; if so, we need to reap exiting thread now and blow it
	ld	a, (iy+KERNEL_THREAD_PPID)
	add	a, a
	add	a, a
	jr	z, .__exit_context_switch
	ld	hl, kthread_pid_map
	ld	l, a
	inc	hl
	ld	ix, (hl)
; check if parent thread have forked
; if so, we are within a valid kernel frame, and we can switch off the child thread without issue
; scheduler will get us to the correct location in the parent
	push	iy
	lea	iy, ix+0
	bit	THREAD_VFORK_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	call	nz, task_switch_running
	res	THREAD_VFORK_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	pop	iy
	ld	hl, (ix+KERNEL_THREAD_SIGNAL_VECTOR)
	ld	a, SIGCHLD shl 2
	add	a, l
	ld	l, a
	ld	a, (hl)
	inc	a
	jr	nz, .__exit_context_switch
; proprely destroy the thread since sigchld is ignored
	ld	hl, (iy+KERNEL_THREAD_TIME)
	ld	de, (ix+KERNEL_THREAD_TIME_CHILD)
	add	hl, de
	ld	(ix+KERNEL_THREAD_TIME_CHILD), hl
; remove thread from zombie queue (node iy, queue zombie)
	ld	hl, kthread_queue_zombie
	call	kqueue.remove
; we need to : free the PID and kmem_cache free the tls
	ld	a, (iy+KERNEL_THREAD_PID)
	call	.free_pid
	lea	hl, iy+KERNEL_THREAD_HEADER
	call	kmem.cache_free
	ld	iy, kernel_idle
	ld	(kthread_current), iy
.__exit_context_switch:
; NOTE : we will correctly update TIME value and proprely switch off
; we need to cleanup the idle stack just before calling though (as if we switch from idle, since the stack will be used from idle)
; NOTE : in case of ignored signal, time will be updated for the idle thread and all info are lost
; NOTE : we need to set kthtread_current if we killed TLS since for scheduler we are idle thread. It is not needed in case of valid TLS since we want to switch away (using idle stack though)
	pop	hl
	pop	af
	pop	bc
	pop	de
; we still have both ix and iy pushed
	exx
	ex	af, af'
	jp	kscheduler.do_schedule

sysdef	_usleep
.usleep:
; hl = time in ms, return 0 is sleept entirely, or approximate time to sleep left
; carry is set if we haven't sleep enough time
; note that the kernel will wake you always *after* this time elapsed, or if a not blocked signal reached you
	ld	iy, (kthread_current)
	di
	call	task_switch_sleep_ms
	call	task_yield
; we are back with interrupt
; this one is risky with interrupts, so disable them the time to do it
	di
	ld	hl, (iy+KERNEL_THREAD_ITIMER+TIMER_COUNT)
	ld	a, l
	or	a, h
	ret	z
.__usleep_eintr:
; we were interrupted by signal
; hl is out pseudo 16 bits counter
; unwind it
	ld	e, l
	dec	h
	inc	hl
	ld	l, e
	ex	de, hl
	lea	iy, iy+KERNEL_THREAD_ITIMER
	ld	hl, ktimer_queue
	call	kqueue.remove_head
	or	a, a
	sbc	hl, hl
	ld	(iy+TIMER_COUNT), l
	ld	(iy+TIMER_COUNT+1), h
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
	scf
	ret

sysdef	_pause
.pause:
; generic suspend, will be waked by a signal
	call	.suspend
	ld	hl, -EINTR
	ret

; DANGEROUS AREA, helper function ;	

.check_child:
; check all pid map table for children
; we need to be ATOMIC here
; destroy hl
; return iy = children found if carry is nc, else invalid value and no children found
	push	de
	push	bc
	ld	hl, (kthread_current)
	ld	a, (hl)
	ld	hl, kthread_pid_map + 5
	ld	de, 4
	ld	b, 63
.check_child_parse_map:
	ld	iy, (hl)
	cp	a, (iy+KERNEL_THREAD_PPID)
	jr	z, .check_child_found
	add	hl, de
	djnz	.check_child_parse_map
	pop	bc
	pop	de
	ld	iy, -1
	scf
	ret
.check_child_found:
	pop	bc
	pop	de
	or	a, a
	ret

.reserve_pid:
; find a free pid
; this should be called in an atomic / critical code section to be sure it will still be free when used
; kinda reserved to ASM
	ld	hl, kthread_pid_map + 4
	ld	de, 4
	ld	b, 63
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
	inc	hl
	ld	(hl), a
	inc	hl
	ld	(hl), a
	inc	hl
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

.irq_create:
; can be called in a interrupt disabled state
; span an irq thread which are all own by PID 1
	di
	call	.do_create
	ret	c
	ld	(iy+KERNEL_THREAD_PPID), 1
; set reschedule value
	ld	hl, KERNEL_INTERRUPT_IPT
	ld	(hl), $80
	ret

.irq_suspend:
	xor	a, a
.irq_wait:
; suspend the current thread, safe from within IRQ
; if a = 0, suspend generic, else suspend waiting the IRQ set by a
	di
	ld	hl, KERNEL_INTERRUPT_IPT
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
	lea	hl, iy+0
	add	hl, de
	or	a, a
	sbc	hl, de
	ret	z
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
	ld	hl, KERNEL_INTERRUPT_IPT
	ld	(hl), $80
	jp	task_switch_running

.yield		= kscheduler.yield
task_yield	= kscheduler.yield
task_schedule	= kscheduler.schedule

; switching ACTIVE to other state will almost always will be followed by a proprer task_yield if needed
; however, switching to ACTIVE need to set the reschedule bit in order to proprely take account of the new thread emerging

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
	jp	kqueue.insert_head

; from TASK_READY to TASK_ZOMBIE
; may break if not in this state before
; need to be fully atomic
task_switch_zombie:
	ld	(iy+KERNEL_THREAD_STATUS), TASK_ZOMBIE
	ld	hl, kthread_mqueue_active
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
	call	kqueue.remove
	ld	l, kthread_queue_zombie and $FF
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
	ld	a, (iy+KERNEL_THREAD_PID)
	lea	iy, iy+KERNEL_THREAD_ITIMER
; write the itimer value
	ld	(iy+TIMER_COUNT), l
	ld	(iy+TIMER_COUNT+1), h
	or	a, a
	sbc	hl, hl
	ld	(iy+TIMER_INTERVAL), l
	ld	(iy+TIMER_INTERVAL+1), h
	ld	hl, ktimer.itimer_sleep
	ld	(iy+TIMER_SIGEV), hl
	ld	(iy+TIMER_INTERNAL_THREAD), a
	ld	hl, ktimer_queue
	call	kqueue.insert_head
	lea	iy, iy-KERNEL_THREAD_ITIMER
	
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
	ld	hl, KERNEL_INTERRUPT_IPT
	ld	(hl), $80
	ld	(iy+KERNEL_THREAD_STATUS), TASK_READY
	ld	hl, kthread_queue_retire
; we can consider removing the head of the queue here and update head pointer, since retire order doesn't matter ;
	call	kqueue.remove_head
	ld	l, (iy+KERNEL_THREAD_PRIORITY)
assert kqueue.insert_head = $
