define	KERNEL_WATCHDOG_VIOLATION     $DE
define	KERNEL_WATCHDOG_MAX_TIME      $010000
define	KERNEL_WATCHDOG_COUNTER       $F16000
define	KERNEL_WATCHDOG_LOAD          $F16004
define	KERNEL_WATCHDOG_RST           $F16008
define	KERNEL_WATCHDOG_CTRL          $F1600C
define	KERNEL_WATCHDOG_STATUS        $F16010
define	KERNEL_WATCHDOG_CLR           $F16014
define	KERNEL_WATCHDOG_REVISION      $F1601C

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
	ld	e, KERNEL_WATCHDOG_LOAD and $FF
	ld	hl, .RESET_DATA
	ld	bc, 6
	ldir
; now, reset the status register too
	ex	de, hl
	ld	l, KERNEL_WATCHDOG_CLR and $FF
	set	0, (hl)
; and start the timer	
	ld	l, KERNEL_WATCHDOG_CTRL and $FF
	set	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
	ret

.stop:
	ld	hl, KERNEL_WATCHDOG_CLR
	set	0, (hl)
; and stop the timer	
	ld	l, KERNEL_WATCHDOG_CTRL and $FF
	res	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
	ret

.RESET_DATA:
	db	$00, $00, $01, $00, $B9, $5A
