; inode flags = (permission or type)
; permission, read/write/execute - map to posix "other" permission. THIS IS "MODE"
define	KERNEL_VFS_PERMISSION_R			1
define	KERNEL_VFS_PERMISSION_W			2
define	KERNEL_VFS_PERMISSION_X			4
define	KERNEL_VFS_PERMISSION_RW		3
define	KERNEL_VFS_PERMISSION_RWX		7
define	KERNEL_VFS_PERMISSION_RX		5
define	KERNEL_VFS_PERMISSION_WX		6
define	KERNEL_VFS_PERMISSION_DMA		8
; please note that file is not a set bit by if inode_flag&TYPE_FILE==0
define	KERNEL_VFS_TYPE_FILE_MASK		248
define	KERNEL_VFS_TYPE_FILE			0
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
define	KERNEL_VFS_FILE_FLAGS			6	; 1 byte, file flags, mode

; file flags that control *file*
; we can & those with permission to check mode
define	KERNEL_VFS_O_R				1
define	KERNEL_VFS_O_W				2
define	KERNEL_VFS_O_RW				3
define	KERNEL_VFS_O_TMPFILE			4	; create a temporary file
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

define	SEEK_SET				0
define	SEEK_CUR				1
define	SEEK_END				2

; 20 bytes
define	STAT_DEVICE				0
define	STAT_INODE				3
define	STAT_MODE				6
define	STAT_LINK				7
define	STAT_RDEVICE				8
define	STAT_BLKSIZE				11
define	STAT_BLKCNT				14
define	STAT_SIZE				17

define	R_OK					1
define	W_OK					2
define	X_OK					4

kvfs:

.phy_indirect_call:
	jp	(iy)

.fd_pointer_check:
; return nc is corret, c with error set if not
; ix = file descriptor, iy = inode
; destroy hl
; 0 - 22 or 23 descriptor
	ld	a, l
	cp	a, KERNEL_THREAD_FILE_DESCRIPTOR_MAX
	ld	a, EBADF
	jp	nc, syserror
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
	jp	z, syserror
; reset carry
	or	a, a
	ret

sysdef _open
.open:
; open(const char* path, int flags, mode_t mode)
; hl is path, bc is flags, de is mode
	push	de
	push	bc
	call	.inode_directory_get_lock
	pop	bc
	pop	de
	ret	c
; here the DIRECTORY is locked for write
	push	hl
	push	de
	push	bc
	call	.inode_directory_lookup
	pop	bc
	pop	de
	pop	hl
; dir is still locked, ix is our file (or not, if carry)
	jr	c, .open_create
; check we didn't ask exclusive creation
; check if both excl and creat are set
	ld	a, b
	and	a, KERNEL_VFS_O_CREAT or KERNEL_VFS_O_EXCL
	sub	a, KERNEL_VFS_O_CREAT or KERNEL_VFS_O_EXCL
	ld	a, EEXIST
	jp	z, .inode_atomic_write_error
; drop parent lock and get our
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	lea	iy, ix+0
	jr	.open_continue
.open_create:
; check that flag O_CREAT set
	bit	1, b
	ld	a, ENOENT
	jp	z, .inode_atomic_write_error
	push	bc
; mode & inode type in de
	ld	d, e
	ld	e, KERNEL_VFS_PERMISSION_RWX
	call	.inode_create_parent
	pop	bc
; if inode create c, the eror should already have been set, so just return
	ret	c
; unlock the child, create parent does always unlock the parent inode (in case of error or sucess)
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
.open_continue:
; iy = node
; now find free file descriptor
; we can drop b from flags, it is useless now
	ld	ix, (kthread_current)
	lea	ix, ix+KERNEL_THREAD_FILE_DESCRIPTOR + 24
	ld	b, KERNEL_THREAD_FILE_DESCRIPTOR_MAX - 3
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
	and	a, KERNEL_VFS_TYPE_FILE_MASK
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
; 	call	.fd_pointer_check
; 	ret	c
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
; TODO : implement
; sync() causes all pending modifications to filesystem metadata and
; cached file data to be written to the underlying filesystems
; ie, call phy_sync for all file modified and not yet written
.sync:
	ret
	
