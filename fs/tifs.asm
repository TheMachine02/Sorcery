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

.path:
 db "/tifs/", 0

.mount:
	ld	hl, 16
	call	kmalloc
	ret	c
; this will be our temporary buffer for path
	push	hl
	pop	iy
	ex	de, hl
	ld	hl, .path
	ld	bc, 6
	ldir
	ld	hl, .path
	ld	bc, KERNEL_VFS_PERMISSION_RWX
	push	iy
	call	kvfs.mkdir
	pop	iy
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
	cp	a, TIFS_FILE_DELETED
	jr	z, .mount_skip_file
	cp	a, TIFS_FILE_VALID
	jr	z, .mount_add_file
.mount_parse_sector_continue:
	pop	hl
.mount_invalid_sector:
	ld	bc, 65536
	add	hl, bc
	ld	h, b
	ld	l, c
	pop	bc
	djnz	.mount_parse
	ret
	
.mount_skip_file:
	inc	hl
	ld	bc, 0
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	jr	.mount_parse_sector
.mount_add_file:
	inc	hl
	ld	bc, 0
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
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
	cp	a, TIFS_TYPE_APPV
	jr	z, .mount_appv
	cp	a, TIFS_TYPE_EXE
	jr	z, .mount_exec
	cp	a, TIFS_TYPE_PROT_EXE
	jr	z, .mount_exec
; unknown file type for now
	jr	.mount_strange_file
.mount_create_inode:
	push	hl
	lea	hl, iy+0
	ld	a, KERNEL_VFS_TYPE_FILE
	push	iy
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
	call	atomic_rw.unlock_write
	pop	iy
	pop	hl
	jp	.mount_parse_sector
.mount_strange_file:
	pop	hl
	jp	.mount_parse_sector
.mount_error_file:
	pop	hl
	pop	hl
	pop	bc
	ret
	
.mount_appv:
	ld	bc, 0
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	push	bc
; RO fs for now
	ld	bc, KERNEL_VFS_PERMISSION_R
	jr	.mount_create_inode
.mount_exec:
	ld	bc, 0
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	dec	bc
	dec	bc
	push	bc
; EF7B
	inc	hl
	inc	hl
	ld	bc, KERNEL_VFS_PERMISSION_RX
	jr	.mount_create_inode
	
.mount_data:
; hl is size of file, de is disk adress, iy is inode
	lea	iy, iy+KERNEL_VFS_INODE_DATA
	ld	bc, 1024
.do_data:
	push	hl
	ld	hl, 64
	call	kmalloc
	push	hl
	pop	ix
	ld	(iy+0), ix
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
