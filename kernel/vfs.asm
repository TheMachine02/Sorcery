; inode flags = (permission or type or capability)

define	KERNEL_VFS_PERMISSION_MASK		00000111b
define	KERNEL_VFS_TYPE_MASK			00111000b
define	KERNEL_VFS_CAPABILITY_MASK		11000000b

; permission, read/write/execute - map to posix "other" permission. THIS IS "MODE"
define	KERNEL_VFS_PERMISSION_R			1
define	KERNEL_VFS_PERMISSION_W			2
define	KERNEL_VFS_PERMISSION_X			4
define	KERNEL_VFS_PERMISSION_RW		3
define	KERNEL_VFS_PERMISSION_RWX		7
define	KERNEL_VFS_PERMISSION_RX		5
define	KERNEL_VFS_PERMISSION_WX		6
define	KERNEL_VFS_PERMISSION_R_BIT		0
define	KERNEL_VFS_PERMISSION_W_BIT		1
define	KERNEL_VFS_PERMISSION_X_BIT		2

define	KERNEL_VFS_TYPE_FILE			0 shl 3
define	KERNEL_VFS_TYPE_DIRECTORY		1 shl 3
define	KERNEL_VFS_TYPE_CHARACTER_DEVICE	2 shl 3
define	KERNEL_VFS_TYPE_BLOCK_DEVICE		3 shl 3
define	KERNEL_VFS_TYPE_FIFO			4 shl 3
define	KERNEL_VFS_TYPE_SYMLINK			5 shl 3
define	KERNEL_VFS_TYPE_SOCKET			6 shl 3

define	KERNEL_VFS_CAPABILITY_DMA		64		; direct pointer acess
define	KERNEL_VFS_CAPABILITY_ACCESS		128		; in use bit
define	KERNEL_VFS_CAPABILITY_DMA_BIT		6		; is the inode support DMA
define	KERNEL_VFS_CAPABILITY_ACCESS_BIT	7		; is the inode is currently being DMA acessed

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

define	KERNEL_VFS_MAX_FOLLOW			4

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
	jp	nc, user_error
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
	jp	z, user_error
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
	ld	ix, (ix+KERNEL_VFS_DIRECTORY_INODE)
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
	ld	d, KERNEL_VFS_TYPE_FILE
	ld	e, KERNEL_VFS_PERMISSION_RWX
	call	.inode_create_parent
	pop	bc
; if inode create c, the eror should already have been set, so just return
	ret	c
; unlock the child, create parent does always unlock the parent inode (in case of error or sucess)
; increment the reference
	inc	(iy+KERNEL_VFS_INODE_REFERENCE)
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
.open_continue:
; iy = node
; check file permission
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_PERMISSION_RWX
	and	a, c
	xor	a, c
	ld	a, EACCES
	jp	nz, user_error
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
	jp	user_error
.open_descriptor_found:
	ld	e, d
	ld	(ix+KERNEL_VFS_FILE_INODE), iy
	ld	(ix+KERNEL_VFS_FILE_OFFSET), de
; write important file flags
	ld	(ix+KERNEL_VFS_FILE_FLAGS), c
; mark fifo as open (read / write)
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_FIFO
	jr	nz, .open_check_trunc
	push	af
	ld	a, c
	and	a, KERNEL_VFS_O_RW
	or	a, (iy+FIFO_ENDPOINT)
	ld	(iy+FIFO_ENDPOINT), a
	pop	af
.open_check_trunc:
	bit	3, c	; O_TRUNC
	jr	z, .extract_fd
; if KERNEL_VFS_O_TRUNC is set in c, and the file is a normal file (not a fifo or char or block) reset the file to size 0 (drop all data)
	or	a, a
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
; hl is fd
	call	.fd_pointer_check
	ret	c
; ix is the pointer to fd, iy is the inode
	lea	de, ix+0
	ld	hl, $E40000+(KERNEL_VFS_TYPE_MASK*256)
	ld	bc, KERNEL_VFS_FILE_DESCRIPTOR_SIZE
	ldir
; if the inode is KERNEL_VFS_TYPE_FILE
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, h
	jr	nz, .close_no
; call the special sync file (write all dirty to flash)
	ld	ix, (iy+KERNEL_VFS_INODE_OP)
	lea	hl, ix+phy_sync
	push	iy
	call	.inode_call
	pop	iy
