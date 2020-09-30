; inode flags = (permission or type)
; permission, read/write/execute - map to posix "other" permission
define	KERNEL_VFS_PERMISSION_R			1
define	KERNEL_VFS_PERMISSION_W			2
define	KERNEL_VFS_PERMISSION_X			4
define	KERNEL_VFS_PERMISSION_RW		3
define	KERNEL_VFS_PERMISSION_RWX		7
define	KERNEL_VFS_PERMISSION_RX		5
define	KERNEL_VFS_PERMISSION_WX		6
; please note that file is not a set bit by if inode_flag&TYPE_FILE==0
define	KERNEL_VFS_TYPE_FILE			248
define	KERNEL_VFS_TYPE_DIRECTORY		8
define	KERNEL_VFS_TYPE_CHARACTER_DEVICE	16
define	KERNEL_VFS_TYPE_BLOCK_DEVICE		32
define	KERNEL_VFS_TYPE_FIFO			64
define	KERNEL_VFS_TYPE_SYMLINK			128

; structure file
define	KERNEL_VFS_FILE_DESCRIPTOR		0
define	KERNEL_VFS_FILE_DESCRIPTOR_SIZE		8
define	KERNEL_VFS_FILE_INODE			0	; 3 bytes, inode pointer
define	KERNEL_VFS_FILE_OFFSET			3	; 3 bytes, offset within file
define	KERNEL_VFS_FILE_FLAGS			6	; 2 byte, file flags, mode

; file flags that control *file*
; we can & those with permission to check mode
define	KERNEL_VFS_O_R				1
define	KERNEL_VFS_O_W				2
define	KERNEL_VFS_O_RW				4
define	KERNEL_VFS_O_TRUNC			8	; trunc file to 0 at open
define	KERNEL_VFS_O_APPEND			16	; append to end of file all write
define	KERNEL_VFS_O_CLOEXEC			32	; close on execve
define	KERNEL_VFS_O_SYNC			64	; always sync write
define	KERNEL_VFS_O_NDELAY			128	; use non-bloquant atomic_rw, error with EWOULDBLOCK

; if specified creat and tmpfile, use mode (permission of inode flags)
; seconde byte, those *doesnt* need to be stored in the file descriptor or 
define	KERNEL_VFS_O_EXCL			1	; use with O_CREAT, fail if file already exist 
define	KERNEL_VFS_O_CREAT			2	; creat the file if don't exist
define	KERNEL_VFS_O_NOFOLLOW			4	; do not follow symbolic reference *ignored*

kvfs:

.set_errno:
	push	iy
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), l
	pop	iy
	scf
	sbc	hl, hl
	ret

.open_error_excl:
	pop	af
	pop	iy
	ld	l, EEXIST
	jr	.set_errno
.open_error_noent:
	pop	af
	pop	iy
	ld	l, ENOENT
	jr	.set_errno
.open_error_acess:
	pop	ix
	pop	de
	pop	af
	pop	iy
	ld	l, EACCES
	jr	.set_errno
	
sysdef _open
.open:
; open(const char* path, int flags, mode_t mode)
; hl is path, bc is flags, a is mode
	push	iy
	push	af
	push	hl
	call	.inode_find
	pop	hl
; check if both excl and creat are set
	ld	a, b
	and	a, KERNEL_VFS_O_CREAT or KERNEL_VFS_O_EXCL
	sub	a, KERNEL_VFS_O_CREAT or KERNEL_VFS_O_EXCL
	jr	z, .open_error_excl
	jr	nc, .open_continue
.open_create:
; check that flag O_CREAT set
	bit	1, b
	jr	z, .open_error_noent
; a is our mode, and hl is path
; TODO : inode create should NOT create directory path
	call	.inode_create
; if inode create c, the eror should already have been set, so just return
	jr	nc, .open_continue
	pop	af
	pop	iy
	ret
.open_continue:
; iy = node
	push	de
	push	ix
	push	bc
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
	pop	bc
	pop	ix
	pop	de
	pop	af
	pop	iy
	ld	l, EMFILE
	jr	.set_errno
.open_descriptor_found:
	pop	bc
; check file permission
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_PERMISSION_RWX
	and	a, c
	xor	a, c
	jr	nz, .open_error_acess
	ld	(ix+KERNEL_VFS_FILE_INODE), iy
	ld	e, 0
	ld	(ix+KERNEL_VFS_FILE_OFFSET), de
; write important file flags
	ld	(ix+KERNEL_VFS_FILE_FLAGS), c
	bit	3, c	; O_TRUNC
	jr	z, .extract_fd
; if KERNEL_VFS_O_TRUNC is set in c, and the file is a normal file (not a fifo or char or block) reset the file to size 0 (drop all data)
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_FILE
	jr	nz, .extract_fd
