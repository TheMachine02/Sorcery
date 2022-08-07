tmpfs:

.super:
	dl	.mount
	dl	.umount
	dl	.memops
	db	"tmpfs", 0

; jump table for physical operation
.memops:
	ret
	dl	$0
	ret
	dl	$0
	ret
	dl	$0
	ret
	dl	$0
	ret
	dl	$00
	ret		; phy_destroy_inode
	dl	$0
; exactly 4 bytes, convenient !
.statfs:
	ld	a, ENOSYS
	scf
.mount:
.umount:
	ret