.close_no:
; and put the inode, decrement reference
	call	.inode_deref
	or	a, a
	sbc	hl, hl
	ret

sysdef _sync
; TODO : implement
; sync() causes all pending modifications to filesystem metadata and
; cached file data to be written to the underlying filesystems
; ie, call phy_sync for all file modified and not yet written
.sync:
	ret

sysdef _read
.read:
;;size_t read(int fd, void *buf, size_t count);
; hl is fd, void *buf is de, size_t count is bc
; pad count to inode_file_size
; return size read
	call	.fd_pointer_check
	ret	c
; check we have read permission
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_R_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
	jp	z, user_error
; iy is inode, de is buffer, bc is count
; first the lock
; if NDELAY is set, use try_lock
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
; KERNEL_VFS_O_NDELAY (128)
	bit	7, (ix+KERNEL_VFS_FILE_FLAGS)
	jr	z, .read_delay
	call	atomic_rw.try_lock_read
	jr	nc, .read_ndelay
	ld	a, EAGAIN
	jp	user_error
.read_delay:
	call	atomic_rw.lock_read
.read_ndelay:
; check inode flag right now
; if block device or character device, directly pass 
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
; NOTE : we mask type or capability : any of the following test can't have dma set anyway
; and we'll need to test it after
	and	a, KERNEL_VFS_TYPE_MASK or KERNEL_VFS_CAPABILITY_DMA
	cp	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE
; passthrough char / block device / fifo driver directly
	jr	z, .read_char_device
	cp	a, KERNEL_VFS_TYPE_BLOCK_DEVICE
	jr	z, .read_block_device
	cp	a, KERNEL_VFS_TYPE_FIFO
	jr	z, .read_fifo
	cp	a, KERNEL_VFS_TYPE_DIRECTORY
	ld	a, EISDIR
	jr	nz, .read_file
	jp	.inode_atomic_read_error
.read_block_device:
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
	push	hl
	add	hl, bc
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
	pop	hl
.read_char_device:
	push	iy
	ld	iy, (iy+KERNEL_VFS_INODE_OP)
	lea	iy, iy+phy_read
	call	.phy_indirect_call
	pop	iy
	push	hl
	jp	.read_unlock
.read_fifo:
; the inode is special in case of a fifo
; the 48 bytes data block hold all the fifo data
; (if end are opened, in write / read, the block data for fifo, and the internal fifo data)
; iy is the inode
	lea	iy, iy+KERNEL_VFS_INODE_FIFO_DATA
	ld	a, (iy+FIFO_ENDPOINT)
; both read and write should be set
	xor	a, FIFO_READ_OPEN or FIFO_WRITE_OPEN
	ld	a, EBADF
	jp	nz, user_error
	call	fifo.read
	lea	iy, iy-KERNEL_VFS_INODE_FIFO_DATA
; save the size readed
	push	hl
	jr	.read_unlock
.read_null:
	or	a, a
	sbc	hl, hl
	ex	(sp), hl
	jr	.read_unlock
.read_file:
; offset = file offset
; if ((offset + size) > inode_size) { size = inode_size - offset; }
; if (size==0) return inode_unlock();
; block = offset >> 10
; block_offset = offset % 1024
; if ( (block_offset + size) < 1024){
; 	read_buff(block_offset, buff, size, count);
;	return inode_unlock();
; }
; size_0 = 1024 - block_offset;
; size = size - size_0;
; read_buff(block_offset, buff, size_0, count);
; count++
; while(size > 1024) {
; 	read_buff(0, buff, 1024, count++);
;	size = size - 1024;
; }
; read_buff(0, buff, size, count);
; return inode_unlock();
; let's start the logic
; if ((offset + size) > inode_size) { size = inode_size - offset; }
	push	de
	ld	hl, (iy+KERNEL_VFS_INODE_SIZE)
	ld	de, (ix+KERNEL_VFS_FILE_OFFSET)
	or	a, a
	sbc	hl, de
; offset > inode_size, so we can't read
	jr	c, .read_null
	sbc	hl, bc
	jr	nc, .read_adjust
	add	hl, bc
	push	hl
	pop	bc
