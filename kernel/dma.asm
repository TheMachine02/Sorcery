define	MAP_ANONYMOUS		1 shl 0
define	MAP_PRIVATE		1 shl 1
define	MAP_FIXED		1 shl 2

; addr need to be PAGE aligned, as well as length and offset (in file offset)

sysdef _mmap
; void *mmap(void *addr, size_t length, int flags, int fd, off_t offset);
; hl adress, de length, bc flag, ix fd, iy offset
.mmap:
; map a file onto memory at specified (or close by) adress
; if MAP_ANONYMOUS : just map memory but no file backing > map page as belonging to the thread as thread memory
; note that change to file will be asynchronously seen
; set cache page as non evictable
	ret
	
sysdef _munmap
; int munmap(void *addr, size_t length); 
.munmap:
; mark cache page as evictable if needed
; if page are thread page, mapping was ANONYMOUS, so free them
	ret
	
sysdef _dma_access
.dma_access:
; fd hl, return hl = first block pointer that can be read/write (please note that the pointer is valid for the first 1024 bytes only)
	call	.fd_pointer_check
	ret	c
; check we have permission
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_R_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
	jp	z, syserror
	bit	KERNEL_VFS_PERMISSION_W_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
	jp	z, syserror
	bit     KERNEL_VFS_CAPABILITY_DMA_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	jp	z, syserror
; about locking : using a dma acess will lock the inode for read/write
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	set	KERNEL_VFS_CAPABILITY_ACCESS_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	hl, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	a, (hl)
	or	a, a
	jr	nz, .dma_cache_hit
	inc	hl
	ld	hl, (hl)
	ret
	
.dma_cache_hit:
	ld	hl, KERNEL_MM_RAM shr 2
	ld	h, a
	add	hl, hl
	add	hl, hl
	ret
	
sysdef _dma_blk
.dma_blk:
; fd hl, block de
; assume we have dma_acess
	call	.fd_pointer_check
	ret	c
	bit	KERNEL_VFS_CAPABILITY_ACCESS_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	a, EACCES
	jp	z, syserror
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
	jr	nz, .dma_cache_hit
	inc	hl
	ld	hl, (hl)
	ret
	
sysdef _dma_release
.dma_release:
; fd is hl, free the file of sub-block DMA read
	call	.fd_pointer_check
	ret	c
	bit	KERNEL_VFS_CAPABILITY_ACCESS_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	a, EACCES
	jp	z, syserror
	res	KERNEL_VFS_CAPABILITY_ACCESS_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	or	a, a
	sbc	hl, hl
	ret
