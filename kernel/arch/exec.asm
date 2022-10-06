define	EXEC_MICROCODE_SIZE	192


sysdef _execve
execve:
; .BINARY_PATH:	hl
; .BIN_ENVP:	de
; .BIN_ARGV:	bc
; TODO : correct error path
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
	ld	bc, (KERNEL_THREAD_STACK_SIZE/KERNEL_MM_PAGE_SIZE) or (KERNEL_MM_GFP_USER shl 8)
	call	vmmu.map_pages
	push	hl
	push	iy
	ld	iy, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	iy, (iy+KERNEL_VFS_INODE_DMA_POINTER)
	call	leaf.exec_dma
; TODO : check for error here
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
; various close on exec etc
; TODO
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
