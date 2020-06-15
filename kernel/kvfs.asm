define	KERNEL_VFS_PAGE_SIZE		1024
define	KERNEL_VSF_IENTRIES_PER_NODE	16		; 64 bytes node, 16 entries of 4 bytes
define	KERNEL_VFS_INODE_IDIRECT_MAX	6
define	KERNEL_VFS_MAX_INDEX		KERNEL_VFS_IDIRECT_SIZE + (KERNEL_VSF_IENTRIES_PER_NODE)*(KERNEL_VSF_IENTRIES_PER_NODE)+KERNEL_VSF_IENTRIES_PER_NODE


define	KERNEL_VFS_INODE			0
define	KERNEL_VFS_INODE_SIZE			56

define	KERNEL_VFS_INODE_FLAGS			0	; inode flag
define	KERNEL_VFS_INODE_REFERENCE		1	; number of reference to this inode (up to 256)
define	KERNEL_VFS_INODE_SIZE			2	; 3 bytes, size of the inode
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

define	kvfs_root_inode			$D00B00

kvfs:

.inode_page_entry:
; iy is node, hl is offset in file

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