; TODO : read and write are almost the SAME routine
; can we merge it ?

sysdef _read
.read:
;;size_t read(int fd, void *buf, size_t count);
; hl is fd, void *buf is de, size_t count is bc
; pad count to inode_file_size
; return size read
; TODO : maybe hide the FD data to the thread
	call	.fd_pointer_check
	ret	c
; check we have read permission
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_R_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
	jp	z, syserror
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
; hl is offset in file, iy is inode, de is buffer, bc is count
	push	hl
; first the lock
; if NDELAY is set, use try_lock
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
; KERNEL_VFS_O_NDELAY (128)
	bit	7, (ix+KERNEL_VFS_FILE_FLAGS)
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
	jp	nz, .inode_atomic_read_error
; FIXME : welp, it is broken from here to the end
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
	push	hl
	add	hl, bc
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
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
	pop	hl
; hl = still the offset in the file, bc = size to read, de = buffer, a = block
; hl mod 1024
	push	af
	ld	a, l
	rl	h
	ld	hl, 0
	ld	l, a
	sbc	a, a
	and	a, 00000001b
	ld	h, a
	pop	af
; start reading the file
; first block is in size 1024 - hl long maximum
	push	bc
	push	bc
	pop	ix
; ix will be size
	push	hl
	ld	bc, -1024
	add	hl, bc
	push	hl
; we have (offset mod 1024) - 1024
; size - (1024-modoffset)) > 0 ?
	lea	bc, ix+0
	add	hl, bc
; hl > 0 ?
	add	hl, de
	or	a, a
	sbc	hl, de
	pop	bc
	pop	hl
	jp	m, .read_end_single_copy
; copy(modoffset, buffer, 1024-modoffset)
; hl set, bc is not *yet* set
	add	ix, bc
; we need to negate bc
	push	hl
	ld	h, a
	ld	a, c
	ld	l, b
	ld	bc, $FFFFFF
	cpl
	ld	c, a
	ld	a, l
	cpl
	ld	b, a
	inc	bc
	ld	a, h
	pop	hl
; a is set, bc is set, hl is set, de is set
	call	.read_buff
	inc	a
	lea	hl, ix+0
.read_copy:
	ld	bc, KERNEL_MM_PAGE_SIZE
	or	a, a
	sbc	hl, bc
	jr	c, .read_copy_end
	push	hl
	or	a, a
	sbc	hl, hl
	call	.read_buff
	pop	hl
	inc	a
	jr	.read_copy
.read_copy_end:
; end copy
	add	hl, bc
	push	hl
	pop	bc
.read_end_single_copy:
	or	a, a
	sbc	hl, hl
	call	.read_buff
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
	call	.phy_indirect_call
	pop	iy
	push	hl
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
; complex logic to read from the inode structure
.read_buff:
; hl = 1024 bytes offset, de = buffer, bc = size, a = block count
; the inner data logic
	push	hl
	call	.inode_block_data
	ld	a, (hl)
	or	a, a
	jr	z, .read_buff_cache_miss
; get data from cache
	ld	hl, KERNEL_MM_RAM shr 2
	ld	h, a
	add	hl, hl
	add	hl, hl
.read_buff_do:
	ex	de, hl
	ex	(sp), hl
	add	hl, de
	pop	de
	ldir
	ret
.read_buff_cache_miss:
	inc	hl
	ld	hl, (hl)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	nz, .read_buff_do
	ld	hl, KERNEL_MM_NULL
	jr	.read_buff_do
	
sysdef _write
.write:
	call	.fd_pointer_check
	ret	c
; check we have read permission
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_W_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
	jp	z, syserror
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
; hl is offset in file, iy is inode, de is buffer, bc is count
	push	hl
