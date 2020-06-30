;include 'include/kernel.inc'

define DRIVER_VIDEO_VRAM                  0xD40000
define DRIVER_VIDEO_VRAM_SIZE             0x25800
define DRIVER_VIDEO_FRAMEBUFFER_SIZE      0x12C00
define DRIVER_VIDEO_CTRL                  0xE30018
define DRIVER_VIDEO_CTRL_DEFAULT          100100100111b
define DRIVER_VIDEO_IMSC                  0xE3001C
define DRIVER_VIDEO_IMSC_DEFAULT          00000100b
define DRIVER_VIDEO_ICR                   0xE30028
define DRIVER_VIDEO_ISR                   0xE30020
define DRIVER_VIDEO_SCREEN                0xE30010
define DRIVER_VIDEO_BUFFER                0xE30014
define DRIVER_VIDEO_PALETTE               0xE30200
define DRIVER_VIDEO_TIMING0               0xE30000
define DRIVER_VIDEO_TIMING1               0xE30004
define DRIVER_VIDEO_TIMING2               0xE30008
define DRIVER_VIDEO_TIMING3               0xE3000C

; define DRIVER_VIDEO_FONT_PALETTE          0xE30C08
; define DRIVER_VIDEO_BLIT_PALETTE          0xE30C09

define DRIVER_VIDEO_IRQ                   00100000b
define DRIVER_VIDEO_IRQ_LOCK              0xE30C0A
define DRIVER_VIDEO_IRQ_LOCK_THREAD       0xE30C0B
define DRIVER_VIDEO_IRQ_LOCK_SET          0

kvideo:
	db	21
.jump:
	jp	.init
	jp	.irq_handler
	jp	.irq_lock
	jp	.irq_unlock
	jp	.swap
	jp	.vsync
	jp	.clear_buffer
	jp	.clear_color

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
	ld	hl, DRIVER_VIDEO_TIMING0 + 1
	ld	de, .LCD_TIMINGS
	ld	c, 8
	ldir
; clear the LCD
	call	.clear_screen
	call	.clear_buffer
; IRQ handle
	call	.irq_lock_reset
	ld	hl, .irq_handler
	ld	a, DRIVER_VIDEO_IRQ
	jp	kirq.request

.irq_handler:
	ld	hl, DRIVER_VIDEO_ICR
	set	2, (hl)
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	bit	DRIVER_VIDEO_IRQ_LOCK_SET, (hl)
; carry flag is untouched, meaning that this IRQ will need a thread wake    
	ret	z
	ld	iy, (DRIVER_VIDEO_IRQ_LOCK_THREAD)
; reset the carry flag, IRQ doesn't need thread to be waked
	jp	kthread.resume_from_IRQ

.irq_lock:
	di
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	sra	(hl)
	jr	nc, .irq_lock_acquire
	call	kthread.yield
	jr	.irq_lock
.irq_lock_acquire:
	ld	hl, (kthread_current)
	ld	(DRIVER_VIDEO_IRQ_LOCK_THREAD), hl
	ei
	ret

.irq_unlock:
; does we own it ?
	ld	hl, (kthread_current)
	ld	de, (DRIVER_VIDEO_IRQ_LOCK_THREAD)
	or	a, a
	sbc	hl, de
; nope, bail out
	ret	nz
; set them freeeeee
.irq_lock_reset:
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	ld	(hl), KERNEL_MUTEX_MAGIC
	inc	hl
	ld	de, NULL
	ld	(hl), de
	ret

.vsync:
	ld	a, i
	jp	po, .vsync_atomic
	ld	a, DRIVER_VIDEO_IRQ
	jp	kthread.wait_on_IRQ
	
.swap:
	ld	a, i
	di
	ld	hl, (DRIVER_VIDEO_SCREEN) 
	ld	de, (DRIVER_VIDEO_BUFFER)
	ld	(DRIVER_VIDEO_BUFFER), hl
	ld	(DRIVER_VIDEO_SCREEN), de
; is interrupt enabled ?
; quit if not enabled, wait for vsync signal else
	jp	po, .vsync_atomic
	ld	a, DRIVER_VIDEO_IRQ
	jp	kthread.wait_on_IRQ	

.vsync_atomic:
; wait until the LCD finish displaying the frame
	ld	hl, DRIVER_VIDEO_ICR
	set	2, (hl)
	ld	l, DRIVER_VIDEO_ISR and $FF
.wait_busy:
	bit	2, (hl)
	jr	z, .wait_busy
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
	or	a, a
	sbc	hl, hl
	add	hl, de
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
 db	7			; HSW
 db	87			; HFP
 db	63			; HBP
 dw	(0 shl 10)+319	; (VSW shl 10)+LPP
 db	179			; VFP
 db	0			; VBP
 db	(0 shl 6)+(0 shl 5)+0	; (ACB shl 6)+(CLKSEL shl 5)+PCD_LO