; adjust size
.read_adjust:
	push	bc
	pop	hl
	add	hl, bc
	or	a, a
	sbc	hl, bc
	jr	z, .read_null
	pop	de
	push	bc
	push	de
; bc = size, hl = offset, de = buffer
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET + 1)
; convert hl to block (16 blocks per indirect, 1024 bytes per block)
; hl >> 10 : block count
	ld	a, l
	srl	h
	rra
	srl	h
	rra
; now, we need the modulo
	ld	de, 0
	ld	e, (ix+KERNEL_VFS_FILE_OFFSET)
; get the last digit
	ld	a, (ix+KERNEL_VFS_FILE_OFFSET+1)
	and	a, 00000001b
	ld	d, a
; de is the block_offset
; we can update offset right here
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
	add	hl, bc
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
; (block_offset + size) < 1024 ?
	ld	hl, KERNEL_MM_PAGE_SIZE
	or	a, a
	sbc	hl, de
	jr	c, .read_multiple
	sbc	hl, bc
	jr	c, .read_multiple_offset
	ex	de, hl
	pop	de
; a, de, bc, hl are all set
	call	.read_buff
	jr	.read_unlock
.read_multiple_offset:
	add	hl, bc
.read_multiple:
; size_0 = 1024 - block_offset; ( = hl right now)
; size = size - size_0;
; swap hl and bc
; de is block offset, keep it in mind
	push	bc
	ex	(sp), hl
	pop	bc
	or	a, a
	sbc	hl, bc
; push this on stack, get back the buff in de, get offset in hl
	ex	(sp), hl
	ex	de, hl
.read_copy_loop:
; hl = offset, de = buffer, bc = size, a = block
	call	.read_buff
	inc	a
	pop	hl
; hl = size
	or	a, a
	ld	bc, KERNEL_MM_PAGE_SIZE
	sbc	hl, bc
	jr	z, .read_unlock
	jr	nc, .read_copy_restore
	add	hl, bc
.read_copy_restore:
	push	hl
	sbc	hl, hl
	jr	nc, .read_copy_loop
	inc	hl
	pop	bc
	call	.read_buff
.read_unlock:
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
; pop our size read
	pop	hl
	ret
; complex logic to read from the inode structure
.read_buff:
; hl = offset mod 1024, de = buffer, bc = size (adapted to offset), a = block count
; the inner data logic
; iy is inode number (adress of the inode)
; a is block number (ie, file adress divided by KERNEL_MM_PAGE_SIZE)
; about alignement : block are at last 1024 bytes aligned
; block data is aligned to 4 bytes
; inode data is 64 bytes aligned
; block adress is : (block & 0x0F)*4 + inode[data+(block >> 4 * 3)]
	push	hl
	push	bc
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
; hl is the block_data adress structure in cache
	ld	a, (hl)
	or	a, a
	jr	z, .read_buff_cache_miss
; get data from cache
	ld	hl, KERNEL_MM_RAM shr 2
	ld	h, a
	add	hl, hl
	add	hl, hl
.read_buff_do:
	ld	a, b
	pop	bc
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
	jp	z, user_error
; hl is offset in file, iy is inode, de is buffer, bc is count
; first the lock
; if NDELAY is set, use try_lock
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
; KERNEL_VFS_O_NDELAY (128)
	bit	7, (ix+KERNEL_VFS_FILE_FLAGS)
	jr	z, .write_delay
	call	atomic_rw.try_lock_write
	jr	nc, .write_ndelay
	ld	a, EAGAIN
	jp	user_error
.write_delay:
	call	atomic_rw.lock_write
.write_ndelay:
; test the inode for type
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE
; passthrough char / block device / fifo driver directly
	jr	z, .write_char_device
	cp	a, KERNEL_VFS_TYPE_BLOCK_DEVICE
	jr	z, .write_block_device
	cp	a, KERNEL_VFS_TYPE_FIFO
	jr	z, .write_fifo
	cp	a, KERNEL_VFS_TYPE_DIRECTORY
	ld	a, EISDIR
	jr	nz, .write_file
	jp	.inode_atomic_write_error
.write_block_device:
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
	push	hl
	add	hl, bc
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
	pop	hl
