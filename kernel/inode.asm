; inode handling ;
define	KERNEL_VFS_INODE			0
define	KERNEL_VFS_INODE_FLAGS			0	; 1 byte, inode flag
define	KERNEL_VFS_INODE_REFERENCE		1	; 1 byte, number of reference to this inode
define	KERNEL_VFS_INODE_SIZE			2	; 3 bytes, size of the inode
define	KERNEL_VFS_INODE_PARENT			5	; 3 bytes, parent of the inode, NULL mean root
define	KERNEL_VFS_INODE_ATOMIC_LOCK		8	; rw lock, 5 bytes
define	KERNEL_VFS_INODE_OP			13	; 3 bytes, memory operation pointer
define	KERNEL_VFS_INODE_DATA			16	; starting from 8, we arrive at data path (all block are indirect)
; 3*16, 48 bytes
; in case of fifo, hold the fifo structure (15 bytes)

define	KERNEL_VFS_DIRECTORY_ENTRY		0
define	KERNEL_VFS_DIRECTORY_INODE		0	; 3 bytes pointer to inode
define	KERNEL_VFS_DIRECTORY_NAME		3	; name, 

define	KERNEL_VFS_INODE_FILE_SIZE		16*16*KERNEL_MM_PAGE_SIZE	; maximum file size
define	KERNEL_VFS_INODE_NODE_SIZE		64	; size in byte of inode
define	KERNEL_VFS_DIRECTORY_ENTRY_SIZE		16	; 16 bytes per entries, or 4 entries per slab entries
define	KERNEL_VFS_DIRECTORY_NAME_SIZE		12	; max size of a name within directory

define	kvfs_root				$D003C0

; block device & char device operation ;
; files operations ;
define	phy_read		0
define	phy_write		4
define	phy_sync		8
define	phy_ioctl		8
define	phy_seek		12
; inode operation ;
define	phy_read_inode		16
define	phy_write_inode		20
define	phy_create_inode	24
define	phy_destroy_inode	28

; jump table for physical operation
.phy_none:
	ret		; phy_read (physical read from backing device)
	dl	$0
	ret		; phy_write (physical write to backing device)
	dl	$0
	ret		; phy_sync (physical sync file to backing device)
	dl	$0
	ret		; phy_seek (do a seek in file)
	dl	$0
	ret		; phy_read_inode (from backing device)
	dl	$0
	ret		; phy_write_inode (from backing device)
	dl	$00
	ret		; phy_create_inode
	dl	$00
	ret		; phy_destroy_inode

; about locking : you should always lock the PARENT first when you need to write both parent & inode to prevent deadlock
; inode searching can sleep with parent inode lock waiting for child inode to be free'd for read
; best is always locking only ONE inode
; return iy if found with ref+1 or the partial node iy with ref+1 and partial string hl

.inode_find:
; start at root inode, hl is path
	ld	iy, kvfs_root
	push	hl
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	pop	hl
	inc	hl	; skip first "/"
.inode_parse_directory:
	ld	a, (hl)
	or	a, a
; 	jr	z, .inode_get_found
	ld	a, '/'
	push	hl
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
; we also need to stop if we catch a NULL
	cpir
	jp	pe, .inode_get_continue
	pop	hl
	push	hl
; reload, but search 0
	xor	a, a
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
; we also need to stop if we catch a NULL
	cpir
	dec	hl
.inode_get_continue:
; push the new position of next name and restore previous name
	ex	(sp), hl
; check if inode is a directory (if not, error out)
	bit	KERNEL_VFS_TYPE_DIRECTORY_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	jr	z, .inode_get_unknown
; now, parse the directory to find we have a entry corresponding to it
; hl is our string, KERNEL_VFS_DIRECTORY_NAME_SIZE - 1 - bc is the size of it
	push	hl
	ld	hl, KERNEL_VFS_DIRECTORY_NAME_SIZE - 1
	or	a, a
	sbc	hl, bc
	push	hl
	pop	bc
	pop	hl
; bc is size, hl is string (not NULL terminated)
	push	iy
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	ld	a, 16
.inode_get_directory_loop:
; 15 times
	ld	ix, (iy+0)
