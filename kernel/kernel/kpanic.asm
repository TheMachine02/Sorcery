define KERNEL_REGISTER_DUMP KERNEL_THREAD+KERNEL_THREAD_HEADER	; pseudo heap space
define KERNEL_REGISTER_IX   0
define KERNEL_REGISTER_IY   3
define KERNEL_REGISTER_HL   6
define KERNEL_REGISTER_DE   9
define KERNEL_REGISTER_BC   12
define KERNEL_REGISTER_PC   15
define KERNEL_REGISTER_SP   18
define KERNEL_REGISTER_AF   21

; address 0220A8
kpanic:
.nmi:
	di
	ld	(KERNEL_REGISTER_DUMP), ix
	ld	ix, KERNEL_REGISTER_DUMP
	ld	(ix+KERNEL_REGISTER_IY), iy
	ld	(ix+KERNEL_REGISTER_HL), hl
	ld	(ix+KERNEL_REGISTER_DE), de
	ld	(ix+KERNEL_REGISTER_BC), bc
	pop	hl
	ld	(ix+KERNEL_REGISTER_PC),hl
	ld	(KERNEL_REGISTER_DUMP+KERNEL_REGISTER_SP), sp
; grab a usable stack.
;	ld	sp, (KERNEL_STACK) ; (note that idle thread reside within kernel stack, usually at the adress KERNEL_STACK)
; let's use the thread stack for now
; shady boot interrupt, curse YOU !
	push	af
	pop	hl
	ld	(ix+KERNEL_REGISTER_AF), hl
; disable watchdog as soon I am safe. & perform cleanup
	ld	hl, KERNEL_WATCHDOG_CTRL
	res	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
; suspend all thread : we NEED that, cause else, everything will just resume easily... and the offending thread might *CRASH* hard
; so suspend thread, kill offended thread as a response, and get all thread running again...

;	* todo*
	call    kinterrupt.init
	call	kvideo.init
	call    kkeyboard.init
; read possible source
	ld	a, (KERNEL_WATCHDOG_STATUS)
	or	a, a
	jr	nz, .nmi_watchdog_violation
.nmi_reboot:
	ld	a, 00010000b
	out0	(0x00), a
	nop
	nop
	jp	$000000

.nmi_watchdog_violation:
	ld	hl, 1
	ld	e, 1
	ld	bc, .WATCHDOG_ERROR_STRING
	call	kvideo.put_string
	ld	hl, 1
	ld	e, 13
	ld	bc, .PC_STRING
	call	kvideo.put_string
	ld	hl, 56
	ld	e, 13
	ld	bc, (ix+KERNEL_REGISTER_PC)
	call	kvideo.put_hex
	call    kvideo.swap
	call    kkeyboard.wait_key
; kill current thread
; it does mean it didn't play nice
; a reboot is maybe more in order....
	jp .nmi_reboot
	
.WATCHDOG_ERROR_STRING:
 db "[***] kernel panic : WATCHDOG_VIOLATION",0
.PC_STRING:
 db "[***] @0x",0