; first the lock
; if NDELAY is set, use try_lock
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
; KERNEL_VFS_O_NDELAY (128)
	bit	7, (ix+KERNEL_VFS_FILE_FLAGS)
	jp	nz, .write_ndelay
	call	atomic_rw.lock_write
.write_ndelay_return:
	pop	hl
; test the inode for type
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	tst	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE or KERNEL_VFS_TYPE_BLOCK_DEVICE
; passthrough char / block device / fifo driver directly
	jp	nz, .write_phy_device
	bit	KERNEL_VFS_TYPE_FIFO_BIT, a
	jp	nz, .write_fifo
; well, we have a directory opened right here
	bit	KERNEL_VFS_TYPE_DIRECTORY_BIT, a
	ld	a, EISDIR
	jp	nz, .inode_atomic_write_error
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
	push	hl
	add	hl, bc
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
; FIXME : welp, it is broken from here to the end
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
; now let's write
; FIXME : write can only occur at 1024 bytes alignement
.write_start:
	push	bc
	push	bc
	pop	hl
.write_copy:
	ld	bc, KERNEL_MM_PAGE_SIZE
	or	a, a
	sbc	hl, bc
	jr	c, .write_copy_end
	push	hl
	call	.write_buff
	pop	hl
	jr	c, .write_error
	inc	a
	jr	.write_copy
.write_copy_end:
; end copy
	add	hl, bc
	push	hl
	pop	bc
	call	.write_buff
	jr	c, .write_error
.write_unlock:
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	pop	hl	; our size written
	ret
.write_error:
	pop	hl
	jp	.inode_atomic_write_error

.write_ndelay:
; TODO : implement
;	call	atomic_rw.try_lock_write
	scf
	jp	nc, .write_ndelay_return
	ld	a, EAGAIN
	jp	syserror
.write_phy_device:
	ex	de, hl
; expect string hl, size bc, de offset
	push	iy
	ld	iy, (iy+KERNEL_VFS_INODE_OP)
	lea	iy, iy+phy_write
	call	.phy_indirect_call
	pop	iy
	push	hl
	jr	.write_unlock
.write_fifo:
; the inode is special in case of a fifo
; the 48 bytes data block hold all the fifo data
; (if end are opened, in write / read, the block data for fifo, and the internal fifo data)
; TODO : check if the fifo can be read / write
; iy is the inode
	push	iy
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	call	fifo.write
	pop	iy
; save the size readed
	push	hl
	jr	.write_unlock
; complex logic for writing to data block
.write_buff:
; the inner data logic
	call	.inode_block_data
	ld	a, (hl)
	or	a, a
	jr	z, .write_buff_cache_miss
.write_buff_do:
; set dirty
	ld	hl, kmm_ptlb_map
	ld	l, a
	set	KERNEL_MM_PAGE_DIRTY, (hl)
; get data from cache
	ld	hl, KERNEL_MM_RAM shr 2
	ld	h, a
	add	hl, hl
	add	hl, hl
	ex	de, hl
	ldir
	ex	de, hl
	ret
.write_buff_cache_miss:
; here, we need to allocate data
	call	cache.page_map
	ret	c
	ld	(hl), a
	inc	hl
	ld	hl, (hl)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .write_buff_do
; so we need to read from backing device here
; iy = inode
	push	af
	ex	de, hl
	ld	hl, KERNEL_MM_RAM shr 2
	ld	h, a
	add	hl, hl
	add	hl, hl
	ex	de, hl
	push	iy
	ld	iy, (iy+KERNEL_VFS_INODE_OP)
; hl = data from inode, bc is size (1024), de is my memory page
	lea	iy, iy+phy_read
	call	.phy_indirect_call
	pop	iy
	pop	af
	jr	.write_buff_do
	
sysdef _ioctl
.ioctl:
; hl is fd, de is request
	call	.fd_pointer_check
	ret	c
