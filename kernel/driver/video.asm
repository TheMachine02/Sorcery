define	DRIVER_VIDEO_VRAM		$D40000
define	DRIVER_VIDEO_VRAM_SIZE		$25800
define	DRIVER_VIDEO_FRAMEBUFFER_SIZE	$12C00
define	DRIVER_VIDEO_CTRL		$E30018
define	DRIVER_VIDEO_CTRL_DEFAULT	10000100100100111b	; generate interrupt at vcomp & watermark enable & pwr & BGR & 8bpp & EN
define	DRIVER_VIDEO_IMSC		$E3001C
define	DRIVER_VIDEO_IMSC_DEFAULT	000001000b	; vcomp interrupt
; 31---------------------------------------------------------0
; UNDEFINED                   MBERROR Vcomp LNBU FUF UNDEFINED
; 000000000000000000000000000 0       0     0    0   0
; MBERROR = AHB master error
; Vcomp   = Vertical compare
; LNBU    = LCD next base address update
; FUF     = FIFO underflow
define	DRIVER_VIDEO_ICR		$E30028
define	DRIVER_VIDEO_ISR		$E30020
define	DRIVER_VIDEO_SCREEN		$E30010
define	DRIVER_VIDEO_BUFFER		$E30014
define	DRIVER_VIDEO_PALETTE		$E30200
define	DRIVER_VIDEO_TIMING0		$E30000
define	DRIVER_VIDEO_TIMING1		$E30004
define	DRIVER_VIDEO_TIMING2		$E30008
define	DRIVER_VIDEO_TIMING3		$E3000C

define	DRIVER_VIDEO_IRQ		00100000b
define	DRIVER_VIDEO_IRQ_LOCK		KERNEL_INTERRUPT_ISR_DATA_VIDEO
define	DRIVER_VIDEO_IRQ_LOCK_SET	0

video:

.init:
	di
	ld	de, DRIVER_VIDEO_PALETTE
	ld	hl, KERNEL_MM_NULL
	ld	bc, 512
	ldir
	ld	hl, DRIVER_VIDEO_IMSC
	ld	(hl), DRIVER_VIDEO_IMSC_DEFAULT
	ld	hl, DRIVER_VIDEO_CTRL_DEFAULT
	ld	(DRIVER_VIDEO_CTRL), hl
	ld	hl, DRIVER_VIDEO_VRAM
	ld	(DRIVER_VIDEO_SCREEN), hl
	ld	hl, DRIVER_VIDEO_VRAM + DRIVER_VIDEO_FRAMEBUFFER_SIZE
	ld	(DRIVER_VIDEO_BUFFER), hl
; setup timings
	ld	hl, .LCD_TIMINGS
	ld	de, DRIVER_VIDEO_TIMING0 + 1
	ld	c, 8
	ldir
; clear the LCD
	call	.clear_screen
	call	.clear_buffer
; IRQ handle
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	call	atomic_mutex.init
	ld	hl, .irq_handler
	ld	a, DRIVER_VIDEO_IRQ
	jp	kinterrupt.irq_request

.irq_handler:
	ld	hl, DRIVER_VIDEO_ICR
	set	3, (hl)
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	bit	DRIVER_VIDEO_IRQ_LOCK_SET, (hl)
	ret	z
	inc	hl
	ld	a, (hl)
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	inc	hl
	ld	iy, (hl)
; signal the IRQ to a waiting (helper / or not ) thread
	ld	a, DRIVER_VIDEO_IRQ
	jp	kthread.irq_resume

.irq_lock:
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	jp	atomic_mutex.lock
	
.irq_unlock:
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	jp	atomic_mutex.unlock
	
.swap:
	ld	a, i
	ld	a, DRIVER_VIDEO_IRQ
	di
	ld	hl, DRIVER_VIDEO_ICR
	set	2, (hl)
	ld	l, DRIVER_VIDEO_ISR and $FF
.wait_LBNU:
	bit	2, (hl)
	jr	z, .wait_LBNU
	ld	hl, (DRIVER_VIDEO_SCREEN) 
	ld	de, (DRIVER_VIDEO_BUFFER)
	ld	(DRIVER_VIDEO_BUFFER), hl
	ld	(DRIVER_VIDEO_SCREEN), de
; is interrupt enabled ?
; quit if not enabled, wait for vsync signal else
	jp	pe, kthread.wait
	jr	.vsync_atomic

.vsync:
	ld	a, i
	ld	a, DRIVER_VIDEO_IRQ
	jp	pe, kthread.wait
	
.vsync_atomic:
; wait until the LCD finish displaying the frame
	ld	hl, DRIVER_VIDEO_ICR
	set	3, (hl)
	ld	l, DRIVER_VIDEO_ISR and $FF
.wait_vcomp:
	bit	3, (hl)
	jr	z, .wait_vcomp
	ret
	
.clear_buffer:
	ld	de, (DRIVER_VIDEO_BUFFER)
	ld	hl, KERNEL_MM_NULL
	ld	bc, 76800
	ldir
	ret

.clear_screen:
	ld	de, (DRIVER_VIDEO_SCREEN)
	ld	hl, KERNEL_MM_NULL
	ld	bc, 76800
	ldir
	ret

.clear_color:
	ld	de, (DRIVER_VIDEO_BUFFER)
	sbc	hl, hl
	adc	hl, de
	inc	de
	ld	(hl), c
	ld	bc, 76799
	ldir
	ret

.copy_buffer:
	ld	hl, (DRIVER_VIDEO_BUFFER)
	ld	de, (DRIVER_VIDEO_SCREEN)
	ld	bc, 76800
	ldir
	ret

.LCD_TIMINGS:
;	db	14 shl 2		; PPL shl 2
	db	7			; HSW
	db	87			; HFP
	db	63			; HBP
	dw	(0 shl 10)+319		; (VSW shl 10)+LPP
	db	179			; VFP
	db	0			; VBP
	db	(0 shl 6)+(0 shl 5)+0	; (ACB shl 6)+(CLKSEL shl 5)+PCD_LO
;  H = ((PPL+1)*16)+(HSW+1)+(HFP+1)+(HBP+1) = 240+8+88+64 = 400
;  V = (LPP+1)+(VSW+1)+VFP+VBP = 320+1+179+0 = 500
; CC = H*V*PCD*2 = 400*500*2*2 = 800000
; Hz = 48000000/CC = 60
