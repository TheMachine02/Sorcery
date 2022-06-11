define	KERNEL_FLASH_MAPPING		$E00003
define	KERNEL_FLASH_CTRL		$E00005
define	KERNEL_FLASH_SIZE		$400000

flash:
.init:
	ld	hl, .phy_program
	ld	de, flash_program
	ld	bc, .phy_program_size
	ldir
	ld	hl, .FLASH_DEV
	ld	c, KERNEL_VFS_PERMISSION_RW or KERNEL_VFS_TYPE_BLOCK_DEVICE
	ld	de, .phy_mem_ops
	jp	_mknod

.FLASH_DEV:
 db "/dev/flash", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write
	jp	.phy_ioctl
; 	ret
; 	dl	0
; 	ret
; 	dl	0
; 	ret

.phy_program:

if $ < $D00000
	org	flash_program
end if

.phy_erase:
; erase sector hl
	call	.unlock
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
; timeout 50µs
	call	.phy_timeout
.phy_erase_loop:
	ld	de, (KERNEL_INTERRUPT_ISR)
	ld	a, d
	or	a, e
	call	nz, .phy_suspend
	ld	a, (hl)
	inc	a
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
	call	.lock
	ei
	halt
	di
; re unlock
	call	.unlock
	ld	a, $30
	ld	($0), a
	ret

.phy_timeout:
; wait a bit more than 50 µs
	push	bc			; 	  10
	ld	b, 181			; +	   8
.phy_timeout_wait:
	djnz	.phy_timeout_wait	; +	2348	(=180*13+1*8)
	pop	bc			; +  	  16
	ret				; +  	  21
					; =	2403 ... 2403/48Mhz=50,0625 µs
.phy_ioctl:
	ret
; no op
.phy_read:
	or	a, a
	sbc	hl, hl
	ret

.phy_write:
; write hl to flash de buffer for bc bytes
	call	.unlock
; we will write hl to de address
.phy_write_loop:
	ld	a, (de)
	and	a, (hl)
	push	hl
	ld	hl, $000AAA
	ld	(hl), l
	ld	hl, $000555
	ld	(hl), l
	add	hl, hl
	ld	(hl), $A0
; byte to program = A
	ld	(de), a
; now we need to check for the write to complete
; 6 micro second typical, ~300 cycles wait
	call	.phy_status_polling
; schedule if need for an interrupt
	ld	hl, (KERNEL_INTERRUPT_ISR)
	ld	a, h
	or	a, l
	jr	z, .phy_write_continue
; perform interrupt
; save all ?
	call	.lock
	ei
	halt
	di
; re unlock
	call	.unlock
.phy_write_continue:
	pop	hl
	inc	de
	cpi
	jp	pe, .phy_write_loop
	jp	.lock

.phy_status_polling:
	and	a, $80
	ld	h, a
.phy_busy_wait:
	ld	a, (de)
	xor	a, h
	add	a, a
	ret	nc
	jp	p, .phy_busy_wait
	ld	a, (de)
	xor	a, h
	rlca
	jr	nc, .phy_busy_wait
	
.phy_abort:
	ld	a, $F0
	ld	($0), a
	ret
	
.phy_program_size:=$-.phy_erase
org	.phy_program + .phy_program_size