; it is a file
; drop all data now
; parse block data and free everything
	call	.inode_drop_data
.extract_fd:
; get our file descriptor
	lea	hl, ix - KERNEL_THREAD_FILE_DESCRIPTOR
	ld	de, (kthread_current)
; carry is reset by last xor
	sbc	hl, de
	srl	h
	rr	l
	srl	h
	rr	l
	srl	h
	rr	l
	pop	ix
	pop	de
	pop	af
	pop	iy
	ret

sysdef _close
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

sysdef _sync
.sync:
	ret
	
	
.read_error_badfd:
	ld	l, EBADF
	jp	.set_errno
.read_error_edir:
	ld	l, EISDIR
	jp	.set_errno
.read_phy_device:
	push	iy
	ld	iy, (iy+KERNEL_VFS_INODE_OP)
	lea	iy, iy+phy_read
	call	.jpiy
	pop	iy
	ret
.jpiy:
	jp	(iy)

.read_fifo:
; the inode is special in case of a fifo
; the 48 bytes data block hold all the fifo data
; (if end are opened, in write / read, the block data for fifo, and the internal fifo data)
; TODO : implement fifo read
	ret
	
sysdef _read
.read:
;;size_t read(int fd, void *buf, size_t count);
; hl is fd, void *buf is de, size_t count is bc
; pad count to inode_file_size
; return size read
; TODO : maybe hide the FD data to the thread
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	ix, (kthread_current)
	ex	de, hl
	add	ix, de
	ex	de, hl
	ld	hl, (ix+KERNEL_THREAD_FILE_DESCRIPTOR + KERNEL_VFS_FILE_OFFSET)
; check if the fd is valid
; if not open / invalid, all data should be zero here
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .read_error_badfd
; check we have read permission
; KERNEL_VFS_O_R (1)
	bit	0, (ix+KERNEL_THREAD_FILE_DESCRIPTOR + KERNEL_VFS_FILE_FLAGS)
	jr	z, .read_error_badfd
	ld	iy, (ix+KERNEL_THREAD_FILE_DESCRIPTOR+KERNEL_VFS_FILE_INODE)	; get inode
; hl is offset in file, iy is inode, de is buffer, bc is count
; check inode flag right now
; if block device or character device, directly pass 
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
; well, we have a directory opened right here
	tst	a, KERNEL_VFS_TYPE_DIRECTORY
	jr	nz, .read_error_edir
	tst	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE or KERNEL_VFS_TYPE_BLOCK_DEVICE
; passthrough char / block device / fifo driver directly
	jr	nz, .read_phy_device
	and	a, KERNEL_VFS_TYPE_FIFO
	jr	nz, .read_fifo
; check hl+bc < inode size
; push bc if <, else push the bc clamped to inode size
	push	hl
	push	de
	push	bc
; compute inode size - offset - size
	ex	de, hl
	ld	hl, (iy+KERNEL_VFS_INODE_SIZE)
	or	a, a
	sbc	hl, de
	sbc	hl, bc
; if carry is not set, then the size can be readed from the inode
	jr	nc, .read_no_clamp
; readable size = inode_size - offset
	add	hl, bc
	ex	(sp), hl	; save back the new value into bc
.read_no_clamp:
	pop	bc
	pop	de
	pop	hl
	push	hl
	add	hl, bc
	ld	(ix+KERNEL_THREAD_FILE_DESCRIPTOR+KERNEL_VFS_FILE_OFFSET), hl
; convert hl to block (16 blocks per indirect, 1024 bytes per block)
; hl / 1024 : offset in block
	dec	sp
	pop	hl
	inc	sp
	ld	a, l
	srl	h
	rra
	srl	h
	rra
; a = block offset, de buffer, bc count
; now let's read
; first the lock
; if NDELAY is set, use try_lock
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
; KERNEL_VFS_O_NDELAY (128)
	bit	7, (ix+KERNEL_THREAD_FILE_DESCRIPTOR + KERNEL_VFS_FILE_FLAGS)
	jr	nz, .read_ndelay
	call	atomic_rw.lock_read
.read_start:
	push	bc
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
	call	atomic_rw.unlock_read
	pop	hl	; our size read
	ret
.read_ndelay:
;	call	atomic_rw.try_lock_read
; TODO : implement
	scf
	jr	nc, .read_start
.read_error_again:
	ld	l, EAGAIN
	jp	.set_errno
	
sysdef _write
.write:
	ret

sysdef _ioctl
.ioctl:
	ret
	
sysdef _pipe
.pipe:
	ret

sysdef _mkdir
.mkdir:
	ret

sysdef _rmdir
.rmdir:
	ret

sysdef _dup
.dup:
	ret
	
sysdef _chroot
.chroot:
	ret
