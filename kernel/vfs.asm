; type (4 first bit)
define	KERNEL_VFS_BLOCK_DEVICE			1
define	KERNEL_VFS_FILE				2
define	KERNEL_VFS_DIRECTORY			4
define	KERNEL_VFS_SYMLINK			8
; capabilities
define	KERNEL_VFS_SEEK				16

define	KERNEL_VFS_FILE_DESCRIPTOR		0
define	KERNEL_VFS_FILE_INODE			0	; 3 bytes, inode pointer
define	KERNEL_VFS_FILE_OFFSET			3	; 3 bytes, offset within file
define	KERNEL_VFS_FILE_FLAGS			6	; 1 byte, file flags
define	KERNEL_VFS_FILE_PADDING			7	; 1 byte, padding

define	KERNEL_VFS_FILE_DESCRIPTOR_SIZE		8

kvfs:

.mkdir:
	ret
	
.rmdir:
	ret

.open:
; find the inode
	push	hl
	call	.inode_find
	pop	hl
	jr	nc, .open_continue
	call	.inode_create
	jr	c, .open_error
.open_continue:
; iy = node
; now find free file descriptor
	ld	ix, (kthread_current)
	lea	ix, ix+KERNEL_THREAD_FILE_DESCRIPTOR + 24
	ld	b, 21
	ld	de, 8
.open_descriptor:
	ld	hl, (ix+0)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .open_descriptor_found
	add	ix, de
	djnz	.open_descriptor
; no descriptor found

.open_error:
	ret

.open_descriptor_found:
	ld	(ix+KERNEL_VFS_FILE_INODE), iy
	ld	e, 0
	ld	(ix+KERNEL_VFS_FILE_OFFSET), de
	ld	(ix+KERNEL_VFS_FILE_FLAGS), e
; get our file descriptor
	lea	hl, ix - KERNEL_THREAD_FILE_DESCRIPTOR
	ld	de, (kthread_current)
	or	a, a
	sbc	hl, de
	srl	h
	rr	l
	srl	h
	rr	l
	srl	h
	rr	l
; hl is fd
	ret

.close:
; hl is fd
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	de, (kthread_current)
	add	hl, de
	ld	de, KERNEL_THREAD_FILE_DESCRIPTOR
	add	hl, de
	ld	iy, (hl)	; get inode
; null the file descriptor
	ex	de, hl
	ld	hl, KERNEL_MM_NULL
	ld	bc, KERNEL_VFS_FILE_DESCRIPTOR_SIZE
	ldir
	ld	ix, (iy+KERNEL_VFS_INODE_OP)
	lea	hl, ix+phy_sync
	call	.inode_call
; and put the inode, decrement reference
	dec	(iy+KERNEL_VFS_INODE_REFERENCE)
	ret	nz
	jp	.inode_destroy

.sync:
	ret
	
.read:
;;size_t read(int fd, void *buf, size_t count);
; hl is fd, void *buf is de, size_t count is bc
; pad count to inode_file_size
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	iy, (kthread_current)
	ex	de, hl
	add	iy, de
	ex	de, hl
	ld	hl, (iy+KERNEL_THREAD_FILE_DESCRIPTOR + KERNEL_VFS_FILE_OFFSET)
	ld	iy, (iy+KERNEL_THREAD_FILE_DESCRIPTOR)	; get inode
; hl is offset in file, iy is inode, de is buffer, bc is count
; TODO : restrict bc to maximum file size ++
; convert hl to block (16 blocks per indirect, 1024 bytes per block)
; hl / 1024 : offset in block
	push	hl
	dec	sp
	pop	hl
	inc	sp
	ld	a, l
	srl	h
	rra
	srl	h
	rra
; a = block offset, de buffer, bc count
; now, let's ldir and lock
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
	push	bc
	pop	hl
.read_copy:
	ld	bc, KERNEL_MM_PAGE_SIZE
	or	a, a
	sbc	hl, bc
	jr	c, .read_copy_end
	push	hl
	call	.inode_block_data
	inc	hl
	ld	hl, (hl)
	ld	bc, KERNEL_MM_PAGE_SIZE
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	nz, .read_not_null
	ld	hl, KERNEL_MM_NULL
.read_not_null:
	ldir
	pop	hl
	inc	a
	jr	.read_copy
.read_copy_end:
; end copy
	add	hl, bc
	push	hl
	call	.inode_block_data
	inc	hl
	ld	hl, (hl)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	nz, .read_not_null2
	ld	hl, KERNEL_MM_NULL
.read_not_null2:
	pop	bc
	ldir
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	jp	atomic_rw.unlock_read

.write:
	ret