; is the inode is a block or a character device ?
; README : the need to lock for read is dummy since we have already open this inode and the flags inode should NEVER change for TYPE
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_BLOCK_DEVICE or KERNEL_VFS_TYPE_CHARACTER_DEVICE
	ld	a, ENOTTY
	jp	z, syserror
; now, just pass to ioctl of file
	ld	iy, (iy+KERNEL_VFS_INODE_OP)
	lea	iy, iy+phy_ioctl
	ex	de, hl
; hl is request
	jp	(iy)
	
sysdef _pipe
; TODO : implement
.pipe:
	ret

sysdef _mkdir
.mkdir:
; int mkdir(const char *pathname, mode_t mode)
; hl is path, bc is mode
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
; TODO : implement
.rmdir:
	ret

sysdef _chmod
.chmod:
; hl is path, bc is new mode
	push	bc
	call	.inode_get_lock
	pop	bc
; if carry, error should have been set (could be acess in read/write/file not found etc) (return non locked)
	ret	c
; iy is the inode (locked), c is mode
; write permission ?
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_W_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	jp	z, .inode_atomic_write_error
	jr	.chmod_shared
	
sysdef _fchmod
.fchmod:
; hl is fd, bc is new mode
	call	.fd_pointer_check
	ret	c
; write permission ?
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_W_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
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
; mode hold everything (and also the file type)
	ld	a, c
	and	a, not KERNEL_VFS_PERMISSION_RWX
; NOTE : mknod can create any type of file with the dev
	call	.inode_create
	pop	de
	ret	c
; TODO : device list and actual fetching of data for the memops
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
; bc is mode, hl is path
	ld	a, KERNEL_VFS_TYPE_FIFO
	call	.inode_create
	ret	c
; we need to allocate a fifo block of data and put it in the data block
; iy is our inode
	ld	hl, FIFO_MAX_SIZE
	call	kmalloc
	ld	a, ENOMEM
	jp	c, .inode_atomic_write_error
; hl is the memory block
; point iy to raw data
	pea	iy + KERNEL_VFS_INODE_ATOMIC_LOCK
	lea	iy, iy + KERNEL_VFS_INODE_DATA
	call	fifo.create
	pop	hl
	call	atomic_rw.unlock_write	
	or	a, a
	sbc	hl, hl
	ret

sysdef _lseek
.lseek:
;; off_t lseek(int fd, off_t offset, int whence);   
; SEEK_SET
;     La tête est placée à offset octets depuis le début du fichier. 
; SEEK_CUR
;     La tête de lecture/écriture est avancée de offset octets. 
; SEEK_END
;     La tête est placée à la fin du fichier plus offset octets. 
; ; fd is hl, de is offset, bc is whence
	call	.fd_pointer_check
	ret	c
; is the inode permit the seek ?
; rule : directory permit (but ignored and useless), character device ESPIPE, fifo ESPIPE, block device permit, symlink should NOT happen
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE or KERNEL_VFS_TYPE_FIFO
	ld	a, ESPIPE
	jp	nz, syserror
; so now, we have the offset de
	ld	a, c
	or	a, a
	jr	z, .lseek_set
	dec	a
	jr	z, .lseek_cur
	dec	a
	jr	z, .lseek_end
	ld	a, EINVAL
	jp	syserror
.lseek_set:
	ld	(ix+KERNEL_VFS_FILE_OFFSET), de
	ex	de, hl
	or	a, a
	ret
.lseek_cur:
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
	add	hl, de
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
	ret	nc
	ld	a, EOVERFLOW
	jp	syserror
.lseek_end:
	ld	hl, (iy+KERNEL_VFS_INODE_SIZE)
	add	hl, de
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
	ret	nc
	ld	a, EOVERFLOW
	jp	syserror

sysdef _fstat
.fstat:
; int fstat(int fd, struct stat *statbuf);
; hl is fd, de is statbuf
	call	.fd_pointer_check
	ret	c
