define	KERNEL_WATCHDOG_VIOLATION	$DE
define	KERNEL_WATCHDOG_HEARTBEAT	$008000		; 1s heartbeat
define	KERNEL_WATCHDOG_COUNTER		$F10000
define	KERNEL_WATCHDOG_LD		$F10004
define	KERNEL_WATCHDOG_RST		$F10008
define	KERNEL_WATCHDOG_CTRL		$F1000C
define	KERNEL_WATCHDOG_STATUS		$F10010
define	KERNEL_WATCHDOG_CLR		$F10014
define	KERNEL_WATCHDOG_ICR		$F10018
define	KERNEL_WATCHDOG_REVISION	$F1001C
define	KERNEL_WATCHDOG_BIT_ENABLE    0
define	KERNEL_WATCHDOG_BIT_REBOOT    1
define	KERNEL_WATCHDOG_BIT_NMI       2
define	KERNEL_WATCHDOG_BIT_EXTERNAL  3
define	KERNEL_WATCHDOG_BIT_CLOCK     4

kwatchdog:

.init:
	di
	ld	de, KERNEL_WATCHDOG_CTRL
; 32768Hz, trigger NMI
	ld	a, 00010100b
	ld	(de), a
	ld	e, KERNEL_WATCHDOG_LD and $FF
	ld	hl, .RESET_DATA
	ld	bc, 6
	ldir
; now, reset the status register too
	ex	de, hl
	ld	l, KERNEL_WATCHDOG_CLR and $FF
	set	0, (hl)
; one shot interrupt
	ld	l, KERNEL_WATCHDOG_ICR and $FF
	ld	(hl), 0

.arm:
; and start the timer
	ld	hl, KERNEL_WATCHDOG_CTRL
	set	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
	ret
	
.disarm:
	ld	hl, KERNEL_WATCHDOG_CLR
	set	0, (hl)
; and stop the timer
	ld	l, KERNEL_WATCHDOG_CTRL and $FF
	res	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
	ret

.RESET_DATA:
	db	$00, $80, $00, $00, $B9, $5A