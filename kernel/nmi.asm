define	CONTEXT_FRAME			0
define	CONTEXT_FRAME_RET		0	; PC register ;
define	CONTEXT_FRAME_PC		0
define	CONTEXT_FRAME_SP		3	; SP register ;
define	CONTEXT_FRAME_STACKFRAME	6	; IX register ;
define	CONTEXT_FRAME_IX		6
define	CONTEXT_FRAME_IY		9	; extended register frame ;
define	CONTEXT_FRAME_DE		12
define	CONTEXT_FRAME_BC		15
define	CONTEXT_FRAME_AF		18
define	CONTEXT_FRAME_IR		21
define	CONTEXT_FRAME_HL		24

define	nmi_context			$D00140
define	nmi_stack			$D001FA

assert $ < $0220A8
rb $0220A8-$

nmi:
.service:
	ld	(nmi_context+CONTEXT_FRAME_HL), hl
	pop	hl
	ld	(nmi_context+CONTEXT_FRAME_PC), hl
	ld	(nmi_context+CONTEXT_FRAME_SP), sp
	ld	sp, nmi_context+CONTEXT_FRAME_HL
; loading i use MBASE
	ld	hl, i
	push	hl
	push	af
	push	bc
	push	de
	push	iy
	push	ix
; restore stack pointer (to be sure we *have* a valid stack pointer (within kernel heap, whatever)
	ld	sp, nmi_stack
; perform NMI now that context has been saved
; restore CPU power state
	ld	a, $03
	ld	(KERNEL_FLASH_CTRL), a
	out0	(KERNEL_POWER_CPU_CLOCK), a
; reset major subsystem
	call	video.init
	call	console.fb_takeover_nmi
; now, process
	ld	hl, KERNEL_WATCHDOG_CTRL
	res	0, (hl)
	ld	l, KERNEL_WATCHDOG_ISR and $FF
	ld	a, (hl)
	or	a, a
	jr	nz, .watchdog_violation
	in0	a, ($3D)
	and	a, $03
	out0	($3E), a
	rra
	jr	c, .stack_overflow
	rra
	jr	c, .memory_protection

.deadlock:
	ld	hl, .THREAD_DEADLOCK
.reboot_trampoline:
	call	.exception_write
	jp	kinit.reboot

.watchdog_violation:
	ld	hl, .WATCHDOG_EXCEPTION
	jr	.reboot_trampoline
	
.stack_overflow:
	ld	hl, .STACKOVERFLOW_EXCEPTION
.core_trampoline:
	call	.exception_write
; we should be able to recover here ;
	jp	kthread.core

.memory_protection:
	ld	hl, .MEMORY_EXCEPTION
	jr	.core_trampoline
	
.illegal_instruction:
; try to know which instruction triggered it
	pop	hl
; return address = hl
	push	hl
	dec	hl
	ld	a, (hl)
; a = last instruction part
; check if instruction was rst $0 meaning a probable memory poison corruption
	cp	a, $C7
	ld	hl, .POISON_MEMORY
	jr	z, .core_trampoline
	ld	hl, .ILLEGAL_TRAP
	jr	.core_trampoline

.longjump:
; restore context
	ld	hl, (ix+CONTEXT_FRAME_IR)
	ld	i, hl
	ld	a, (ix+CONTEXT_FRAME_IR+2)
	ld	MB, a
	ld	hl, (ix+CONTEXT_FRAME_AF)
	push	hl
	pop	af
	ld	hl, (ix+CONTEXT_FRAME_SP)
	ld	sp, hl
	ld	hl, (ix+CONTEXT_FRAME_PC)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_HL)
	ld	bc, (ix+CONTEXT_FRAME_BC)
	ld	de, (ix+CONTEXT_FRAME_DE)
	ld	iy, (ix+CONTEXT_FRAME_IY)
	ld	ix, (ix+CONTEXT_FRAME_IX)
	retn
 
.exception_write:
	ld	ix, nmi_context
; hl is exception string
	push	hl
	ld	hl, .CONTEXT_FRAME_SYSE
	ld	bc, 24
	call	console.phy_write
	pop	hl
	ld	bc, 0
	ld	c, (hl)
	inc	hl
	call	console.phy_write
	ld	hl, (ix+CONTEXT_FRAME_IR)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_PC)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_SP)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_IX)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_IY)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_HL)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_DE)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_BC)
	push	hl
	ld	hl, (ix+CONTEXT_FRAME_AF)
	push	hl
	ld	hl, .CONTEXT_FRAME_STR
	push	hl
	ld	hl, console_string
	push	hl
	call	_boot_sprintf_safe
	ld	hl, 33
	add	hl, sp
	ld	sp, hl
	ld	hl, console_string
	ld	bc, 183
	call	console.phy_write
; unwind stack frame
	ld	ix, (ix+CONTEXT_FRAME_SP)
	ld	b, 8
.exception_unwind:
	push	bc
	pea	ix+3
	ld	hl, (ix+0)
	push	hl
	ld	hl, .CONTEXT_STACK_STR
	push	hl
	ld	hl, console_string
	push	hl
	call	_boot_sprintf_safe
	ld	hl, 9
	add	hl, sp
	ld	sp, hl
	ld	hl, console_string
	ld	bc, 15
	call	console.phy_write
	pop	ix
	pop	bc
	djnz	.exception_unwind
; wait any key
	ld	hl, DRIVER_KEYBOARD_CTRL
	ld	(hl), 1
	ld	l, DRIVER_KEYBOARD_IMSC and $FF
	set	2, (hl)
	ld	l, DRIVER_KEYBOARD_ISCR and $FF
.wait_busy:
	bit	2, (hl)
	jr	z, .wait_busy
	ld	l, DRIVER_KEYBOARD_IMSC and $FF
	res	2, (hl)
; idle mode now
	ld	(hl), h
; also restore console state, and return
	ret

.THREAD_DEADLOCK:
 db 15, "system deadlock"
.WATCHDOG_EXCEPTION:
 db 18, "watchdog violation"
.STACKOVERFLOW_EXCEPTION:
 db 14, "stack overflow"
.MEMORY_EXCEPTION:
 db 17, "memory protection"
.POISON_MEMORY:
 db 18, "poisoned derefence"
.ILLEGAL_TRAP:
 db 19, "illegal instruction"
 
 ; size 24
.CONTEXT_FRAME_SYSE:
 db "System exception : ", $1B, "[31m"
 
.CONTEXT_FRAME_STR:
 db 10,10, $1B, "[39m"
 db "     af: 0x%06x bc: 0x%06x de: 0x%06x", 10
 db "     hl: 0x%06x ",$1B,"[35m","iy", $1B,"[39m", ": 0x%06x ",$1B,"[35m", "ix", $1B,"[39m", ": 0x%06x", 10
 db "     sp: 0x%06x pc: 0x%06x ",$1B,"[33m","ir", $1B,"[39m", ": 0x%06x", 10, 10
 db "Stack frame :", 0
 
 ; blit on screen 8 last value of the stack
 ; size 15 (not counting null)
 .CONTEXT_STACK_STR:
 db 10,"     +0x%06x", 0

_boot_sprintf_safe:
; the nice _boot_sprintf routine is bugged, and scrap need to be cleared to zero
	or	a, a
	sbc	hl, hl
	ld	(KERNEL_HEAP+32), hl
	jp	_boot_sprintf