.write_char_device:
; expect string hl, size bc, de offset
	push	iy
	ld	iy, (iy+KERNEL_VFS_INODE_OP)
	lea	iy, iy+phy_write
	call	.phy_indirect_call
	pop	iy
	push	hl
	jp	.write_unlock
.write_fifo:
; the inode is special in case of a fifo
; the 48 bytes data block hold all the fifo data
; (if end are opened, in write / read, the block data for fifo, and the internal fifo data)
; iy is the inode
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	ld	a, (iy+FIFO_ENDPOINT)
; both read and write should be set
	xor	a, FIFO_READ_OPEN or FIFO_WRITE_OPEN
	ld	a, EBADF
	jp	nz, user_error
	call	fifo.write
	lea	iy, iy-KERNEL_VFS_INODE_FIFO_DATA
; save the size readed
	push	hl
	jp	.write_unlock
.write_file:
; check size !=0
	push	bc
	pop	hl
	add	hl, bc
	or	a, a
	sbc	hl, bc
	jr	nz, .write_do
	push	hl
	jp	.write_unlock
.write_do:
; case if offset > max_file_size >>> set new offset = max_file_size & size = 0
	push	de
	ld	hl, KERNEL_VFS_INODE_FILE_SIZE
	ld	de, (ix+KERNEL_VFS_FILE_OFFSET)
	ld	a, EFBIG
	or	a, a
	sbc	hl, de
; past maximum file size
	jr	c, .write_atomic_error
; offset + size is past the maximum file size : error
	sbc	hl, bc
	jr	c, .write_atomic_error
; set new inode size
; inode_size = (offset + size) > inode_size ? (offset + size) : inode_size
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
	add	hl, bc
	ld	de, (iy+KERNEL_VFS_INODE_SIZE)
	or	a, a
	sbc	hl, de
	jr	c, .write_adjust_size
	add	hl, de
	ld	(iy+KERNEL_VFS_INODE_SIZE), hl
.write_adjust_size:
	pop	de
	push	bc
	push	de
; bc = size, hl = offset, de = buffer
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET + 1)
; convert hl to block (16 blocks per indirect, 1024 bytes per block)
; hl >> 10 : block count
	ld	a, l
	srl	h
	rra
	srl	h
	rra
; now, we need the modulo
	inc.s	de
	ld	e, (ix+KERNEL_VFS_FILE_OFFSET)
; get the last digit
	ld	a, (ix+KERNEL_VFS_FILE_OFFSET+1)
	and	a, 00000001b
	ld	d, a
; de is the block_offset
; we can update offset right here
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
	add	hl, bc
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
; (block_offset + size) < 1024 ?
	ld	hl, KERNEL_MM_PAGE_SIZE
	or	a, a
	sbc	hl, de
	jr	c, .write_multiple
	sbc	hl, bc
	jr	c, .write_multiple_offset
	ex	de, hl
	pop	de
; a, de, bc, hl are all set
	call	.write_buff
	jr	c, .write_atomic_error
	jr	.write_unlock
.write_multiple_offset:
	add	hl, bc
.write_multiple:
; size_0 = 1024 - block_offset; ( = hl right now)
; size = size - size_0;
; swap hl and bc
; de is block offset, keep it in mind
	push	bc
	ex	(sp), hl
	pop	bc
	or	a, a
	sbc	hl, bc
; push this on stack, get back the buff in de, get offset in hl
	ex	(sp), hl
	ex	de, hl
.write_copy_loop:
; hl = offset, de = buffer, bc = size, a = block
	call	.write_buff
	pop	hl
	jr	c, .write_atomic_error
	inc	a
; hl = size
	or	a, a
	ld	bc, KERNEL_MM_PAGE_SIZE
	sbc	hl, bc
	jr	z, .write_unlock
	jr	nc, .write_copy_restore
	add	hl, bc
.write_copy_restore:
	push	hl
	sbc	hl, hl
	jr	nc, .write_copy_loop
	inc	hl
	pop	bc
	call	.write_buff
	jr	c, .write_atomic_error
.write_unlock:
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
; pop our size writed
	pop	hl
	ret
.write_atomic_error:
	pop	hl
	push	af
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	pop	af
	jp	user_error
.write_error_pop_l3:
	pop	de
.write_error_pop_l2:
	pop	bc
	pop	hl
	ld	a, ENOMEM
	scf
	ret
