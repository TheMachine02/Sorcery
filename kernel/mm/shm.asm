sysdef _shmctl
.shmctl:
; fd hl, return hl = first block pointer that can be read/write (please note that the pointer is valid for the first 1024 bytes only)
	call	kvfs.fd_pointer_check
	ret	c
; check we have permission
	ld	a, (ix+KERNEL_VFS_FILE_FLAGS)
	cpl
	and	a, 3
	ld	a, EACCES
	jp	nz, user_error
	lea	hl, iy+KERNEL_VFS_INODE_FLAGS
	bit     KERNEL_VFS_CAPABILITY_DMA_BIT, (hl)
	jp	z, user_error
; about locking : using a dma acess will lock the inode for read/write
	inc	hl	; =iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	set	KERNEL_VFS_CAPABILITY_ACCESS_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	hl, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	a, (hl)
	or	a, a
	jr	nz, .__shm_cache_hit
	inc	hl
	ld	hl, (hl)
	ret
.__shm_cache_hit:
	ld	hl, KERNEL_MM_PHY_RAM shr 2
	ld	h, a
	add	hl, hl
	add	hl, hl
	ret
	
sysdef _shmget
.shmget:
; fd hl, block de
; assume we have dma_acess
	call	kvfs.fd_pointer_check
	ret	c
	bit	KERNEL_VFS_CAPABILITY_ACCESS_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	a, EACCES
	jp	z, user_error
	ld	a, e
	ld	b, a
	rra
	rra
	rra
	and	a, 00011110b
	ld	c, a
	rra
	add	a, c
	lea	hl, iy+KERNEL_VFS_INODE_DATA
	add	a, l
	ld	l, a
	ld	a, b
	and	a, 00001111b
; hl adress should be aligned to 64 bytes
	add	a, a
	add	a, a
	ld	hl, (hl)
	add	a, l
	ld	l, a
	ld	a, (hl)
	or	a, a
	jr	nz, .__shm_cache_hit
	inc	hl
	ld	hl, (hl)
	ret
	
sysdef _shmfree
.shmfree:
; fd is hl, free the file of sub-block DMA read
	call	kvfs.fd_pointer_check
	ret	c
	lea	hl, iy+KERNEL_VFS_INODE_FLAGS
	bit	KERNEL_VFS_CAPABILITY_ACCESS_BIT, (hl)
	ld	a, EACCES
	jp	z, user_error
	res	KERNEL_VFS_CAPABILITY_ACCESS_BIT, (hl)
	inc	hl	; =iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	or	a, a
	sbc	hl, hl
	ret