; read permission ?
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_R_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
	jp	z, syserror
	push	de
	pop	ix
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	jr	.stat_fill

sysdef _stat
.stat:
; int stat(const char *pathname, struct stat *statbuf);
; dev_t     st_dev;         ID of device containing file
; ino_t     st_ino;         Inode number
; mode_t    st_mode;        File type and mode (1 byte) (expose if DMA is available)
; nlink_t   st_nlink;       Number of hard links (1 byte)
; dev_t     st_rdev;        Device ID (if special file)
; off_t     st_size;        Total size, in bytes
; blksize_t st_blksize;     Block size for filesystem I/O
; blkcnt_t  st_blocks;      Number of 1024 bytes blocks allocated
; hl is path, de is statbuff
	push	de
	call	.inode_get_lock
	pop	ix
; if carry, error should have been set (could be acess in read/write/file not found etc) (return non locked)
	ret	c
.stat_fill:
; iy is inode
; copy data
	ld	(ix+STAT_INODE), iy
	or	a, a
	sbc	hl, hl
	ld	(ix+STAT_DEVICE), hl
	ld	a, (iy+KERNEL_VFS_INODE_REFERENCE)
	dec	a
	ld	(ix+STAT_LINK), a
; find the correct device number
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	(ix+STAT_MODE), a
	and	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE or KERNEL_VFS_TYPE_BLOCK_DEVICE
	jr	z, .stat_no_device
	ld	(ix+STAT_SIZE), hl
	ld	(ix+STAT_BLKCNT), hl
	ld	(ix+STAT_BLKSIZE), hl
	ld	hl, (iy+KERNEL_VFS_INODE_DEVICE)
	ld	(ix+STAT_RDEVICE), hl
	jr	.stat_continue
.stat_no_device:
	ld	(ix+STAT_RDEVICE), hl
	ld	hl, (iy+KERNEL_VFS_INODE_SIZE)
	ld	(ix+STAT_SIZE), hl
	ld	hl, 1024
	ld	(ix+STAT_BLKSIZE), hl
	ld	de, 0
; 256 entries to parse, it is quite slow
; TODO : find a faster way to count those block
	ld	c, 16
	lea	hl, iy+KERNEL_VFS_INODE_DATA
.stat_indirect_block:
	push	hl
	ld	hl, (hl)
	ld	b, 16
.stat_direct_block:
	inc	hl
	push	hl
	ld	hl, (hl)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .stat_noinc
	inc	de
.stat_noinc:
	pop	hl
	inc	hl
	inc	hl
	inc	hl
	djnz	.stat_indirect_block
	pop	hl
	dec	c
	jr	nz, .stat_indirect_block
	ld	(ix+STAT_BLKCNT), de
.stat_continue:
	lea	hl, iy + KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	or	a, a
	sbc	hl, hl
	ret

sysdef _dup
; TODO : implement
.dup:
	ret
	
sysdef _chroot
; TODO : implement
.chroot:
	ret

sysdef _access
; int access(const char *pathname, int mode);
.access:
; hl is path, de is mode
	push	de
	call	.inode_get_lock
	pop	de
	ret	c
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, e
	xor	a, e
	and	a, KERNEL_VFS_PERMISSION_RWX
	ld	a, EACCES
	jr	nz, .stat_continue
	jp	.inode_atomic_write_error

sysdef _chdir
.chdir:
;       int chdir(const char *path);
;       int fchdir(int fd);
	call	.inode_get_lock
	ret	c
.chdir_common:
; iy is the inode
	bit	KERNEL_VFS_TYPE_DIRECTORY_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	jp	z, .inode_atomic_write_error
; iy is valid
	ld	ix, (kthread_current)
	ld	(ix+KERNEL_THREAD_WORKING_DIRECTORY), ix
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	or	a, a
	sbc	hl, hl
	ret
	
sysdef _fchdir
.fchdir:
	call	.fd_pointer_check
	ret	c
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	jr	.chdir_common

