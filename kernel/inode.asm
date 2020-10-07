; inode handling ;
define	KERNEL_VFS_INODE			0
define	KERNEL_VFS_INODE_FLAGS			0	; 1 byte, inode flag
define	KERNEL_VFS_INODE_REFERENCE		1	; 1 byte, number of reference to this inode
define	KERNEL_VFS_INODE_SIZE			2	; 3 bytes, size of the inode
define	KERNEL_VFS_INODE_DEVICE			2	; 2 bytes, device number if applicable
define	KERNEL_VFS_INODE_PARENT			5	; 3 bytes, parent of the inode, NULL mean root
define	KERNEL_VFS_INODE_ATOMIC_LOCK		8	; rw lock, 5 bytes
define	KERNEL_VFS_INODE_OP			13	; 3 bytes, memory operation pointer
define	KERNEL_VFS_INODE_DATA			16	; starting from 8, we arrive at data path (all block are indirect)
; 3*16, 48 bytes
; in case of fifo, hold the fifo structure (15 bytes) (data block point to slab structure of 64 bytes with CACHE:BLOCK)

define	KERNEL_VFS_DIRECTORY_ENTRY		0
define	KERNEL_VFS_DIRECTORY_INODE		0	; 3 bytes pointer to inode
define	KERNEL_VFS_DIRECTORY_NAME		3	; name, 

define	KERNEL_VFS_INODE_FILE_SIZE		16*16*KERNEL_MM_PAGE_SIZE	; maximum file size
define	KERNEL_VFS_INODE_NODE_SIZE		64	; size in byte of inode
define	KERNEL_VFS_DIRECTORY_ENTRY_SIZE		16	; 16 bytes per entries, or 4 entries per slab entries
define	KERNEL_VFS_DIRECTORY_NAME_SIZE		12	; max size of a name within directory

; block device & char device operation ;
; files operations ;
define	phy_read		0
define	phy_write		4
define	phy_sync		8
define	phy_ioctl		8
; inode operation ;
define	phy_read_inode		12
define	phy_write_inode		16
define	phy_create_inode	18
define	phy_destroy_inode	22

; jump table for physical operation
.phy_none:
	ret		; phy_read (physical read from backing device)
	dl	$0
	ret		; phy_write (physical write to backing device)
	dl	$0
	ret		; phy_sync (physical sync file to backing device)
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

.inode_atomic_read_error:
	push	af
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	pop	af
	jp	syserror

.inode_atomic_write_error:
; unlock the inode (write locked) and error out
	push	af
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	pop	af
	jp	syserror
	
.inode_get_lock:
; hl is path
; return c = error, none lock
; return nc = iy is the locked for write inode
	ld	iy, kvfs_root
	inc	hl
; skip the first '/'
	ld	a, (hl)
	or	a, a
	jp	z, .inode_get_root_lock
	push	hl
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
	pop	hl
.inode_get_parse_path:
; find the entrie in the directory
	call	.inode_directory_lookup
	jp	c, .inode_atomic_read_error
; ix is the new inode, iy the old, hl is still our path
; ex : /dev/ need to lock dev for write
	ld	c, KERNEL_VFS_DIRECTORY_NAME_SIZE
.__bad_search3:
	ld	a, (hl)
	inc	hl
	or	a, a
	jr	z, .inode_get_lock_entry
	cp	a, '/'
	jr	z, .inode_get_continue
	dec	c
	jr	nz, .__bad_search3
	ld	a, ENAMETOOLONG
	jp	.inode_atomic_read_error
.inode_get_continue:
	ld	a, (hl)
	or	a, a
	jr	z, .inode_get_lock_entry
; we have the new path at hl
; lock dance
	push	hl
	lea	hl, ix+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	lea	iy, ix+0
	pop	hl
	jr	.inode_get_parse_path
.inode_get_lock_entry:
	lea	hl, ix+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	lea	iy, ix+0
	xor	a, a
	ret
.inode_get_root_lock:
	push	hl
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	xor	a, a
	pop	hl
	ret

	
.inode_directory_get_lock:
; Half - debuged
; /dev lock the correct directory
; /dev/fifo too
; need to check /dev/ and /dev/fifo/ + error path
; hl is path
; return c = error, none lock
; return nc = iy is the locked for write inode, hl is the name of the file
; logic is quite complex here
; exemple
; /dev/ lock / for write and give back dev//0
; /dev/hello lock /dev/ for write and give back hello/0
	ld	iy, kvfs_root
	inc	hl
; skip the first '/'
	ex	de, hl
	or	a, a
	sbc	hl, hl
	add	hl, de
	ld	a, (hl)
	or	a, a
; we will maintain hl = name actually looked up
; de = name AFTER the following '/'
	jp	z, .inode_directory_get_root_lock
	ld	c, KERNEL_VFS_DIRECTORY_NAME_SIZE
.__bad_search:
	ld	a, (hl)
	inc	hl
	or	a, a
	jr	z, .inode_directory_get_root_lock
	cp	a, '/'
	jr	z, .inode_directory_get_start
	dec	c
	jr	nz, .__bad_search
	ld	a, ENAMETOOLONG
	jp	syserror
.inode_directory_get_start:
	ld	a, (hl)
	or	a, a
	jr	z, .inode_directory_get_root_lock
	ex	de, hl
	push	hl
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
	pop	hl
.inode_directory_get_parse_path:
; find the entrie in the directory
	push	de
	call	.inode_directory_lookup
	pop	de
	jp	c, .inode_atomic_read_error
