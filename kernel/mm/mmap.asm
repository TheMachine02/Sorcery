define	MAP_ANONYMOUS		0	; anonymous
define	MAP_PRIVATE		1	; private to the thread, copy of file, don't move change to underlying file
define	MAP_SHARED		2	; copy of file, asynchronously seen by other process
define	MAP_TYPE_MASK		3
define	MAP_FIXED		4

; addr need to be PAGE aligned, as well as length and offset (in file offset)

sysdef _mmap
; void *mmap(void *addr, size_t length, int flags, int fd, off_t offset);
; hl adress, de length, bc flag, ix fd, iy offset
.mmap:
; map a file onto memory at specified (or close by) adress
; if MAP_ANONYMOUS : just map memory but no file backing > map page as belonging to the thread as thread memory
; note that change to file will be asynchronously seen
; set cache page as non evictable
; WORK: for MAP_PRIVATE and MAP_ANONYMOUS
; TODO: MAP_SHARED
	ld	a, c
	and	a, MAP_TYPE_MASK
	jp	z, .__mmap_anonymous
	cp	a, MAP_PRIVATE
	jr	z, .__mmap_private
.__mmap_shared:
; 	ld	de, KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_UNEVICTABLE_MASK
; if shared, we need to allocate memory and then start pushing it down the inode data and cleaning dangling pages
; ; for inode, we need to extract the 12 bits of information and merge it with the tlb
; ; (inode are 64 aligned, 2 bits in lower, 2 bits in upper, 8 bits for high)
; 	add	iy, iy
; 	add	iy, iy
; 	ld	d, iyh
; 	push	iy
; 	dec	sp
; 	pop	bc
; 	inc	sp
; 	ld	c, a
; 	ld	a, b
; 	and	a, KERNEL_MM_PAGE_USER_MASK
; 	or	a, e
; 	ld	e, a
;	call	.map_pages
	ld	a, EINVAL
	jp	user_error
.__mmap_private:
	push	hl
	push	de
	push	iy
	lea	hl, ix+0
; .fd_pointer_check
	ld	a, l
	cp	a, KERNEL_THREAD_FILE_DESCRIPTOR_MAX
	ld	a, EBADF
	jp	nc, .__mmap_error
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	ix, (kthread_current)
	ld	ix, (ix+KERNEL_THREAD_FILE_DESCRIPTOR)
	ex	de, hl
	add	ix, de
	ex	de, hl
	ld	iy, (ix+KERNEL_VFS_FILE_INODE)
; check if the fd is valid
; if not open / invalid, all data should be zero here
	lea	hl, iy+0
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .__mmap_error
; check inode is a file
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_FILE
	ld	a, EACCES
	jr	nz, .__mmap_error
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_R_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
	jr	z, .__mmap_error
	pop	hl
; writed the offset
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
	push	hl
	push	bc
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
	pop	bc
	pop	hl
; iy is the inode, locked for write, we can start to do *stuff*
; if the flag is MAP_PRIVATE, just allocate and start copying data from the file
; in all case, allocate
	pop	de
; hl is offset, de is lenght. First check if lenght+offset < inode_size
	add	hl, de
	push	bc
	ld	bc, (iy+KERNEL_VFS_INODE_SIZE)
	or	a, a
	sbc	hl, bc
	pop	bc
	jp	m, .__mmap_error_size
; ok we can start to allocate at adress hl, size de, keep fd and inode in ix and iy
; allocate unevicatable cache page
	pop	hl
	push	de
	push	iy
	ex	de, hl
	call	mm.physical_to_ptlb
	ex	de, hl
	ld	e, a
	call	mm.physical_to_ptlb
	ld	h, a
	ld	l, e
	ld	b, h
	ld	c, l
	push	ix
	call	vmmu.map_pages
	pop	ix
	pop	iy
	pop	bc
	jr	c, .__mmap_error_size
; hl = memory mapped page, size is bc
; keep offset and inode in ix and iy
; so now, read the file from offset and copy it to the memory area
	ex	de, hl
	jp	kvfs.read_file

.__mmap_anonymous:
	ex	de, hl
	call	mm.physical_to_ptlb
	ex	de, hl
	ld	c, a
	call	mm.physical_to_ptlb
	ld	b, a
	call	vmmu.map_pages
	ret	nc
	jp	user_error

.__mmap_error:
	pop	iy
	pop	de
	pop	hl
	jp	user_error

.__mmap_error_size:
	pop	hl
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	ld	a, EINVAL
	jp	user_error

sysdef _munmap
; int munmap(void *addr, size_t length); 
.munmap:
; mark cache page as evictable if needed
; if page are thread page, mapping was ANONYMOUS, so free them
	ret 
