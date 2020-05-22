;include 'include/kernel.inc'

define	DRIVER_KEYBOARD_CTRL                0xF50000
define	DRIVER_KEYBOARD_ISCR                0xF50008
define	DRIVER_KEYBOARD_IMSC                0xF5000C
define	DRIVER_KEYBOARD_ISR                 0xD000FB
define	DRIVER_KEYBOARD_CONTINUOUS_SCAN     3
define	DRIVER_KEYBOARD_SINGLE_SCAN         2
define	DRIVER_KEYBOARD_KEY_DETECTION       1
define	DRIVER_KEYBOARD_IRQ                 00010000b
define	DRIVER_KEYBOARD_IRQ_LOCK            0xE30C0A
define	DRIVER_KEYBOARD_IRQ_LOCK_THREAD     0xE30C0B
define	DRIVER_KEYBOARD_IRQ_LOCK_SET        0

kkeyboard:
	db	5
.jump:
	jp	.init
	jp	.irq_handler
	jp	.irq_lock
	jp	.irq_unlock
	jp	.wait_key
	jp	.wait_scan
    
.init:
	tstdi
	ld	hl, DRIVER_KEYBOARD_CTRL
	ld	a, DRIVER_KEYBOARD_CONTINUOUS_SCAN
	ld	(hl), a
	xor	a, a
	inc	l
	ld	(hl), 15
	inc	l
	ld	(hl), a
	inc	l
	ld	(hl), 15
	inc	l
	ld	a, 8
	ld	(hl), a
	inc	l
	ld	(hl), a
; enable interrupt chip side
	ld	hl, DRIVER_KEYBOARD_IMSC
	ld	(hl), 2
; lock reset
	call	.irq_lock_reset
; enable IRQ handler & enable IRQ
	ld	hl, .irq_handler
	ld	a, DRIVER_KEYBOARD_IRQ
	call	kirq.request
	retei

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
	push	af
	ld	a, (iy+KERNEL_THREAD_IRQ)
	or	a, a
	ld	(iy+KERNEL_THREAD_IRQ), 0
	call	nz, kthread.resume
	pop	af
	ccf
	ret
		
.irq_lock:
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK
	sra	(hl)
	jr	nc, .irq_lock_acquire
	call	kthread.yield
	jr	.irq_lock
.irq_lock_acquire:
	ld	hl, (kthread_current)
	ld	(DRIVER_KEYBOARD_IRQ_LOCK_THREAD), hl
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
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK_THREAD
	ld	de, NULL
	ld	(hl), de
	dec	hl
	ld	(hl), KERNEL_MUTEX_MAGIC
	ret

.wait_key:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_IRQ), DRIVER_KEYBOARD_IRQ
	jp	kthread.suspend
	    
.wait_scan:
	ld	hl, DRIVER_KEYBOARD_IMSC
	set	0, (hl)
.wait_scan_bit:    
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_IRQ), DRIVER_KEYBOARD_IRQ
	call	kthread.suspend
	ld	hl, DRIVER_KEYBOARD_ISR
	bit	0, (hl)
	jr	z, .wait_scan_bit
	ld	hl, DRIVER_KEYBOARD_IMSC
	res	0, (hl)
	ret
