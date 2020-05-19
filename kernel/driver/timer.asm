;include 'include/kernel.inc'

define DRIVER_TIMER1_COUNTER             0xF20000
define DRIVER_TIMER1_RST                 0xF20004
define DRIVER_TIMER1_MATCH1              0xF20008
define DRIVER_TIMER1_MATCH2              0xF2000C
define DRIVER_TIMER1_CTRL                0xF20030
define DRIVER_TIMER1_ISCR                0xF20034
define DRIVER_TIMER1_ISR                 0xD000F1
define DRIVER_TIMER1_INTERRUPT           00000010b
define DRIVER_TIMER1_SIGNAL              00000010b
define DRIVER_TIMER1_LOCK_THREAD         0xD000F2
define DRIVER_TIMER1_LOCK_CTRL           0xD000F5
define DRIVER_TIMER1_LOCK_ENABLE_BIT     0

ktimer:
	db	3
.jump:
	jp	.init
	jp	.interrupt
	jp	.wait

.init:
	tstdi
; init the lock
    ld	hl, DRIVER_TIMER1_LOCK_CTRL
	ld (hl), 0xFE
; interruption init
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	ld	a, (hl)
	or	a, KERNEL_INTERRUPT_TIMER1
	ld	(hl), a
	ld	hl, KERNEL_INTERRUPT_SIGNAL_LATCH
	ld	a, (hl)
	or	a, KERNEL_INTERRUPT_TIMER1
	ld	(hl), a
	ld	hl, .interrupt
	ld	a, KERNEL_INTERRUPT_TIMER1_BIT
	call	kinterrupt.register
; todo : enable the timer 1 with default paramater
	retei

.interrupt:
	push	af
	ld	hl, DRIVER_TIMER1_ISCR
	ld	a, (hl)
	ld	(DRIVER_TIMER1_ISR), a
	ld	(hl), 0x03
	ld	hl, DRIVER_TIMER1_LOCK_CTRL
	bit	DRIVER_TIMER1_LOCK_ENABLE_BIT, (hl)	
	jr	nz, .interrupt_lock
	ld	a, DRIVER_TIMER1_SIGNAL
	call	kscheduler.set_io_signal
	pop	af
	ret
.interrupt_lock:
	ld	iy, (DRIVER_TIMER1_LOCK_THREAD)
	call	kthread.resume
	pop	af
	ret

.lock:
	ld	hl, DRIVER_TIMER1_LOCK_CTRL
    sra (hl)
    jr  nc, .lock_acquire
    call    kscheduler.switch
    jr  .lock
.lock_acquire:
    ld  hl, (kthread_current)
    ld  (DRIVER_TIMER1_LOCK_THREAD), hl
	ret

.unlock:
; does we own it ?
    ld  hl, (kthread_current)
    ld  de, (DRIVER_TIMER1_LOCK_THREAD)
    or  a, a
    sbc hl, de
; nope, bail out
    ret nz
; set them freeeeee
    ld	hl, DRIVER_TIMER1_LOCK_CTRL
	ld (hl), 0xFE
	ret
	
.wait:
	ld iy, (kthread_current)
	ld (iy+KERNEL_THREAD_IRQ), DRIVER_TIMER1_IRQ
	jp	kthread.suspend
