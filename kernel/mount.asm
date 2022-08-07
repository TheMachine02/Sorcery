.filesystem:
 dl	tifs.super
 dl	tmpfs.super

sysdef	_mount
.mount:
;       int mount(const char *source, const char *target,
;                 const char *filesystemtype, unsigned long mountflags,
;                 const void *data);
; using dev source, target folder target, with a char string describing filesystem, mountflags, and data passed to super mount routine from the fs (exemple, for tifs, we'll pass /dev/flash)
	ret

sysdef	_umount
.umount:
	ret
