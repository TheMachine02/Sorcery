;include 'include/kernel.inc'

define	DRIVER_KEYBOARD_CTRL			$F50000
define	DRIVER_KEYBOARD_ISCR			$F50008
define	DRIVER_KEYBOARD_IMSC			$F5000C
define	DRIVER_KEYBOARD_SCAN_IDLE		0
define	DRIVER_KEYBOARD_SCAN_CONTINUOUS		3
define	DRIVER_KEYBOARD_SCAN_SINGLE		2
define	DRIVER_KEYBOARD_SCAN_DETECTION		1
define	DRIVER_KEYBOARD_IRQ			00010000b
define	DRIVER_KEYBOARD_IRQ_LOCK		KERNEL_INTERRUPT_ISR_DATA_KEYBOARD
define	DRIVER_KEYBOARD_ISR			KERNEL_INTERRUPT_ISR_DATA_KEYBOARD + 6
define	DRIVER_KEYBOARD_IRQ_LOCK_SET		0

define	DRIVER_KEYBOARD_DELAY_RATE		150

keyboard:
    
.init:
	di
	ld	hl, DRIVER_KEYBOARD_CTRL
	ld	(hl), DRIVER_KEYBOARD_SCAN_CONTINUOUS
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
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK
	call	atomic_mutex.init
; enable IRQ handler & enable IRQ
	ld	hl, .irq_handler
	ld	a, DRIVER_KEYBOARD_IRQ
	jp	kinterrupt.irq_request

.irq_handler:
	ld	hl, DRIVER_KEYBOARD_ISCR
	ld	a, (hl)
	ld	(hl), $07
	ld	(DRIVER_KEYBOARD_ISR), a
; check register
	ld	l, $14
	bit	7, (hl)
	jr	z, .__irq_no_ctrl
	ld	l, $12
	bit	0, (hl)
	call	nz, console.irq_switch
.__irq_no_ctrl:
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK
	bit	DRIVER_KEYBOARD_IRQ_LOCK_SET, (hl)
	ret	z
	inc	hl
	ld	a, (hl)
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	inc	hl
	ld	iy, (hl)
	ld	a, DRIVER_KEYBOARD_IRQ
	jp	kthread.irq_resume

.irq_lock:
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK
	jp	atomic_mutex.lock
	
.irq_unlock:
	ld	hl, DRIVER_KEYBOARD_IRQ_LOCK
	jp	atomic_mutex.unlock

.wait_key:
	ld	a, i
	ld	a, DRIVER_KEYBOARD_IRQ
	jp	pe, kthread.wait

.wait_key_atomic:
; TODO : implement
	ret

.load_keymap:
	ret

.getchar:
	ret
