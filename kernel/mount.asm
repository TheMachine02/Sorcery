.filesystem:
 dl	tifs.super
 dl	tmpfs.super

.mount_root:
if CONFIG_MOUNT_ROOT_TIFS
; mount tifs & symlink it to binary, config_tifs
	call	tifs.mount_root
end if
	ret
.arch_dev_root:
 db	"/dev/flash", 0
.arch_root:
 db	"/", 0
.arch_filesystem:
 db	"tifs", 0
 
sysdef	_mount
.mount:
;       int mount(const char *source, const char *target,
;                 const char *filesystemtype, unsigned long mountflags,
;                 const void *data);
; using dev source, target folder target, with a char string describing filesystem, mountflags, and data passed to super mount routine from the fs (exemple, for tifs, we'll pass /dev/flash)
; mount the root filesystem.
	ret

sysdef	_umount
.umount:
	ret
