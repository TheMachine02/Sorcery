define	KERNEL_FLASH_MAPPING		$E00003
define	KERNEL_FLASH_CTRL		$E00005
define	KERNEL_FLASH_SIZE		$400000

define	FLASH_MICROCODE_SIZE		256

flash:
.init:
	ld	hl, .microcode
	ld	de, flash_microcode
	ld	bc, FLASH_MICROCODE_SIZE
	ldir
	ld	hl, flash_atomic
	call	atomic_mutex.init
	ld	hl, .FLASH_DEV
	ld	c, KERNEL_VFS_PERMISSION_RW or KERNEL_VFS_TYPE_BLOCK_DEVICE
	ld	de, .phy_mem_ops
	jp	_mknod

.FLASH_DEV:
 db "/dev/flash", 0

.phy_mem_ops:
	jp	.read
	jp	.write
	jp	.ioctl
; 	ret
; 	dl	0
; 	ret
; 	dl	0
; 	ret

.ioctl:
	ret
; no op
.read:
	or	a, a
	sbc	hl, hl
	ret

.microcode:
 org	flash_microcode
 rb	KERNEL_ATOMIC_MUTEX_SIZE

.erase:
; erase sector hl
	push	hl
	ld	hl, flash_atomic
	call	atomic_mutex.lock
	pop	hl
	di
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
	ex	de, hl
; timeout 50µs
	call	.microcode_timeout
.microcode_erase_busy_wait:
	call	.microcode_irq_suspend
	ld	a, (de)
	inc	a
	jr	nz, .microcode_erase_busy_wait
	call	.lock
	ld	hl, flash_atomic
	jp	atomic_mutex.unlock

.write:
	push	bc
	push	de
	push	hl
	ld	hl, flash_atomic
	call	atomic_mutex.lock
	pop	hl
	pop	de
	pop	bc
; write hl to flash de buffer for bc bytes
	di
	call	.unlock
; we will write hl to de address
.microcode_write_buffer:
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
	call	.microcode_status_polling
; schedule if need for an interrupt
	call	.microcode_irq
	pop	hl
	inc	de
	cpi
	jp	pe, .microcode_write_buffer
	call	.lock
	push	de
	ld	hl, flash_atomic
	call	atomic_mutex.unlock
	pop	de
	ret

.microcode_status_polling:
	and	a, $80
	ld	h, a
.microcode_busy_wait:
	ld	a, (de)
	xor	a, h
	add	a, a
	ret	nc
	jp	p, .microcode_busy_wait
	ld	a, (de)
	xor	a, h
	rlca
	jr	nc, .microcode_busy_wait
	
.microcode_abort:
	ld	a, $F0
	ld	($0), a
; this is a fatal error, we had a flash failure
	ret

.microcode_timeout:
; wait a bit more than 50 µs
	push	bc			; 	  10
	ld	b, 181			; +	   8
.microcode_timeout_wait:
	djnz	.microcode_timeout_wait	; +	2348	(=180*13+1*8)
	pop	bc			; +  	  16
	ret				; +  	  21
					; =	2403 ... 2403/48Mhz=50,0625 µs		
	
.microcode_irq_suspend:
	ld	hl, (KERNEL_INTERRUPT_ISR)
	ld	a, h
	or	a, l
	ret	z
	ld	a, $B0
	ld	($0), a
; check for DQ6 toggle
.microcode_suspend_busy_wait:
	bit	6, (hl)
	jr	z, .microcode_suspend_busy_wait
; perform interrupt
	call	.lock
	call	.microcode_irq_halt
	ld	a, $30
	ld	($0), a
	ret

.microcode_irq:
	ld	hl, (KERNEL_INTERRUPT_ISR)
	ld	a, h
	or	a, l
	ret	z
; perform interrupt
; relock flash, keep mutex locked, halt to trigger rst 38h
; destroy a
	call	.lock
.microcode_irq_halt:
	ei
	halt
	di
	ld	hl, (KERNEL_INTERRUPT_ISR)
	ld	a, h
	or	a, l
	jr	nz, .microcode_irq_halt
	jp	.unlock
	
 align	256
 org	.microcode + FLASH_MICROCODE_SIZE
