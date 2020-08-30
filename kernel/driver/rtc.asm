;include 'include/kernel.inc'

define	DRIVER_RTC_COUNTER_SECOND	0xF30000
define	DRIVER_RTC_COUNTER_MINUTE	0xF30004
define	DRIVER_RTC_COUNTER_HOUR		0xF30008
define	DRIVER_RTC_COUNTER_DAY		0xF3000C
define	DRIVER_RTC_ALARM_SECOND		0xF30010
define	DRIVER_RTC_ALARM_MINUTE		0xF30014
define	DRIVER_RTC_ALARM_HOUR		0xF30018
define	DRIVER_RTC_CTRL			0xF30020
define	DRIVER_RTC_WRITE_SECOND		0xF30024
define	DRIVER_RTC_WRITE_MINUTE		0xF30028
define	DRIVER_RTC_WRITE_HOUR		0xF3002C
define	DRIVER_RTC_WRITE_DAY		0xF30030
define	DRIVER_RTC_ISCR			0xF30034
define	DRIVER_RTC_DEFAULT		11011111b

define	DRIVER_RTC_SECOND_MASK		1
define	DRIVER_RTC_MINUTE_MASK		2
define	DRIVER_RTC_HOUR_MASK		4
define	DRIVER_RTC_DAY_MASK		8
define	DRIVER_RTC_ALARM_MASK		16
define	DRIVER_RTC_LOAD_MASK		32

define	DRIVER_RTC_ISR			KERNEL_INTERRUPT_ISR_DATA_RTC + 4
define	DRIVER_RTC_IRQ			01000000b
define	DRIVER_RTC_IRQ_LOCK_THREAD	KERNEL_INTERRUPT_ISR_DATA_RTC + 1
define	DRIVER_RTC_IRQ_LOCK		KERNEL_INTERRUPT_ISR_DATA_RTC
define	DRIVER_RTC_IRQ_LOCK_SET		0

rtc:

.init:
	di
	ld	hl, DRIVER_RTC_WRITE_SECOND
	ld	(hl), h
	ld	l, DRIVER_RTC_WRITE_MINUTE and $FF
	ld	(hl), h
	ld	l, DRIVER_RTC_WRITE_HOUR and $FF
	ld	(hl), h
	ld	l, DRIVER_RTC_WRITE_DAY and $FF
	ld	(hl), h
	inc	l
	ld	(hl), h
	ld	l, DRIVER_RTC_CTRL and $FF
	ld	(hl), DRIVER_RTC_DEFAULT
; reset lock
	call	.irq_lock_reset
; enable IRQ handler & enable IRQ
	ld	hl, .irq_handler
	ld	a, DRIVER_RTC_IRQ
	jp	kinterrupt.irq_request

.irq_handler:
	ld	hl, DRIVER_RTC_ISCR
	ld	a, (hl)
	ld	(DRIVER_RTC_ISR), a
	ld	(hl), 0xFF
	ld	hl, DRIVER_RTC_IRQ_LOCK
	bit	DRIVER_RTC_IRQ_LOCK_SET, (hl)
;	jp	z, kinterrupt.irq_resume
	ret	z
	ld	iy, (DRIVER_RTC_IRQ_LOCK_THREAD)
	ld	a, DRIVER_RTC_IRQ
	call	kthread.resume_from_IRQ
;	jp	kinterrupt.irq_resume_thread
	ret

.irq_lock:
	di
	ld	hl, DRIVER_RTC_IRQ_LOCK
	sra	(hl)
	jr	nc, .irq_lock_acquire
	call	kthread.yield
	jr	.irq_lock
.irq_lock_acquire:
	ld	hl, (kthread_current)
	ld	(DRIVER_RTC_IRQ_LOCK_THREAD), hl
	ei
	ret

.irq_unlock:
; does we own it ?
	ld	hl, (kthread_current)
	ld	de, (DRIVER_RTC_IRQ_LOCK_THREAD)
	or	a, a
	sbc	hl, de
; nope, bail out
	ret	nz
.irq_lock_reset:
; set them freeeeee
	ld	hl, DRIVER_RTC_IRQ_LOCK
	ld	(hl), KERNEL_MUTEX_MAGIC
	inc	hl
	ld	de, NULL
	ld	(hl), de
	ret
	    
.wait_alarm:
	ld	a, DRIVER_RTC_ALARM_MASK
	jr	.wait_bit
    
.wait_minute:
	ld	a, DRIVER_RTC_MINUTE_MASK
	jr	.wait_bit

.wait_hour:
	ld	a, DRIVER_RTC_HOUR_MASK
	jr	.wait_bit

.wait_day:
	ld	a, DRIVER_RTC_DAY_MASK
	jr	.wait_bit

.wait_second:
	ld	a, DRIVER_RTC_SECOND_MASK

.wait_bit:
	push	af
	ld	a, DRIVER_RTC_IRQ
	call	kthread.wait_on_IRQ
	ld	hl, DRIVER_RTC_ISR
	pop	af
	tst	a, (hl)
	jr	z, .wait_bit
	ret

.set_time:
	ret

.get_time:
	ret

.uptime:
; those read aren't atomic, so up_time isn't precise... but fast
	di
	ld	hl, (DRIVER_RTC_COUNTER_SECOND)
	push	hl
.uptime_restart:
	ld	b, 60
	ld	a, (DRIVER_RTC_COUNTER_MINUTE)
	ld	e, a
	ld	d, b
	mlt	de
	add	hl, de
	ld	a, (DRIVER_RTC_COUNTER_HOUR)
	ld	e, a
	ld	d, b
	mlt	de
	ld	c, e
	ld	e, b
	mlt	bc
	add	hl, bc
	mlt	de
	ex	de, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, de
	ex	(sp), hl
	ld	de, (DRIVER_RTC_COUNTER_SECOND)
	or	a, a
	sbc	hl, de	; failed
	ex	de, hl
	jr	nz, .uptime_restart
	pop	hl
	ei
	ret
	
.set_alarm:
	ret
