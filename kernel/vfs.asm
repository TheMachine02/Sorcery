; inode flags = (permission or type)
; permission, read/write/execute - map to posix "other" permission. THIS IS "MODE"
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

define	KERNEL_VFS_PERMISSION_R_BIT		0
define	KERNEL_VFS_PERMISSION_W_BIT		1
define	KERNEL_VFS_PERMISSION_X_BIT		2
define	KERNEL_VFS_TYPE_DIRECTORY_BIT		3
define	KERNEL_VFS_TYPE_CHARACTER_DEVICE_BIT	4
define	KERNEL_VFS_TYPE_BLOCK_DEVICE_BIT	5
define	KERNEL_VFS_TYPE_FIFO_BIT		6
define	KERNEL_VFS_TYPE_SYMLINK_BIT		7

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

sysdef _open
.open:
; open(const char* path, int flags, mode_t mode)
; hl is path, bc is flags, de is mode
; TODO : use create OR find based on O_CREAT
	push	de
	push	hl
	push	bc
	call	.inode_find
	pop	bc
	pop	hl
	pop	de
	jr	c, .open_create
; check if both excl and creat are set
	ld	a, b
	and	a, KERNEL_VFS_O_CREAT or KERNEL_VFS_O_EXCL
	sub	a, KERNEL_VFS_O_CREAT or KERNEL_VFS_O_EXCL
	ld	a, EEXIST
	jp	z, syserror
	jr	.open_continue
.open_create:
; check that flag O_CREAT set
	bit	1, b
	ld	a, ENOENT
	jp	z, syserror
	ld	a, e
; a is our mode, and hl is path
	push	bc
; the .inode create reparse the filesystem for creating the inode
; so it could return EEXIST if someone created the file between the first "find" and this .inode_create
; TODO : fix race condition
	call	.inode_create
	pop	bc
; if inode create c, the eror should already have been set, so just return
	ret	c
.open_continue:
; iy = node
; now find free file descriptor
; we can drop b from flags, it is useless now
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
	ld	a, EMFILE
	jp	syserror
.open_descriptor_found:
; check file permission
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_PERMISSION_RWX
	and	a, c
	xor	a, c
	ld	a, EACCES
	jp	nz, syserror
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
	ret

sysdef _close
.close:
; TODO ; finish to implement
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
	ld	a, EBADF
	jp	z, syserror
; check we have read permission
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_R_BIT, (ix+KERNEL_THREAD_FILE_DESCRIPTOR + KERNEL_VFS_FILE_FLAGS)
	jp	z, syserror
	ld	iy, (ix+KERNEL_THREAD_FILE_DESCRIPTOR+KERNEL_VFS_FILE_INODE)	; get inode
; hl is offset in file, iy is inode, de is buffer, bc is count
	push	hl
; first the lock
; if NDELAY is set, use try_lock
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
; KERNEL_VFS_O_NDELAY (128)
	bit	7, (ix+KERNEL_THREAD_FILE_DESCRIPTOR + KERNEL_VFS_FILE_FLAGS)
	jp	nz, .read_ndelay
	call	atomic_rw.lock_read
.read_ndelay_return:
	pop	hl
; check inode flag right now
; if block device or character device, directly pass 
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	tst	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE or KERNEL_VFS_TYPE_BLOCK_DEVICE
; passthrough char / block device / fifo driver directly
	jp	nz, .read_phy_device
	bit	KERNEL_VFS_TYPE_FIFO_BIT, a
	jp	nz, .read_fifo
; well, we have a directory opened right here
	bit	KERNEL_VFS_TYPE_DIRECTORY_BIT, a
	ld	a, EISDIR
	jp	nz, syserror
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
.read_unlock:
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	pop	hl	; our size read
	ret
.read_ndelay:
; TODO : implement
;	call	atomic_rw.try_lock_read
	scf
	jp	nc, .read_ndelay_return
	ld	a, EAGAIN
	jp	syserror
