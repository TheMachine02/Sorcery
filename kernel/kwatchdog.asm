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
	ld	hl, KERNEL_WATCHDOG_CTRL
	ld	a, 20		; 32768Hz, trigger NMI
	ld	(hl), a
	ld	de, KERNEL_WATCHDOG_LOAD
	ld	hl, .RESET_DATA
	ld	bc, 6
	ldir
; now, reset the status register too
	ld	hl, KERNEL_WATCHDOG_CLR
	set	0, (hl)
; and start the timer	
	ld	hl, KERNEL_WATCHDOG_CTRL
	set	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
	ret

.stop:
	ld	hl, KERNEL_WATCHDOG_CLR
	set	0, (hl)
; and stop the timer	
	ld	hl, KERNEL_WATCHDOG_CTRL
	res	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
	ret

.RESET_DATA:
	db	$00, $00, $01, $00, $B9, $5A
