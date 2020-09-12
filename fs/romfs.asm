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


;   452 static __u32 romfs_checksum(const void *data, int size)
;   453 {
;   454     const __be32 *ptr = data;
;   455     __u32 sum;
;   456 
;   457     sum = 0;
;   458     size >>= 2;
;   459     while (size > 0) {
;   460         sum += be32_to_cpu(*ptr++);
;   461         size--;
;   462     }
;   463     return sum;
;   464 }
;   
;   
;   559 static struct dentry *romfs_mount(struct file_system_type *fs_type,
;   560             int flags, const char *dev_name,
;   561             void *data)