; check if ix is NULL, else, skip
	push	hl
	lea	hl, ix+0
	add	hl, de
	or	a, a
	sbc	hl, de
	pop	hl
	jr	z, .inode_get_directory_skip
	push	af
	call	.inode_helper_compare_1st_time
	call	.inode_helper_compare
	call	.inode_helper_compare
	call	.inode_helper_compare
	pop	af
.inode_get_directory_skip:
	lea	iy, iy+3
	dec	a
	jr	nz, .inode_get_directory_loop
.inode_get_unknown:
	pop	iy
	ex	(sp), hl
	inc	(iy+KERNEL_VFS_INODE_REFERENCE)
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	pop	hl
	scf
	ret
.inode_get_directory_found:
	pop	bc
	ld	hl, 6
	add	hl, sp
	ld	sp, hl
	pop	af
; ix is the directory found, so use it as new parent inode
	ld	iy, (ix+KERNEL_VFS_DIRECTORY_INODE)
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
; now unlock the parent
	ex	(sp), iy
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	pop	iy
	pop	hl
	jp	.inode_parse_directory

.inode_helper_compare:
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
.inode_helper_compare_1st_time:
	lea	de, ix+KERNEL_VFS_DIRECTORY_NAME
	push	hl
	push	bc
.inode_helper_comp_loop:
	ld	a, (de)
	cpi
	jr	nz, .inode_helper_comp_restore
	jp	po, .inode_get_directory_found
	inc	de
	jr	.inode_helper_comp_loop
.inode_helper_comp_restore:
	pop	bc
	pop	hl
	ret
	
.inode_destroy:
; there is no more reference to this inode, so it can be freely destroyed
; we also need to free all child : TODO
; first signal the callback
	ld	ix, (iy+KERNEL_VFS_INODE_OP)
	lea	hl, ix+phy_destroy_inode
	call	.inode_call
	lea	hl, iy+KERNEL_VFS_INODE
	jp	kfree

.inode_call:
	jp	(hl)

.inode_atomic_error:
; unlock the inode (write locked) and error out
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	jp	syserror
	
.inode_create:
; hl is path, bc is mode, a is inode type
; return c and errno set if there is an issue
; else return iy = created inode with write lock held and hl = 0 nc
	ld	b, a
	push	bc
	call	.inode_find
	pop	de
; if inode_find carry we have an error already set by this function, but that *okay* (and even wanted)
	ld	a, EEXIST
	jp	nc, syserror
.inode_create_from_node:
; check the error is the correct one, ie ENOENT
	ld	ix, (kthread_current)
	ld	a, (ix+KERNEL_THREAD_ERRNO)
	cp	a, ENOENT
; if the error is different, return
	jr	nz, .inode_atomic_error
; hl is partial string, iy is the PARENT node
; we have several sanity check here
; check the inode can be writed
	bit	KERNEL_VFS_PERMISSION_W_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	a, EACCES
	jr	z, .inode_atomic_error
; right here, hl is the partial string and should be null terminated, does not contain '/'
	push	hl
	ld	a, '/'
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
	cpir
	pop	hl
	ld	a, ENOENT
	jr	z, .inode_atomic_error
; does the base name is not too long ?
	xor	a, a
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
	push	hl
	cpir
	pop	hl
	ld	a, ENAMETOOLONG
	jp	po, .inode_atomic_error
; now, we can allocate the inode & create the directory inode
; convention : hl is the name of the inode, iy is parent inode (it MUST be a directory), a is inode flags
	ld	a, e
	and	a, KERNEL_VFS_PERMISSION_RWX
	ld	e, a
	ld	a, d
	and	a, not KERNEL_VFS_PERMISSION_RWX
	or	a, e
; return iy = inode if not carry, if carry then it is an error and you should quit

.inode_allocate:
; hl is the name of the inode, iy is parent inode (directory), which should already be write locked++
; a is raw inode flags
; sanity check
	ld	c, a
	ld	a, ENOTDIR
	bit	KERNEL_VFS_TYPE_DIRECTORY_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	jr	z, .inode_atomic_error
; save name in register de
	ex	de, hl