; ix is the new inode, iy the old, hl is still our path
; ex : /dev/ need to lock dev for write
; de > copy to hl
	or	a, a
	sbc	hl, hl
	add	hl, de
	ld	c, KERNEL_VFS_DIRECTORY_NAME_SIZE
.__bad_search2:
	ld	a, (hl)
	inc	hl
	or	a, a
	jr	z, .inode_directory_get_lock_entry
	cp	a, '/'
	jr	z, .inode_directory_continue
	dec	c
	jr	nz, .__bad_search2
	ld	a, ENAMETOOLONG
	jp	.inode_atomic_read_error
.inode_directory_continue:
	ld	a, (hl)
	or	a, a
	jr	z, .inode_directory_get_lock_entry
	ex	de, hl
; we have the new path at de
; lock dance
	push	hl
	lea	hl, ix+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	lea	iy, ix+0
	pop	hl
	jr	.inode_directory_get_parse_path
.inode_directory_get_lock_entry:
	ex	de, hl
	push	hl
	lea	hl, ix+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	pop	hl
	lea	iy, ix+0
	xor	a, a
	ret
.inode_directory_get_root_lock:
	ex	de, hl
	push	hl
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	xor	a, a
	pop	hl
	ret

.inode_directory_lookup:
; return c if error with a = error (but NO ERRNO SET)
; return nc if found, ix is the inode lookup
; also can check partial path ('dev/toto' lookup dev)
	bit	KERNEL_VFS_TYPE_DIRECTORY_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	a, ENOTDIR
	scf
	ret	z
; does we have at least read authorization of this folder ?
	bit	KERNEL_VFS_PERMISSION_R_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	a, EACCES
	ret	z
	push	iy
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	ld	b, 16
.inode_directory_lookup_data:
; 16 times
	ld	ix, (iy+0)
; check if ix is NULL, else, skip
	push	hl
	lea	hl, ix+0
	add	hl, de
	or	a, a
	sbc	hl, de
	pop	hl
	jr	z, .inode_directory_data_null
	call	.inode_directory_entry_cmp
	jr	z, .inode_directory_lookup_match
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	call	.inode_directory_entry_cmp
	jr	z, .inode_directory_lookup_match
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	call	.inode_directory_entry_cmp
	jr	z, .inode_directory_lookup_match
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	call	.inode_directory_entry_cmp
	jr	z, .inode_directory_lookup_match
.inode_directory_data_null:
	lea	iy, iy+3
	djnz	.inode_directory_lookup_data
	pop	iy
	ld	a, ENOENT
	scf
	ret
.inode_directory_lookup_match:
	pop	iy
	ld	ix, (ix+KERNEL_VFS_DIRECTORY_INODE)
	xor	a, a
	ret

.inode_directory_entry_cmp:
	lea	de, ix+KERNEL_VFS_DIRECTORY_NAME
	push	hl
	push	bc
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
.inode_directory_entry_loop:
	ld	a, (hl)
	or	a, a
	jr	z, .inode_directory_entry_last
	sub	a, '/'
	jr	z, .inode_directory_entry_last
	ld	a, (de)
	cpi
	jr	nz, .inode_directory_entry_return
	inc	de
	jp	pe, .inode_directory_entry_loop
; entry are the same
.inode_directory_entry_return:
; z flags set
	pop	bc
	pop	hl
	ret
.inode_directory_entry_last:
; check 0 against (de)
	ex	de, hl
	cp	a, (hl)
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
	
.inode_create:
; hl is path, bc is mode, a is inode type
; return c and errno set if there is an issue
; else return iy = created inode with write lock held and hl = 0 nc
	ld	b, a
	push	bc
	call	.inode_directory_get_lock
	pop	de
	ret	c
; we have several sanity check here
	push	de
	push	hl
	call	.inode_directory_lookup
	pop	hl
	pop	de
	ld	a, EEXIST
	jp	nc, .inode_atomic_write_error
.inode_create_parent:
; hl is name, iy is the PARENT node, d is inode type, e is mode
; check the inode can be writed
	bit	KERNEL_VFS_PERMISSION_W_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	a, EACCES
	jp	z, .inode_atomic_write_error
; right here, hl is the partial string and should be null terminated
; does the base name is not too long ?
	xor	a, a
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
	push	hl
	cpir
	pop	hl
	ld	a, ENAMETOOLONG
	jp	po, .inode_atomic_write_error
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
	jp	z, .inode_atomic_write_error
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
	jp	.inode_atomic_write_error
; upper data block was free, so allocate one
.inode_allocate_free_indirect:
	ld	hl, KERNEL_VFS_DIRECTORY_ENTRY_SIZE * 4
	call	kmalloc
	ld	a, ENOMEM
	jr	c, .inode_allocate_error
; iy is the directory entry, write the new entry made
	ld	(iy+0), hl
; copy result to ix
	push	hl
	pop	ix
.inode_allocate_free_direct:
; ix is the directory entrie
	pop	iy
; iy is now the parent inode
	ld	hl, KERNEL_VFS_INODE_NODE_SIZE
	call	kmalloc
	ld	a, ENOMEM
	jp	c, .inode_atomic_write_error
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
; do not copy trailing '/'
	ld	a, (hl)
	or	a, a
	jr	z, .inode_allocate_copy_end
	sub	a, '/'
	jr	z, .inode_allocate_copy_end
	ldi
	jp	pe, .inode_allocate_copy_name
.inode_allocate_copy_end:
	ld	(de), a
	pop	bc
	pop	hl
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
; destroy a, hl
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
	pop	bc
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
	
	
	