.read_phy_device:
	push	iy
	ld	iy, (iy+KERNEL_VFS_INODE_OP)
	lea	iy, iy+phy_read
	call	.read_indirect_call
	pop	iy
	jr	.read_unlock
.read_fifo:
; the inode is special in case of a fifo
; the 48 bytes data block hold all the fifo data
; (if end are opened, in write / read, the block data for fifo, and the internal fifo data)
; TODO : check if the fifo can be read / write
; iy is the inode
	push	iy
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	call	fifo.read
	pop	iy
; save the size readed
	push	hl
	jr	.read_unlock
.read_indirect_call:
	jp	(iy)
	
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
; int mkdir(const char *pathname, mode_t mode)
	ld	a, KERNEL_VFS_TYPE_DIRECTORY
	call	.inode_create
; return iy = inode
; if carry, it mean we have an error (already set)
	ret	c
; here, we need to fill inode data, none since it is a directory (empty)
; so just put the inode and unlock it (write locked by inode create)
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	or	a, a
	sbc	hl, hl
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

sysdef _chmod
.chmod:
; hl is path, bc is new mode
	push	bc
	call	.inode_find
	pop	bc
; if carry, error should have been set (could be acess in read/write/file not found etc)
	jp	c, .inode_atomic_error
; iy is the inode (locked), c is mode
; write permission ?
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_W_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	jp	z, .inode_atomic_error
	jr	.chmod_shared
	
sysdef _fchmod
.fchmod:
; hl is fd, bc is new mode
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	iy, (kthread_current)
	ex	de, hl
	add	iy, de
	ex	de, hl
	ld	hl, (iy+KERNEL_THREAD_FILE_DESCRIPTOR + KERNEL_VFS_FILE_OFFSET)
; check if the fd is valid
; if not open / invalid, all data should be zero here
	add	hl, de
	or	a, a
	sbc	hl, de
	ld	a, EBADF
	jp	z, syserror
	ld	iy, (iy+KERNEL_THREAD_FILE_DESCRIPTOR+KERNEL_VFS_FILE_INODE)
; write permission ?
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_W_BIT, (iy+KERNEL_THREAD_FILE_DESCRIPTOR + KERNEL_VFS_FILE_FLAGS)
	jp	z, syserror
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
.chmod_shared:
; read the inode
	ld	a, c
	and	a, KERNEL_VFS_PERMISSION_RWX
	ld	c, a
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, not KERNEL_VFS_PERMISSION_RWX
	or	a, c
	ld	(iy+KERNEL_VFS_INODE_FLAGS), a
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	or	a, a
	sbc	hl, hl
	ret

sysdef _chown
sysdef _fchown
; TODO : maybe later ?
.chown:
.fchown:
; no-op here
	or	a, a
	sbc	hl, hl
	ret

sysdef _mknod
.mknod:
; int mknod(const char *pathname, mode_t mode, dev_t dev)
; hl is path, bc is mode, de is dev (ie memory ops)
	push	de
	ld	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE
	call	.inode_create
	pop	de
	ret	c
	ld	(iy+KERNEL_VFS_INODE_OP), de
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	or	a, a
	sbc	hl, hl
	ret
	
sysdef _mkfifo
.mkfifo:
; a bit more complex, but anyway
; int mkfifo(const char *pathname, mode_t mode)
	ld	a, KERNEL_VFS_TYPE_FIFO
	call	.inode_create
	ret	c
; we need to allocate a fifo block of data and put it in the data block
; iy is our inode
	ld	hl, FIFO_MAX_SIZE
	call	kmalloc
	ld	a, ENOMEM
	jp	c, syserror
; hl is the memory block
	push	hl
	ex	de, hl
; point iy to raw data
	pea	iy + KERNEL_VFS_INODE_ATOMIC_LOCK
	lea	iy, iy + KERNEL_VFS_INODE_DATA
	call	fifo.create
	pop	hl
	call	atomic_rw.unlock_write	
	or	a, a
	sbc	hl, hl
	ret


