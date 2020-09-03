; inode handling ;
define	KERNEL_VFS_INODE			0
define	KERNEL_VFS_INODE_FLAGS			0	; 1 byte, inode flag
define	KERNEL_VFS_INODE_REFERENCE		1	; 1 byte, number of reference to this inode
define	KERNEL_VFS_INODE_SIZE			2	; 3 bytes, size of the inode
define	KERNEL_VFS_INODE_PARENT			5	; 3 bytes, parent of the inode, NULL mean root
define	KERNEL_VFS_INODE_ATOMIC_LOCK		8	; rw lock, 8 bytes
define	KERNEL_VFS_INODE_DATA			16	; starting from 8, we arrive at data path (all block are indirect)
; 3*15, 45 bytes
define	KERNEL_VFS_INODE_OP			61

define	KERNEL_VFS_DIRECTORY_ENTRY		0
define	KERNEL_VFS_DIRECTORY_FLAGS		0	; flags
define	KERNEL_VFS_DIRECTORY_INODE		1	; 3 bytes pointer to inode
define	KERNEL_VFS_DIRECTORY_NAME		4	; name, 

define	KERNEL_VFS_INODE_FILE_SIZE		15*16*KERNEL_MM_PAGE_SIZE	; maximum file size
define	KERNEL_VFS_INODE_NODE_SIZE		64	; size in byte of inode
define	KERNEL_VFS_DIRECTORY_ENTRY_SIZE		16	; 16 bytes per entries, or 4 entries per slab entries
define	KERNEL_VFS_DIRECTORY_NAME_SIZE		12	; max size of a name within directory

define	kvfs_root				$D003C0

; files operations ;
define	phy_read		0
define	phy_write		4
define	phy_sync		8
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
	ret		; phy_sync (sync file)
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
	dl	$00
	
.inode_get_found:
; increment the reference
; we don't care if it is atomic or not, we are at least read locked
; decrementing this reference is always _write_ locked, so it is always exclusive
	inc	(iy+KERNEL_VFS_INODE_REFERENCE)
; unlock
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	or	a, a
	ret

; about locking : you should always lock the PARENT first when you need to write both parent & inode to prevent deadlock
; inode searching can sleep with parent inode lock waiting for child inode to be free'd for read
; best is always locking only ONE inode
; return iy if found with ref+1 or the partial node iy with ref+1 and partial string hl
.inode_find:
; start at root inode, hl is path
	ld	iy, kvfs_root
	push	hl
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
	pop	hl
	inc	hl	; skip first "/"
.inode_parse_directory:
	ld	a, (hl)
	or	a, a
	jr	z, .inode_get_found
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
.inode_get_continue:
; push the new position of next name and restore previous name
	ex	(sp), hl
; check if inode is a directory (if not, error out)
	bit	KERNEL_VFS_DIRECTORY, (iy+KERNEL_VFS_INODE_FLAGS)
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
	ld	a, 15
.inode_get_directory_loop:
	push	af
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
	lea	de, ix+KERNEL_VFS_DIRECTORY_NAME
	call	.inode_helper_compare
	jr	z, .inode_get_directory_found
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	lea	de, ix+KERNEL_VFS_DIRECTORY_NAME
	call	.inode_helper_compare
	jr	z, .inode_get_directory_found
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	lea	de, ix+KERNEL_VFS_DIRECTORY_NAME
	call	.inode_helper_compare
	jr	z, .inode_get_directory_found
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	lea	de, ix+KERNEL_VFS_DIRECTORY_NAME
	call	.inode_helper_compare
	jr	z, .inode_get_directory_found
.inode_get_directory_skip:
	lea	iy, iy+3
	pop	af
	dec	a
	jr	nz, .inode_get_directory_loop
.inode_get_unknown:
	pop	iy
	inc	(iy+KERNEL_VFS_INODE_REFERENCE)
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	pop	hl
	scf
	ret
.inode_get_directory_found:
; ix is the directory found, so use it as new parent inode
	ld	iy, (ix+KERNEL_VFS_DIRECTORY_INODE)
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
; now unlock the parent
	ex	(sp), iy
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_read
	pop	iy
	pop	hl
	jp	.inode_parse_directory

.inode_helper_compare:
	push	hl
	push	bc
.inode_helper_comp_loop:
	ld	a, (de)
	cpi
	jr	nz, .inode_helper_comp_restore
	jp	po, .inode_helper_comp_restore
	inc	de
	jr	.inode_helper_comp_loop
.inode_helper_comp_restore:
	pop	bc
	pop	hl
	ret

.inode_get:
; use read to be faster because the dec is in itself atomic
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_read
	inc	(iy+KERNEL_VFS_INODE_REFERENCE)
	jp	atomic_rw.unlock_read

.inode_put:
; iy is inode
; decrement reference, but doesn't clear lock
; note that testing the value should be atomic ++++
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	dec	(iy+KERNEL_VFS_INODE_REFERENCE)
	jr	z, .inode_destroy
	jp	atomic_rw.unlock_write
	
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

