define	KERNEL_WATCHDOG_HEARTBEAT	$008000		; 1s heartbeat
define	KERNEL_WATCHDOG_COUNTER		$F10000
define	KERNEL_WATCHDOG_LD		$F10004
define	KERNEL_WATCHDOG_RST		$F10008
define	KERNEL_WATCHDOG_CTRL		$F1000C
define	KERNEL_WATCHDOG_ISR		$F10010
define	KERNEL_WATCHDOG_ICR		$F10014
define	KERNEL_WATCHDOG_ILR		$F10018
define	KERNEL_WATCHDOG_REVISION	$F1001C
define	KERNEL_WATCHDOG_ENABLE		1
define	KERNEL_WATCHDOG_REBOOT		2
define	KERNEL_WATCHDOG_NMI		4
define	KERNEL_WATCHDOG_EXTERNAL	8
define	KERNEL_WATCHDOG_CLOCK		16

kwatchdog:

.init:
	di
	ld	de, KERNEL_WATCHDOG_CTRL
; 32768Hz, trigger NMI
	ld	a, KERNEL_WATCHDOG_NMI or KERNEL_WATCHDOG_CLOCK
	ld	(de), a
	ld	e, KERNEL_WATCHDOG_LD and $FF
	ld	hl, .RESET_DATA
	ld	bc, 6
	ldir
; now, reset the status register too
	ex	de, hl
	ld	l, KERNEL_WATCHDOG_ICR and $FF
	ld	(hl), c
; one shot interrupt
	ld	l, KERNEL_WATCHDOG_ILR and $FF
	ld	(hl), c

.arm:
; and start the timer
	ld	hl, KERNEL_WATCHDOG_ICR
	ld	(hl), h
	ld	l, KERNEL_WATCHDOG_RST and $FF
	ld	(hl), $B9
	inc	hl
	ld	(hl), $5A
	ld	l, KERNEL_WATCHDOG_CTRL and $FF
	set	0, (hl)
	ret
	
.disarm:
	ld	hl, KERNEL_WATCHDOG_ICR
	ld	(hl), h
; and stop the timer
	ld	l, KERNEL_WATCHDOG_CTRL and $FF
	res	0, (hl)
	ret

.RESET_DATA:
	db	$00, $80, $00, $00, $B9, $5A
