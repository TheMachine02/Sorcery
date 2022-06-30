define	TIFS_SECTOR_FLAG		$F0
define	TIFS_FREE_FLAG			$FF
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

define	TIFS_WRITE_OFFSET_SIZE		19
define	TIFS_WRITE_HEADER_SIZE		22

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
	jp	.phy_stat

.phy_stat:
	ld	a, ENOSYS
	scf
	ret

.phy_read:
	ldir
	ret
	
.phy_sync:
; tifs work by finding a free spot somewhere and write the file here (also droping the previous file)
; if all spot are filed, garbage collect and retry (kinda inefficient indeed)
; doesn't sync all special file (dev, char, fifo, symlink etc since it is unsupported in this fs)
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_FILE
	ld	a, EIO
	ret	nz
	ld	a, (iy+KERNEL_VFS_INODE_SIZE)
	or	a, a
	ld	a, ENOMEM
	ret	nz
; goes each page and search for an empty spot
	ld	b, TIFS_SECTOR_COUNT
	ld	hl, TIFS_SECTOR_BASE
.__phy_sync_parse:
	push	bc
; create an inode for each file found and fill it
	ld	a, (hl)
	cp	a, TIFS_FREE_FLAG
; whole sector is free, write there
	jr	z, .__phy_sync_valid
	cp	a, TIFS_SECTOR_FLAG
	jr	nz, .__phy_sync_invalid_sector
	inc	hl
	push	hl
.__phy_sync_parse_sector:
	ld	a, (hl)
	inc	hl
	inc.s	bc
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	cp	a, TIFS_FREE_FLAG
	jr	nz, .phy_sync_parse_continue
; check for space
	push	hl
	ld	de, (iy+KERNEL_VFS_INODE_SIZE)
	or	a, a
	sbc.s	hl, de
	ld	de, TIFS_WRITE_HEADER_SIZE
	or	a, a
	sbc.s	hl, de
	pop	hl
	jp	p, .__phy_sync_valid
	jr	.__phy_sync_invalid_sector
.phy_sync_parse_continue:
	add	hl, bc
	cp	a, TIFS_FILE_DELETED
	jr	z, .__phy_sync_parse_sector
	cp	a, TIFS_FILE_VALID
	jr	z, .__phy_sync_parse_sector
	pop	hl
.__phy_sync_invalid_sector:
	ld	bc, 65536
	add	hl, bc
	ld	h, b
	ld	l, c
	pop	bc
	djnz	.__phy_sync_parse
	ret
.__phy_sync_valid:
; actually write the file to flash
	push	hl
; hl is the valid adress
	ld	hl, kmem_cache_s32
	call	kmem.cache_alloc
	ret	c
	push	hl
	pop	ix
; write in hl all good stuff, and write it to flash
	ld	(ix+TIFS_FILE_FLAG), TIFS_FILE_VALID
	ld	hl, (iy+KERNEL_VFS_INODE_SIZE)
	ld	bc, TIFS_WRITE_OFFSET_SIZE
	add	hl, bc
	ld	(ix+TIFS_FILE_SIZE), hl
	ld	a, TIFS_TYPE_APPV
	bit	KERNEL_VFS_PERMISSION_X_BIT, (iy+KERNEL_VFS_INODE_FLAGS)
	jr	z, $+4
	ld	a, TIFS_TYPE_PROT_EXE
	ld	(ix+TIFS_FILE_TYPE), a
	ld	(ix+TIFS_FILE_ATTRIBUTE), a
	ld	(ix+TIFS_FILE_VERSION), a
; adress = de + TIFS_WRITE_HEADER_SIZE
	pop	hl
	push	hl
	ld	bc, TIFS_WRITE_HEADER_SIZE
	add	hl, bc
	ld	(ix+TIFS_FILE_ADRESS), hl
	ld	(ix+TIFS_FILE_NAME_SIZE), 12
	ld	(ix+TIFS_FILE_NAME), 'A'
	ld	(ix+TIFS_FILE_NAME), '0'
	pop	de
	ld	bc, TIFS_WRITE_HEADER_SIZE
	call	flash.phy_write
; now, write data \o/
	push	de
	lea	hl, ix+0
	call	kfree
	pop	de
; TODO : write data and mark page of the inode as 'non dirty'
; get approx size for knowing how much we loop (lot of special case to handle...)
	ld	ix, (iy+KERNEL_VFS_INODE_DATA)
	ld	b, 4
.__phy_sync_mark_page:
	ld	hl, (ix+0)
	add	hl, de
	or	a, a
	sbc	hl, de
; if zero, we write NULL data equivalent
	jr	nz, .__phy_sync_process_indirect
; 16 blocks, so write 16384 NULL bytes
	ld	hl, KERNEL_MM_NULL
	ld	bc, KERNEL_MM_PAGE_SIZE * 16
	call	flash.phy_write
	djnz	.__phy_sync_mark_page
	ret
.__phy_sync_process_indirect:


	ret

.phy_destroy:
; marking the variable as removed in flash
; iy = inode
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_FILE
	ret	nz
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

.path_home:
 db "/home/", 0
.path_bin:
 db "/bin/", 0
.path_lib:
 db "/lib/", 0

; TODO : in the futur, detect if the path where tifs is mounted is root and if so, hard link bin and lib 
; and generate tifs path (because all stuff in root is nasty)

.mount_root:
; mount the tifs as root
	call	.mount
; 	ld	hl, .path_bin
; 	ld	bc, KERNEL_VFS_PERMISSION_RW
; 	call	kvfs.mkdir
; 	ld	hl, .path_lib
; 	ld	bc, KERNEL_VFS_PERMISSION_RW
; 	call	kvfs.mkdir
	ld	hl, .path_home
	ld	de, .path_bin
	call	kvfs.link
	ld	hl, .path_home
	ld	de, .path_lib
	jp	kvfs.link
 
.mount:
	ld	hl, kmem_cache_s32
	call	kmem.cache_alloc
	ret	c
; this will be our temporary buffer for path
	ex	de, hl
	ld	iy, 0
	lea	bc, iy+6
	add	iy, de
	push	de
	ld	hl, .path_home
	ldir
	ld	hl, .path_home
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
	call	kfree
	ld	hl, .tifs_root_message
	jp	printk

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
	dec	bc
	dec	bc
	push	bc
	inc	hl
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

.tifs_root_message:
 db	"tifs: root partition found", 10, 0