; complex logic for writing to data block
.write_buff:
; the inner data logic
	push	hl
	push	bc
	push	de
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
	ld	de, (hl)
	ex	de, hl
; check if this was allocated, if not, allocate it
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	nz, .write_deref
	ld	hl, kmem_cache_s64
	call	kmem.cache_alloc
	jr	c, .write_error_pop_l3
	ex	de, hl
	ld	(hl), de
	ex	de, hl
.write_deref:
	pop	de
	ld	a, b
	and	a, 00001111b
; hl adress should be aligned to 64 bytes
	add	a, a
	add	a, a
	add	a, l
	ld	l, a
	ld	a, (hl)
	or	a, a
	jr	z, .write_buff_cache_miss
; cache hit, we can directly write
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
	ld	a, b
	pop	bc
	ex	de, hl
	ex	(sp), hl
	add	hl, de
	pop	de
	ex	de, hl
	ldir
	ex	de, hl
	ret
.write_buff_cache_miss:
; here, we need to allocate data
; following does not destroy bc
	call	cache.page_map
	jr	c, .write_error_pop_l2
	ld	(hl), a
	inc	hl
	ld	hl, (hl)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .write_buff_do
; so we need to read from backing device here
; iy = inode
	push	bc
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
	ld	bc, KERNEL_MM_PAGE_SIZE
	call	.phy_indirect_call
	pop	iy
	pop	af
	pop	bc
	jr	.write_buff_do
	
sysdef _ioctl
.ioctl:
; hl is fd, de is request
	call	.fd_pointer_check
	ret	c
; is the inode is a block or a character device ?
; README : the need to lock for read is dummy since we have already open this inode and the flags inode should NEVER change for TYPE
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE
	jr	z, .char_dev
	cp	a, KERNEL_VFS_TYPE_BLOCK_DEVICE
	ld	a, ENOTTY
	jp	nz, user_error
.char_dev:
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
	jp	z, user_error
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
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE
	jr	z, .error
	cp	a, KERNEL_VFS_TYPE_FIFO
.error:
	ld	a, ESPIPE
	jp	z, user_error
; so now, we have the offset de
	ld	a, c
	or	a, a
	jr	z, .lseek_set
	dec	a
	jr	z, .lseek_cur
	dec	a
	ld	a, EINVAL
	jp	nz, user_error
	ld	hl, (iy+KERNEL_VFS_INODE_SIZE)
	jr	.lseek_end
.lseek_cur:
	ld	hl, (ix+KERNEL_VFS_FILE_OFFSET)
.lseek_end:	
	add	hl, de
	ld	(ix+KERNEL_VFS_FILE_OFFSET), hl
	ret	nc
	ld	a, EOVERFLOW
	jp	user_error
.lseek_set:
	ld	(ix+KERNEL_VFS_FILE_OFFSET), de
	ex	de, hl
	or	a, a
	ret

sysdef _fstat
.fstat:
; int fstat(int fd, struct stat *statbuf);
; hl is fd, de is statbuf
	call	.fd_pointer_check
	ret	c
; read permission ?
	ld	a, EACCES
	bit	KERNEL_VFS_PERMISSION_R_BIT, (ix+KERNEL_VFS_FILE_FLAGS)
	jp	z, user_error
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
	cp	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE
	jr	z, .stat_device
	cp	a, KERNEL_VFS_TYPE_BLOCK_DEVICE
	jr	nz, .stat_no_device
.stat_device:
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
	ld	de, 1024
	ld	(ix+STAT_BLKSIZE), de
	ld	d, e
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
; int chroot(const char *path);
.chroot:
	call	.inode_get_lock
	ret	c
; iy is the inode
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_DIRECTORY
	jp	nz, .inode_atomic_write_error
; iy is valid
	ld	ix, (kthread_current)
	ld	(ix+KERNEL_THREAD_ROOT_DIRECTORY), ix
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	or	a, a
	sbc	hl, hl
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
	jr	z, .stat_continue
	jp	.inode_atomic_write_error

sysdef _chdir
.chdir:
;       int chdir(const char *path);
;       int fchdir(int fd);
	call	.inode_get_lock
	ret	c
.chdir_common:
; iy is the inode
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_DIRECTORY
	jp	nz, .inode_atomic_write_error
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
