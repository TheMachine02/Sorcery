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
	ld	a, c
	and	a, MAP_TYPE_MASK
	jp	z, .mmap_anonymous
	push	hl
	push	de
	push	iy
	lea	hl, ix+0
; .fd_pointer_check
	ld	a, l
	cp	a, KERNEL_THREAD_FILE_DESCRIPTOR_MAX
	ld	a, EBADF
	jr	nc, .mmap_error
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	ix, (kthread_current)
	lea	ix, ix+KERNEL_THREAD_FILE_DESCRIPTOR
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
	jr	z, .mmap_error
; check inode is a file
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_FILE
	ld	a, EACCES
	jr	nz, .mmap_error
	push	bc
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	pop	bc
; iy is the inode, locked for write, we can start to do *stuff*
; if the flag is MAP_PRIVATE, just allocate and start copying data from the file
; if shared, we need to allocate memory and then start pushing it down the inode data and cleaning dangling pages
; in all case, allocate
	pop	ix
	lea	hl, ix+0
	pop	de
; hl (ix) is offset, de is lenght. First check if lenght+offset < inode_size
	add	hl, de
; we are kinda short on register here TODO : find a better way
	push	bc
	ld	bc, (iy+KERNEL_VFS_INODE_SIZE)
	or	a, a
	sbc	hl, bc
	pop	bc
	ld	a, EINVAL
	jp	m, .mmap_error_size
; ok we can start to allocate at adress hl, size de, keep offset and inode in ix and iy
	pop	hl
	
	
; 	call	.map_pages
	

	ret
.mmap_error:
	pop	iy
	pop	de
.mmap_error_size:
	pop	hl
	jp	user_error
.mmap_anonymous:
	ret

sysdef _munmap
; int munmap(void *addr, size_t length); 
.munmap:
; mark cache page as evictable if needed
; if page are thread page, mapping was ANONYMOUS, so free them
	ret 
