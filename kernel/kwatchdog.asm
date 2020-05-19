define	KERNEL_WATCHDOG_VIOLATION     0xDE
define	KERNEL_WATCHDOG_MAX_TIME      0x008000
define	KERNEL_WATCHDOG_COUNTER       0xF16000
define	KERNEL_WATCHDOG_LOAD          0xF16004
define	KERNEL_WATCHDOG_RST           0xF16008
define	KERNEL_WATCHDOG_CTRL          0xF1600C
define	KERNEL_WATCHDOG_STATUS        0xF16010
define	KERNEL_WATCHDOG_CLR           0xF16014
define	KERNEL_WATCHDOG_REVISION      0xF1601C

define	KERNEL_WATCHDOG_BIT_ENABLE    0
define	KERNEL_WATCHDOG_BIT_REBOOT    1
define	KERNEL_WATCHDOG_BIT_NMI       2
define	KERNEL_WATCHDOG_BIT_EXTERNAL  3
define	KERNEL_WATCHDOG_BIT_CLOCK     4

kwatchdog:
.init:
    tstdi
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
	retei

.stop:
	ld	hl, KERNEL_WATCHDOG_CLR
	set	0, (hl)
; and stop the timer	
	ld	hl, KERNEL_WATCHDOG_CTRL
	res	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
	ret

.RESET_DATA:
	db	0x00, 0x80, 0x00, 0x00, 0xB9, 0x5A
