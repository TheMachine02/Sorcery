random:

.RAND_DEV:
 db "/dev/random", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write
	jp	.phy_ioctl
; 	ret
; 	dl	0
; 	ret
; 	dl	0
; 	ret
	
.phy_read:
; offset hl to de for bc size
; return hl = bc
	sbc	hl, hl
	adc	hl, bc
	ret

.phy_write:
	ld	a, ENOSYS
	jp	user_error
	
.phy_ioctl:
	ld	a, ENOTTY
	jp	user_error 
