define	EXEC_MICROCODE_SIZE	192


sysdef _execve
execve:
; .BINARY_PATH:	hl
; .BIN_ENVP:	de
; .BIN_ARGV:	bc
	call	kvfs.inode_get_lock
	ret	c
; check if the inode is executable
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	l, a
	and	a, KERNEL_VFS_TYPE_MASK
	ld	a, ENOEXEC
	jp	nz, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_PERMISSION_X_BIT, l
	jp	z, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_CAPABILITY_DMA_BIT, l
	jp	z, kvfs.inode_atomic_write_error
; we have an DMA inode
; save the vmmu context of the current thread
	ld	hl, kmem_cache_s32
	call	kmem.cache_alloc
	jp	c, kvfs.inode_atomic_write_error
	push	hl
	ld	ix, (kthread_current)
	lea	de, ix+KERNEL_THREAD_VMMU_CONTEXT
	ex	de, hl
	ld	bc, 28
	ldir
; nullify the context
	lea	de, ix+KERNEL_THREAD_VMMU_CONTEXT
	ld	hl, KERNEL_MM_NULL
	ld	c, 28
	ldir
; allocate a new stack
	push	iy
	ld	iy, (kthread_current)
	ld	bc, (KERNEL_THREAD_STACK_SIZE/KERNEL_MM_PAGE_SIZE) or (KERNEL_MM_GFP_USER shl 8)
	call	vmmu.map_pages
	pop	iy
	jp	c, .__execve_invalid_stack
	push	hl
	push	iy
	ld	iy, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	iy, (iy+KERNEL_VFS_INODE_DMA_POINTER)
	call	leaf.exec_dma
	jp	c, .__execve_invalid_program
	push	hl
	ld	hl, kmem_cache_s128
	call	kmem.cache_alloc
	jp	c, .__execve_invalid_sighand
	ex	de, hl
	di
; drop the signal handler table and allocate a new one
	ld	iy, (kthread_current)
	ld	hl, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
	ld	(iy+KERNEL_THREAD_SIGNAL_VECTOR), de
; if signal refcount is zero, we can cleanup
	dec	(hl)
	call	z, kmem.cache_free
	ld	hl, signal.default_handler
	ld	bc, KERNEL_THREAD_SIGNAL_VECTOR_SIZE
	ldir
	pop	hl
; hl is the adress we need to jump to
; * cleanup *
	pop	iy
	ex	(sp), hl
; past this point, inode is not needed anymore, we can free it
	push	hl
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	pop	hl
	di
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
	ld	(iy+KERNEL_THREAD_HEAP), hl
	ld	de, KERNEL_THREAD_STACK_SIZE - 3
	add	hl, de
	ld	de, kthread.exit
	ld	(hl), de
	ld	(iy+KERNEL_THREAD_STACK), hl
	lea	hl, iy+KERNEL_THREAD_STACK_LIMIT
	ld	bc, $00033A
	otimr
; various thread reset
; various close on exec etc
; reset attached timers
;	call	ktimer.drop
; check for fd with close on exec flags and close them
; close all fd
	ld	ix, (iy+KERNEL_THREAD_FILE_DESCRIPTOR)
	ld	b, KERNEL_THREAD_FILE_DESCRIPTOR_MAX
.__execve_close_fd:
	push	bc
	pea	ix+KERNEL_VFS_FILE_DESCRIPTOR_SIZE
	ld	hl, (ix+0)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .__execve_skip_fd
	ld	a, (ix+KERNEL_VFS_FILE_FLAGS)
	and	a, KERNEL_VFS_O_CLOEXEC
	call	nz, kvfs.close
.__execve_skip_fd:
	pop	ix
	pop	bc
	djnz	.__execve_close_fd
; check if the parent thread have vforked, is so, resume it
	ld	a, (iy+KERNEL_THREAD_PPID)
	add	a, a
	add	a, a
	jr	z, .__execve_invalid_ppid
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
.__execve_invalid_ppid:
; directly return to new program
	pop	hl
	ex	(sp), hl
; hl = context to drop
	ex	de, hl
	pop	bc
; bc = return adress
	ld	hl, (iy+KERNEL_THREAD_STACK)
	ld	sp, hl
	push	bc
	ei
	push	de
	call	vmmu.drop_context_de
	pop	hl
	jp	kmem.cache_free
.__execve_invalid_sighand:
	pop	de
.__execve_invalid_program:
	pop	iy
	pop	de
	push	hl
	call	vmmu.drop_context
	pop	hl
.__execve_invalid_stack_entry:
	ex	(sp), hl
	ld	iy, (kthread_current)
	lea	de, iy+KERNEL_THREAD_VMMU_CONTEXT
	ld	bc, 28
	ldir
	ld	bc, -28
	add	hl, bc
	call	kmem.cache_free
	pop	hl
	scf
	ret
.__execve_invalid_stack:
	ld	hl, -ENOMEM
	jr	.__execve_invalid_stack_entry
	
; execute kernel in place, provide hl = file path
; as reboot, we expect filesystem to be sync and ready to reboot
sysdef	_kexec
kexec:
	call	user_perm
; freeze user space
; then filesystem sync
; then kexec
	call	kvfs.inode_get_lock
	ret	c
 ; check if the inode is executable
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	l, a
	and	a, KERNEL_VFS_TYPE_MASK
	ld	a, ENOEXEC
	jp	nz, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_PERMISSION_X_BIT, l
	jp	z, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_CAPABILITY_DMA_BIT, l
	jp	z, kvfs.inode_atomic_write_error
; we have an DMA inode, so we may check both compat and XIP
	ld	iy, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	iy, (iy+KERNEL_VFS_INODE_DMA_POINTER)
	jp	leaf.exec_dma_static
