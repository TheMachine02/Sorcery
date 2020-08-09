;include 'include/kernel.inc'

define	DRIVER_KEYBOARD_CTRL                0xF50000
define	DRIVER_KEYBOARD_ISCR                0xF50008
define	DRIVER_KEYBOARD_IMSC                0xF5000C
define	DRIVER_KEYBOARD_ISR                 0xD000FB
define	DRIVER_KEYBOARD_MODE_IDLE		0
define	DRIVER_KEYBOARD_CONTINUOUS_SCAN     3
define	DRIVER_KEYBOARD_SINGLE_SCAN         2
define	DRIVER_KEYBOARD_KEY_DETECTION       1
define	DRIVER_KEYBOARD_IRQ                 00010000b
define	DRIVER_KEYBOARD_IRQ_LOCK            0xE30C0A
define	DRIVER_KEYBOARD_IRQ_LOCK_THREAD     0xE30C0B
define	DRIVER_KEYBOARD_IRQ_LOCK_SET        0

keyboard:
    
.init:
	di
	ld	hl, DRIVER_KEYBOARD_CTRL
	ld	(hl), DRIVER_KEYBOARD_MODE_IDLE
	ld	de, $08080F
	inc	l
	ld	(hl), e
	inc	l
	ld	(hl), h
	inc	l
	ld	(hl), de
; enable interrupt chip side
	ld	l, DRIVER_KEYBOARD_IMSC and $FF
; interrupt on data change
	ld	(hl), 2
; init the stdin file
; lock reset
	call	.irq_lock_reset
; enable IRQ handler & enable IRQ
	ld	hl, .irq_handler
	ld	a, DRIVER_KEYBOARD_IRQ
	jp	kinterrupt.irq_request

.irq_handler:
	push	af
	ld	hl, DRIVER_KEYBOARD_ISCR
	ld	a, (hl)
	ld	(hl), 0x07
	ld	(DRIVER_KEYBOARD_ISR), a
	pop	af
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK
	bit	DRIVER_KEYBOARD_IRQ_LOCK_SET, (hl)
	ret	z
	ld	iy, (DRIVER_KEYBOARD_IRQ_LOCK_THREAD)
	jp	kthread.resume_from_IRQ
		
.irq_lock:
	di
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK
	sra	(hl)
	jr	nc, .irq_lock_acquire
	call	kthread.yield
	jr	.irq_lock
.irq_lock_acquire:
	ld	hl, (kthread_current)
	ld	(DRIVER_KEYBOARD_IRQ_LOCK_THREAD), hl
	ei
	ret

.irq_unlock:
; does we own it ?
	ld	hl, (kthread_current)
	ld	de, (DRIVER_KEYBOARD_IRQ_LOCK_THREAD)
	or	a, a
	sbc	hl, de
; nope, bail out
	ret	nz
.irq_lock_reset:
; set them freeeeee
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK
	ld	(hl), KERNEL_MUTEX_MAGIC
	inc	hl
	ld	de, NULL
	ld	(hl), de
	ret

.wait_key:
	ld	a, DRIVER_KEYBOARD_IRQ
	jp	kthread.wait_on_IRQ
	    
; .wait_scan:
; 	ld	hl, DRIVER_KEYBOARD_IMSC
; 	set	0, (hl)
; 	ld	hl, DRIVER_KEYBOARD_ISR
; .wait_scan_bit:
; 	bit	0, (hl)
; 	jr	z, .wait_scan_bit
; 	set	0, (hl)
; 	ld	hl, DRIVER_KEYBOARD_IMSC
; 	res	0, (hl)
; 	ret
