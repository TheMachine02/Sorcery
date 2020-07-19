define	KERNEL_VFS_PAGE_SIZE		1024
define	KERNEL_VSF_INODE_INDIRECT_MAX	14		; 56 bytes node, 14 entries of 4 bytes
define	KERNEL_VFS_INODE_DIRECT_MAX	6
define	KERNEL_VFS_MAX_INDEX		KERNEL_VFS_IDIRECT_SIZE + (KERNEL_VSF_IENTRIES_PER_NODE)*(KERNEL_VSF_IENTRIES_PER_NODE)+KERNEL_VSF_IENTRIES_PER_NODE


define	KERNEL_VFS_INODE			0
define	KERNEL_VFS_INODE_SIZE			56

define	KERNEL_VFS_INODE_FLAGS			0	; inode flag
define	KERNEL_VFS_INODE_REFERENCE		1	; number of reference to this inode (up to 256)
define	KERNEL_VFS_INODE_DATA_SIZE		2	; 3 bytes, size of the inode
define	KERNEL_VFS_INODE_PARENT			5	; parent of the inode, NULL mean root
; data block ;
define	KERNEL_VFS_INODE_DATA_DIRECT		8
; 8 direct data block, 32 bytes : block_device_adress : page_cache
define	KERNEL_VFS_INODE_DATA_SDIRECT		40
define	KERNEL_VFS_INODE_DATA_DDIRECT		44
define	KERNEL_VFS_INODE_OP			53

define	KERNEL_VFS_DIRECTORY_ENTRY		0
define	KERNEL_VFS_DIRECTORY_ENTRY_SIZE		14	; 4 entries for 56 bytes in total > or 64 bytes for the slab entry

define	KERNEL_VFS_DIRECTORY_FLAGS		0
define	KERNEL_VFS_DIRECTORY_INODE		1
define	KERNEL_VFS_DIRECTORY_NAME		4

; type (4 first bit)
define	KERNEL_VFS_BLOCK_DEVICE			1
define	KERNEL_VFS_FILE				2
define	KERNEL_VFS_DIRECTORY			4
define	KERNEL_VFS_SYMLINK			8
; capabilities
define	KERNEL_VFS_SEEK				16



; for directories :
; also allocate data block, 64 bytes 4 directories per node > 2 byte flags, > 3 bytes inode > 10 bytes names + NULL >


;	typedef struct _iofile
;	{
;		char*  _read;		; current reading pointer
;		int    _roffset		; reading offset within the file
;		char*  _write;		; current writing pointer
;		int    _woffset;	; current inode index for block data
;		int    _flag;		; opened flags
;		int    _fd;		; file descriptor
;	} FILE;

define	kvfs_root_inode			$D001C0

kvfs:

.inode_page_entry:
; iy is node, hl is offset in file
; interrupt disabled please
; please note that we need to allocate the entry if not allocated
; (ie max two slab alloc)
	dec	sp
	push	hl
	inc	sp
	ex	(sp), hl
	pop	bc
	srl	h
	rr	l
	srl	h
	rr	l
	ex	de, hl
	xor	a, a
	sbc	hl, hl
	ld	h, d
	ld	l, e
	ld	bc, KERNEL_VFS_INODE_DIRECT_MAX
	sbc	hl, bc
	jr	c, .inode_direct
	ld	c, KERNEL_VSF_INODE_INDIRECT_MAX and $FF
	sbc	hl, bc
	jr	c, .inode_indirect_single
.inode_indirect_double:
; divide by KERNEL_VSF_INODE_INDIRECT_MAX and get the modulo KERNEL_VSF_INODE_INDIRECT_MAX
; two indirection then the adress
	ld	bc, KERNEL_VSF_INODE_INDIRECT_MAX
	ex	de, hl
	call	div
; de = mod, hl = result bc = untouched
	push	de
	add	hl, hl
	add	hl, hl
	or	a, (iy+KERNEL_VFS_INODE_DATA_DDIRECT+2)
	jr	nz, .inode_double_indirect_first
	push	hl
	push	iy
	ld	hl, 56
	call	kslab.malloc
	pop	iy
	ld	(iy+KERNEL_VFS_INODE_DATA_DDIRECT), hl
	pop	hl
.inode_double_indirect_first:
	ld	bc, (iy+KERNEL_VFS_INODE_DATA_DDIRECT)
	add	hl, bc
; check the data on the first indirect page
	inc	hl
	inc	hl
	ld	a, (hl)
	dec	hl
	dec	hl
	or	a, a
	jr	nz, .inode_double_indirect_second
	push	iy
	push	hl
	ld	hl, 56
	call	kslab.malloc
	pop	de
	ex	de, hl
	ld	(hl), de
	pop	iy
.inode_double_indirect_second:
	ld	de, (hl)
	pop	hl
	add	hl, hl
	add	hl, hl
	add	hl, de
	ret
.inode_direct:
	add	hl, bc
	add	hl, hl
	add	hl, hl
	lea	bc, iy+KERNEL_VFS_INODE_DATA_DIRECT
	add	hl, bc
	ret
.inode_indirect_single:
	add	hl, bc
	add	hl, hl
	add	hl, hl
	or	a, (iy+KERNEL_VFS_INODE_DATA_SDIRECT+2)
	jr	nz, .inode_indirect_find_index
	push	hl
	push	iy
	ld	hl, 56
	call	kslab.malloc
	pop	iy
	ld	(iy+KERNEL_VFS_INODE_DATA_SDIRECT), hl
	pop	hl
.inode_indirect_find_index:
	ld	bc, (iy+KERNEL_VFS_INODE_DATA_SDIRECT)
	add	hl, bc
	ret

.find_inode:
; bc is path "/xxxxx/xxxxxx/file.x", 0 or "/xxxx/xxxx", 0 for a directory
	ld	iy, kvfs_root_inode

.find_loop:
; extract next name : is next name is null, then return current iy node
; else
; lock the inode, try to find the path in the inode data (if inode is directory)
	ret

.create_inode:
	ret
	
.destroy_inode:
	ret

.mkdir:
	ret
	
.rmdir:
	ret	

.open:
	call	.find_inode
	ret	c

	ret

.close:
	ret	
	
.read:
;;size_t read(FILE* file, void *buf, size_t count);
; iy is file, void *buf is de, size_t count is bc
; pad count to inode_file_size
	ret
	
.write:
	ret

