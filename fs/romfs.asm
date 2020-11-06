define	ROMFS_MAGIC		0	; 8 bytes magic, "-rom1fs-"
define	ROMFS_SIZE		8	; 4 bytes, full size of the filesystem
define	ROMFS_CHECKSUM		12	; 4 bytes, checksum of the first 512 bytes
define	ROMFS_VOLUME_NAME	16	; volume name, padded to 16 bytes, zero terminated

; file headers start at the end of the volume name (padded)

define	ROMFS_FILEHDR_NEXT	0	; offset of next file
define	ROMFS_FILEHDR_TYPE	0	; 4 lower bit
define	ROMFS_FILEHDR_INFO	4	; info for directories / hard link / devices
define	ROMFS_FILEHDR_SIZE	8	; (size of the file)
define	ROMFS_FILEHDR_CHECKSUM	12	; file checksum (including metadata and padding)
define	ROMFS_FILEHDR_NAME	16	; zero terminated, padded to 16 bytes

; type ; what is info

define	ROMFS_HARD_LINK		0	; info is link destination (file header)
define	ROMFS_DIRECTORY		1	; first file header
define	ROMFS_FILE		2	; 0
define	ROMFS_SYMBOLIC_LINK	3	; 0
define	ROMFS_BLOCK_DEVICE	4	; 16 bits major / minor number
define	ROMFS_CHAR_DEVICE	5	; 16 bits major / minor number
define	ROMFS_SOCKET		6	; 0
define	ROMFS_FIFO		7	; 0
   
;   559 static struct dentry *romfs_mount(struct file_system_type *fs_type,
;   560             int flags, const char *dev_name,
;   561             void *data)

romfs:

.IDENTIFIER:
 db	"-rom1fs-"

.compare:
	ld	a, (de)
	cpi
	ret	nz
	inc	de
	ret	po
	jr	.compare

.verify:
; z if it is, nz otherwise
; check if the given adress (ix) hold a ROMFS file system and if the checksum match
	lea	hl, ix+ROMFS_MAGIC
	ld	de, .IDENTIFIER
	ld	bc, 8
	call	.compare
	ret	nz
	ld	hl, 512
	ld	bc, (ix+ROMFS_SIZE)
	or	a, a
	sbc	hl, bc
	jr	nc, .smaller_fs
	ld	bc, 512
.smaller_fs:
	lea	hl, ix+ROMFS_MAGIC
	call	.checksum
; compare the checksum and the value stored
	ld	de, (ix+ROMFS_CHECKSUM)
	sub	a, (ix+ROMFS_CHECKSUM+3)
	sbc	hl, de
	ret
	
.checksum:
; ix is void*, bc is size
; add up 32 bits value in BIG ENDIAN
	srl	b
	rr	c
	srl	b
	rr	c
	ld	a, b
	or	a, c
	sbc	hl, hl
	ret	z
	ld	a, c
	dec	bc
	inc	b
	ld	c, b
	ld	b, a
	xor	a, a
.checksum_outer_loop:
	push	bc
.checksum_inner_loop:
; load ix + 1 in deu
	ld	de, (ix-1)
; then big endian ordering
	ld	c, d
	ld	d, (ix+2)
	ld	e, (ix+3)
; add up the 32 bits value
	add	hl, de
	adc	a, c
	lea	ix, ix+4
	djnz	.checksum_inner_loop
	pop	bc
	dec	c
	jr	nz, .checksum_outer_loop
; ahl is the 32 bits checksum
	ret

.mount:
; mount the file system at the given directory
; for exemple, in root /


