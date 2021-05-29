define	TIFS_SECTOR_FLAG		$F0
define	TIFS_SECTOR_BASE		$0C0000
define	TIFS_SECTOR_COUNT		$34
; valid 0FCh
; valid 0FFh
; valid 0F0h
define	TIFS_FILE_VALID			$FC
define	TIFS_FILE_DELETED		$F0
define	TIFS_FILE_CORRUPTED		$FE
 
define	TIFS_FILE_FLAG			0
define	TIFS_FILE_SIZE			1	; doesnt take in count the small offset, so base size off the next adress of this field
define	TIFS_FILE_TYPE			3
define	TIFS_FILE_ATTRIBUTE		4
define	TIFS_FILE_VERSION		5
define	TIFS_FILE_ADRESS		6
define	TIFS_FILE_NAME_SIZE		9
define	TIFS_FILE_NAME			10

define	TIFS_TYPE_GDB			1
define	TIFS_TYPE_STRING		4
define	TIFS_TYPE_EXE			5
define	TIFS_TYPE_PROT_EXE		6
define	TIFS_TYPE_PICTURE		7
define	TIFS_TYPE_APPV			21
define	TIFS_TYPE_GROUP			23
define	TIFS_TYPE_IMAGE			26

tifs:

.phy_mem_ops:
	jp	.phy_read
	ret
	dl	$0
	jp	.phy_sync
	ret		; phy_read_inode (from backing device) ; not supported
	dl	$0
	ret		; phy_sync_inode ; not supported (no inode data written)
	dl	$00
	jp	.phy_destroy

.phy_read:
	ldir
	ret
	
.phy_sync:
; tifs work by finding a free spot somewhere and write the file here (also droping the previous file)
; if all spot are filed, garbage collect and retry (kinda inefficient indeed)
	ret

.phy_destroy:
; marking the variable as removed in flash
; iy = inode
; reading the first value of the first block is okay since tifs write file in-order
	ld	ix, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	ix, (ix+KERNEL_VFS_INODE_DMA_POINTER)
; hl is pointer to flash memory
; back search the begin of the variable
	lea	hl, ix-3
	lea	de, ix-9
.field_search:
; search the TIFS_FILE_ADRESS field by checking if de = bc
	ld	bc, (hl)
	ex	de, hl
	or	a, a
	sbc	hl, bc
	add	hl, bc
	dec	hl
	dec	de
	jr	nz, .field_search
; hl is the TIFS_FILE_ADRESS, bc is the base adress
; so write $F0 to bc adress with flash routine
	ld	de, .delete_byte
	or	a, a
	sbc	hl, hl
	add	hl, bc
	ex	de, hl
	ld	bc, 1
	jp	flash.phy_write

.delete_byte:
 db	$F0

.path:
 db "/tifs/", 0

.mount:
	ld	hl, kmem_cache_s16
	call	kmem.cache_alloc
	ret	c
; this will be our temporary buffer for path
	ex	de, hl
	ld	iy, 0
	lea	bc, iy+6
	add	iy, de
	push	de
	ld	hl, .path
	ldir
	ld	hl, .path
	ld	c, KERNEL_VFS_PERMISSION_RWX
	call	kvfs.mkdir
	pop	iy
	ret	c
; goes each page and search
	ld	b, TIFS_SECTOR_COUNT
	ld	hl, TIFS_SECTOR_BASE
.mount_parse:
	push	bc
; create an inode for each file found and fill it
	ld	a, (hl)
	cp	a, TIFS_SECTOR_FLAG
	jr	nz, .mount_invalid_sector
	inc	hl
	push	hl
.mount_parse_sector:
	ld	a, (hl)
; unexpected value, quit current sector
	inc	hl
	inc.s	bc
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	cp	a, TIFS_FILE_VALID
	jr	z, .mount_add_file
; mount_skip_file	
	add	hl, bc
	cp	a, TIFS_FILE_DELETED
	jr	z, .mount_parse_sector
	pop	hl
.mount_invalid_sector:
	ld	bc, 65536
	add	hl, bc
	ld	h, b
	ld	l, c
	pop	bc
	djnz	.mount_parse
	lea	hl, iy+0
	jp	kfree

.mount_add_file:
	push	hl
	add	hl, bc
	ex	(sp), hl
	ld	a, (hl)		; file type
	ld	bc, 6
	add	hl, bc
; goes directly to NAME
	ld	c, (hl)
; size name
	inc	c
	dec	c
	jr	z, .mount_strange_file
; copy file name to our temporary buffer
	lea	de, iy+6
	inc	hl
	ldir
; blit a zero to be a null terminated string \*/
	ex	de, hl
	ld	(hl), c
	ex	de, hl
; iy is our file name, let's create inode
; a = file type, hl = data
; offset based on the type ?
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	cp	a, TIFS_TYPE_APPV
	jr	z, .mount_appv
	cp	a, TIFS_TYPE_EXE
	jr	z, .mount_exec
	cp	a, TIFS_TYPE_PROT_EXE
; unknown file type for now
	jr	nz, .mount_strange_file
.mount_exec:
	inc	hl
	dec.s	bc
	dec	bc
	push	bc
; skip $EF7B identifier of 8xp exectuable
	inc	hl
	ld	bc, KERNEL_VFS_PERMISSION_RX
.mount_create_inode:
	inc	hl
	push	hl
	lea	hl, iy+0
	ld	a, KERNEL_VFS_TYPE_FILE or KERNEL_VFS_CAPABILITY_DMA
	push	hl
	call	kvfs.inode_create
	pop	ix
	pop	de
	pop	hl
	jr	c, .mount_error_file
	push	ix
; fill in the inode
; size is hl, start of data is de
; allocate indirect block and fill them with data
	ld	(iy+KERNEL_VFS_INODE_SIZE), hl
	ld	bc, .phy_mem_ops
	ld	(iy+KERNEL_VFS_INODE_OP), bc
	pea	iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	.mount_data
	pop	hl
; and let go of the lock
; 	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	pop	iy
.mount_strange_file:
	pop	hl
	jp	.mount_parse_sector
.mount_error_file:
	pop	hl
	pop	hl
	pop	bc
	ret
	
.mount_appv:
	push	bc
; RO fs for now
	ld	bc, KERNEL_VFS_PERMISSION_R
	jr	.mount_create_inode
	
.mount_data:
; hl is size of file, de is disk adress, iy is inode
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	ld	bc, 1024
.do_data:
	push	hl
	ld	hl, kmem_cache_s64
	call	kmem.cache_alloc
	ld	(iy+0), hl
	ld	ix, (iy+0)
	lea	iy, iy+3
	pop	hl
	ld	a, 16
.do_data_inner:
	ld	(ix+1), de
	lea	ix, ix+4
	ex	de, hl
	add	hl, bc
	ex	de, hl
	sbc	hl, bc
	ret	c
	dec	a
	jr	nz, .do_data_inner
	jr	.do_data