; take the write lock on the parent inode to check if we can write a new inode in this directory
	push	iy
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	ld	b, 16
.inode_allocate_data:
	ld	ix, (iy+0)
; check if ix is NULL, else, skip
	lea	hl, ix+0
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_allocate_free_indirect
	ld	hl, (ix+KERNEL_VFS_DIRECTORY_INODE)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_allocate_free_direct
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	ld	hl, (ix+KERNEL_VFS_DIRECTORY_INODE)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_allocate_free_direct
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	ld	hl, (ix+KERNEL_VFS_DIRECTORY_INODE)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_allocate_free_direct
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	ld	hl, (ix+KERNEL_VFS_DIRECTORY_INODE)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_allocate_free_direct
	lea	iy, iy+3
	djnz	.inode_allocate_data
; well, no place found
; unlock and quit
	ld	a, ENOSPC
.inode_allocate_error:
	pop	iy
	jp	.inode_atomic_error
; upper data block was free, so allocate one
.inode_allocate_free_indirect:
	ld	hl, KERNEL_VFS_DIRECTORY_ENTRY_SIZE * 4
	call	kmalloc
	ld	a, ENOMEM
	jr	c, .inode_allocate_error
; iy is the directory entry, write the new entry made
	ld	(iy+0), hl
.inode_allocate_free_direct:
; ix is the directory entrie
	pop	iy
; iy is now the parent inode
	ld	hl, KERNEL_VFS_INODE_NODE_SIZE
	call	kmalloc
	ld	a, ENOMEM
	jp	c, .inode_atomic_error
; hl is our new little inode \o/
; copy everything in the dir entrie
	ld	(ix+KERNEL_VFS_DIRECTORY_INODE), hl
	push	hl
	push	bc
; now copy the name (still in de after all this time)
	lea	hl, ix+KERNEL_VFS_DIRECTORY_NAME
	ex	de, hl
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
.inode_allocate_copy_name:
	ld	a, (hl)
	or	a, a
	jr	z, .inode_allocate_copy_end
	ldi
	jp	pe, .inode_allocate_copy_name
.inode_allocate_copy_end:
	ld	(de), a
	pop	hl
	pop	bc
; c is still our flags, hl is our inode
; hl is our node inode
	push	hl
	pop	ix
; right here, we have the new inode as ix, the parent as iy, and name of inode as de
	inc	(ix+KERNEL_VFS_INODE_REFERENCE)
	ld	(ix+KERNEL_VFS_INODE_FLAGS), c
	ld	(ix+KERNEL_VFS_INODE_PARENT), iy
	lea	hl, ix+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.init
; hard take the write lock
; it is okay, since the inode is not yet inserted in the filesystem
	dec	(hl)
; copy parent methode inheriting filesystem and mount propriety
	ld	hl, (iy+KERNEL_VFS_INODE_OP)
	ld	(ix+KERNEL_VFS_INODE_OP), hl
; unlock parent inode
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
; children inode is still locked
; return the children node in iy
	push	ix
	pop	iy
	or	a, a
	sbc	hl, hl
	ret
	
.inode_dup:
	ret

.inode_symlink:
	ret
	
.inode_block_data:
; iy is inode number (adress of the inode)
; a is block number (ie, file adress divided by KERNEL_MM_PAGE_SIZE)
; about alignement : block are at last 1024 bytes aligned
; block data is aligned to 4 bytes
; inode data is 64 bytes aligned
; destroy a, bc, hl
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
	ret

.inode_drop_data:
; TODO : implement
; iy is inode number
; parse the data and unmap everything (+clear everything)
	ret
	
sysdef _rename
.inode_rename:
; int rename(const char *oldpath, const char *newpath);
; hl is old path, bc is newpath
; for this we need to find the file (grab inode and parent inode, lock the parent inode for write, remove reference for the file, introduce reference to the new path, etc). QUite some hard work actually
; 	push	bc
; 	call	.inode_find
; 	pop	hl
; ; well, we didn't found the first path, so abort
; 	ret	c
; 	push	iy
; 	call	.inode_find_directory
; 	pop	ix
; ; well, the path of the directory for the new name couldn't been found
; 	ret	c
; ; now lock both, and pray
; TODO : implement

	ret
	
	
	

