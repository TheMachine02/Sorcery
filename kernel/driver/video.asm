define DRIVER_VIDEO_VRAM                  $D40000
define DRIVER_VIDEO_VRAM_SIZE             $25800
define DRIVER_VIDEO_FRAMEBUFFER_SIZE      $12C00
define DRIVER_VIDEO_CTRL                  $E30018
define DRIVER_VIDEO_CTRL_DEFAULT          100100100111b
define DRIVER_VIDEO_IMSC                  $E3001C
define DRIVER_VIDEO_IMSC_DEFAULT          00000100b
define DRIVER_VIDEO_ICR                   $E30028
define DRIVER_VIDEO_ISR                   $E30020
define DRIVER_VIDEO_SCREEN                $E30010
define DRIVER_VIDEO_BUFFER                $E30014
define DRIVER_VIDEO_PALETTE               $E30200
define DRIVER_VIDEO_TIMING0               $E30000
define DRIVER_VIDEO_TIMING1               $E30004
define DRIVER_VIDEO_TIMING2               $E30008
define DRIVER_VIDEO_TIMING3               $E3000C

define DRIVER_VIDEO_IRQ                   00100000b
define DRIVER_VIDEO_IRQ_LOCK              $D00060
define DRIVER_VIDEO_IRQ_LOCK_THREAD       $D00061
define DRIVER_VIDEO_IRQ_LOCK_SET          0

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
	call	.irq_lock_reset
	ld	hl, .irq_handler
	ld	a, DRIVER_VIDEO_IRQ
	jp	kinterrupt.irq_request

.irq_handler:
	ld	hl, DRIVER_VIDEO_ICR
	set	2, (hl)
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	bit	DRIVER_VIDEO_IRQ_LOCK_SET, (hl)
	jp	z, kinterrupt.irq_resume
	ld	iy, (DRIVER_VIDEO_IRQ_LOCK_THREAD)
; signal the IRQ to a waiting (helper / or not ) thread
	ld	a, DRIVER_VIDEO_IRQ
	call	kthread.resume_from_IRQ
	jp	kinterrupt.irq_resume_thread

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
	
.swap:
	ld	a, i
	ld	a, DRIVER_VIDEO_IRQ
	di
	ld	hl, (DRIVER_VIDEO_SCREEN) 
	ld	de, (DRIVER_VIDEO_BUFFER)
	ld	(DRIVER_VIDEO_BUFFER), hl
	ld	(DRIVER_VIDEO_SCREEN), de
; is interrupt enabled ?
; quit if not enabled, wait for vsync signal else
	jp	pe, kthread.wait_on_IRQ
	jr	.vsync_atomic

.vsync:
	ld	a, i
	ld	a, DRIVER_VIDEO_IRQ
	jp	pe, kthread.wait_on_IRQ
	
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
