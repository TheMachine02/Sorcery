define	KERNEL_FLASH_MAPPING		$E00003
define	KERNEL_FLASH_CTRL		$E00005
define	KERNEL_FLASH_SIZE		$400000

flash:

.phy_init:
	ld	hl, .phy_mem_ops
	ld	bc, .FLASH_DEV
; inode capabilities flags
; single dev block, (so write / read / seek only), seek capabilities exposed
	ld	a, KERNEL_VFS_BLOCK_DEVICE or KERNEL_VFS_SEEK
	jp	kvfs.create_inode

.FLASH_DEV:
 db "/dev/flash", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write

.init:
; set flash wait state
	di
	rsmix
	ld	hl, KERNEL_FLASH_CTRL
	ld	(hl), $03
	ld	l, KERNEL_FLASH_MAPPING and $FF
	ld	(hl), $06

	ld	hl, .phy_write_base
	ld	de, $D18800
	ld	bc, 256
	ldir
	call	.phy_init

; lock it on init

; flash unlock and lock
.phy_lock:
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ret
	
.phy_unlock:
	in0	a, ($06)
	or	a, 4
	out0	($06), a
	ld	a, 4
	di 
	jr	$+2
	di
	rsmix 
	im 1
	out0	($28),a
	in0	a,($28)
	bit	2,a
	ret
 
.phy_read:
	ret

.phy_write_base:

org $D18800

.phy_erase:
; erase sector hl
	call	.phy_unlock
	ex	de, hl
; first cycle
	ld	hl, $000AAA
	ld	(hl), l
	ld	hl, $000555
	ld	(hl), l
	add	hl, hl
	ld	(hl), $80
; second cycle
	ld	(hl), l
	ld	hl, $000555
	ld	(hl), l
	ex	de, hl
	ld	(hl), $30
.phy_erase_loop:
	ld	de, (KERNEL_INTERRUPT_STATUS_MASKED)
	ld	a, d
	or	a, e
	call	nz, .phy_suspend
	ld	a, (hl)
	cp	a, $FF
	jr	nz, .phy_erase_loop	
	ret

.phy_suspend:
	ld	a, $B0
	ld	($0), a
; check for DQ6 toggle
.phy_suspend_busy_wait:
	bit	6, (hl)
	jr	z, .phy_suspend_busy_wait
; perform interrupt
	call	.phy_lock
	ei
	halt
	di
; re unlock
	call	.phy_unlock
	ld	a, $30
	ld	($0), a
	ret
	
.phy_write:
; write hl to flash for bc bytes
	call	.phy_unlock
; we will write hl to de address
.phy_write_loop:
	ld	a, (hl)
	push	hl
	ld	hl, $000AAA
	ld	(hl), l
	ld	hl, $000555
	ld	(hl), l
	add	hl, hl
	ld	(hl), $A0
	ex	de, hl
	and	a, (hl)
; byte to program = A
	ld	(hl), a
; now we need to check for the write to complete
; 6 micro second typical, ~300 cycles wait
	call	.phy_status_polling
; schedule if need for an interrupt
	ld	de, (KERNEL_INTERRUPT_STATUS_MASKED)
	ld	a, d
	or	a, e
	jr	z, .phy_write_continue
; perform interrupt
; save all ?
	call	.phy_lock
	ei
	halt
	di
; re unlock
	call	.phy_unlock
.phy_write_continue:
	ex	de, hl
	pop	hl
	inc	de
	cpi
	jp	pe, .phy_write_loop
	jp	.phy_lock

.phy_status_polling:
	and	a, $80
	ld	d, a
.phy_busy_wait:
	ld	a, (hl)
	xor	a, d
;	rlca
	add	a, a
	ret	nc
;	bit	6, a
;	jr	z, .phy_busy_wait
	jp	p, .phy_busy_wait
	ld	a, (hl)
	xor	a, d
	rlca
	jr	nc, .phy_busy_wait
	
.phy_abort:
	ld	a, $F0
	ld	($0), a
	ret