.inode_allocate_none:
	pop	af
	pop	hl
	scf
	ret
.inode_allocate_unpop:
	pop	af
	pop	hl
.inode_allocate:
; parent inode is iy (with ref+1) (it IS a directory), a is flag
; hl is the name of the inode
	push	hl
	push	af
	ld	hl, KERNEL_VFS_INODE_NODE_SIZE
	call	kmalloc
	jr	c, .inode_allocate_none
	pop	af
; hl is our node inode
	push	hl
	ex	de, hl
	or	a, a
	sbc	hl, hl
	add	hl, de
	inc	de
	ld	(hl), $FF
	ld	bc, KERNEL_VFS_INODE_NODE_SIZE - 1
	ldir
	pop	ix
	inc	(ix+KERNEL_VFS_INODE_REFERENCE)
	ld	(ix+KERNEL_VFS_INODE_FLAGS), a
	ld	(ix+KERNEL_VFS_INODE_PARENT), iy
	pop	de
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.lock_write
	ld	hl, (iy+KERNEL_VFS_INODE_OP)
	ld	(ix+KERNEL_VFS_INODE_OP), hl
; write the name (de) + flags + inode (ix)
	push	iy
	push	ix
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	ld	a, 15
.inode_directory_free:
	push	af
; 15 times
	ld	ix, (iy+0)
; check if ix is NULL, else, skip
	lea	hl, ix+0
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_directory_free_upper
	lea	hl, ix+KERNEL_VFS_DIRECTORY_NAME
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_directory_free_pointer
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	lea	hl, ix+KERNEL_VFS_DIRECTORY_NAME
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_directory_free_pointer
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	lea	hl, ix+KERNEL_VFS_DIRECTORY_NAME
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_directory_free_pointer
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	lea	hl, ix+KERNEL_VFS_DIRECTORY_NAME
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .inode_directory_free_pointer
	lea	iy, iy+3
	pop	af
	dec	a
	jr	nz, .inode_directory_free
.inode_directory_none_free:
	pop	hl	; this is our inode
	call	kfree
	pop	iy
; iput
	dec	(iy+KERNEL_VFS_INODE_REFERENCE)
	jp	z, .inode_destroy
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	scf
	ret
.inode_directory_free_upper:
	ld	hl, KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	call	kmalloc
	jr	c, .inode_directory_none_free
	ld	(ix+0), hl
	push	hl
	pop	ix
.inode_directory_free_pointer:
	pop	hl	; this is our inode
	push	hl
	ld	(ix+KERNEL_VFS_DIRECTORY_INODE), hl
	lea	hl, ix+KERNEL_VFS_DIRECTORY_NAME
	ex	de, hl
; copy hl > de
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE - 1
.inode_copy_name:
	ld	a, (hl)
	or	a, a
	jr	z, .inode_copy_end
	ldi
	jp	pe, .inode_copy_name
.inode_copy_end:
	ex	(sp), iy
; iput
	dec	(iy+KERNEL_VFS_INODE_REFERENCE)
	jp	z, .inode_destroy
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	pop	iy
	or	a, a
	ret

.inode_device:
; create a device
; hl path, a is flags, bc is mem op
; IT WILL CRASH SO ABORT TODO
	ret
	push	bc
	call	.inode_create
	pop	bc
	ret	c
	ld	(iy+KERNEL_VFS_INODE_OP), bc
	ret
	
.inode_create_error_exist:
; unlock the referenced parent
	pop	af
	call	.inode_put
	scf
	ret
.inode_create_alloc_error:
	pop	af
	pop	hl
	scf
	ret

.inode_create:
	push	af	; inode flags
	call	.inode_find
	jr	nc, .inode_create_error_exist	; already exist
; hl is partial string, iy is the PARENT node
; sanity check, does we have a directory on partial find ?
	bit	KERNEL_VFS_DIRECTORY, (iy+KERNEL_VFS_INODE_FLAGS)
	jr	z, .inode_create_error_exist
.inode_create_directory_chain:
; here, we have to : extract name
	ld	a, '/'
	push	hl
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
	cpir
	jp	pe, .inode_create_continue
	pop	hl
	push	hl
	xor	a, a
	ld	bc, KERNEL_VFS_DIRECTORY_NAME_SIZE
	cpir
.inode_create_continue:
	ld	a, (hl)
	or	a, a
; if zero, final inode AT LAST, else zero's the '/'
	jr	z, .inode_create_final
	dec	hl
	ld	(hl), $00
	ex	(sp), hl
	ld	a, KERNEL_VFS_DIRECTORY
	call	.inode_allocate
	jr	c, .inode_create_alloc_error
; iy is new parent, get the inode, aaaannnnnd loop back
	call	.inode_get
	pop	hl
	jr	.inode_create_directory_chain
.inode_create_final:
	pop	hl
	pop	af
	jp	.inode_allocate
	
.inode_dup:
	ret
