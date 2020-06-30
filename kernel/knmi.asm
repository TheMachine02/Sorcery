define	CONTEXT_FRAME		0
define	CONTEXT_FRAME_RET		0	; PC register ;
define	CONTEXT_FRAME_PC		0
define	CONTEXT_FRAME_SP		3	; SP register ;
define	CONTEXT_FRAME_STACKFRAME	6	; IX register ;
define	CONTEXT_FRAME_IX		6
define	CONTEXT_FRAME_IY		9	; extended register frame ;
define	CONTEXT_FRAME_HL		12
define	CONTEXT_FRAME_DE		15
define	CONTEXT_FRAME_BC		18
define	CONTEXT_FRAME_AF		21
define	CONTEXT_FRAME_IR		24

define	knmi_context			$D00043

assert $ < $0220A8
rb $0220A8-$

knmi:
.service:
	ld	(knmi_context+CONTEXT_FRAME_IX), ix
	ld	ix, knmi_context
	ld	(ix+CONTEXT_FRAME_IY), iy
	ld	(ix+CONTEXT_FRAME_HL), hl
	ld	(ix+CONTEXT_FRAME_DE), de
	ld	(ix+CONTEXT_FRAME_BC), bc
	pop	hl
	ld	(ix+CONTEXT_FRAME_PC), hl
	ld	(knmi_context+CONTEXT_FRAME_SP), sp
; restore kernel stack pointer to be sure we *have* a valid stack pointer
	ld	sp, (KERNEL_STACK)
	push	af
	pop	hl
	ld	(ix+CONTEXT_FRAME_AF), hl
; loading i use MBASE
	ld	hl, i
	ld	(ix+CONTEXT_FRAME_IR), hl
; perform NMI now that context has been saved
; reset major subsystem
	call    kinterrupt.init
	call	console.init
; now, process
	ld	hl, KERNEL_WATCHDOG_CTRL
	res	KERNEL_WATCHDOG_BIT_ENABLE, (hl)
	ld	l, KERNEL_WATCHDOG_STATUS and $FF
	ld	a, (hl)
	or	a, a
	jr	nz, .watchdog_violation
	in0	a, ($3D)
	and	a, $03
	jr	nz, .stack_overflow
	jp	kinit.reboot
	
.watchdog_violation:
	ld	bc, .WATCHDOG_EXCEPTION
	call	.write_exception
	jp	kinit.reboot
	
.illegal_instruction:
	jp	kinit.reboot

.stack_overflow:
	ld	bc, .STACKOVERFLOW_EXCEPTION
	call	.write_exception
	jp	kinit.reboot
		
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
 
.write_exception:
; TODO : optimize this for size please
; bc is exception string
	ld	hl, (console_cursor_xy)
	call	console.glyph_string
	call	console.new_line
	call	console.new_line
	ld	bc, .CONTEXT_FRAME_STR0
	ld	a, 3
.write_loop:
	push	af
	ld	l, 5
	call	console.glyph_string
	inc	bc
	push	bc
	call	console.new_line
	pop	bc
	pop	af
	dec	a
	jr	nz, .write_loop
	call	console.new_line
	call	console.glyph_string
	
	ld	bc, (ix+CONTEXT_FRAME_AF)
	ld	hl, 7*256+9
	ld	a, 1
	call	console.glyph_hex
	
	ld	bc, (ix+CONTEXT_FRAME_BC)
	ld	hl, 7*256+23
	ld	a, 1
	call	console.glyph_hex
	
	ld	bc, (ix+CONTEXT_FRAME_DE)
	ld	hl, 7*256+37
	ld	a, 1
	call	console.glyph_hex

	ld	bc, (ix+CONTEXT_FRAME_HL)
	ld	hl, 8*256+9
	ld	a, 1
	call	console.glyph_hex
	
	ld	bc, (ix+CONTEXT_FRAME_IY)
	ld	hl, 8*256+23
	ld	a, 1
	call	console.glyph_hex
	
	ld	bc, (ix+CONTEXT_FRAME_IX)
	ld	hl, 8*256+37
	ld	a, 1
	call	console.glyph_hex
	
	ld	bc, (ix+CONTEXT_FRAME_SP)
	ld	hl, 9*256+9
	ld	a, 1
	call	console.glyph_hex
	
	ld	bc, (ix+CONTEXT_FRAME_PC)
	ld	hl, 9*256+23
	ld	a, 1
	call	console.glyph_hex
	
	ld	bc, (ix+CONTEXT_FRAME_IR)
	ld	hl, 9*256+37
	ld	a, 1
	call	console.glyph_hex
	
; blit stack and correspondance ?

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
	ret

.WATCHDOG_EXCEPTION:
 db "System exception : ", $1B,"[31m", "watchdog violation", $1B,"[39m", 0
.STACKOVERFLOW_EXCEPTION:
 db "System exception : ", $1B,"[31m", "stack overflow", $1B,"[39m", 0

.CONTEXT_FRAME_STR0:
 db "af:           bc:           de:         ", 0
.CONTEXT_FRAME_STR1:
 db "hl:           ",$1B,"[35m","iy", $1B,"[39m", ":           ",$1B,"[35m", "ix", $1B,"[39m", ":", 0
.CONTEXT_FRAME_STR2:
 db "sp:           pc:           ",$1B,"[33m","ir", $1B,"[39m", ":", 0
.CONTEXT_FRAME_STR3:
 db "Stack frame :", 0
 
; longjump and setjump context
; stackframe
; 
; 0021B7     FDE5          push iy
; 0021B9     FD21030000    ld iy,$000003
; 0021BE     FD39          add iy,sp
; 0021C0     FDE5          push iy
; 0021C2     E1            pop hl
; 0021C3     FD3703        ld iy,(iy+$03)	; iy is buffer
; 0021C6     FD3E03        ld (iy+$03),ix	; ix reg, stackframe
; 0021C9     FD2F06        ld (iy+$06),hl	; sp reg
; 0021CC     ED27          ld hl,(hl)		; address (stackpointer)
; 0021CE     FD2F00        ld (iy),hl
; 0021D1     21000000      ld hl,$000000
; 0021D5     FDE1          pop iy
; 0021D7     C9            ret 
; 0021D8     ED1300        lea de,iy
; 0021DB     FD21000000    ld iy,$000000
; 0021E0     FD39          add iy,sp
; 0021E2     FD2706        ld hl,(iy+$06)
; 0021E5     01000000      ld bc,$000000
; 0021E9     B7            or a,a
; 0021EA     ED42          sbc hl,bc
; 0021EC     2002          jr nz,$0021F0
; 0021EE     2E01          ld l,$01
; 0021F0     FD3703        ld iy,(iy+$03)
; 0021F3     FD3103        ld ix,(iy+$03)
; 0021F6     FD0700        ld bc,(iy)
; 0021F9     FD3706        ld iy,(iy+$06)
; 0021FC     FDF9          ld sp,iy
; 0021FE     FD0F00        ld (iy),bc
; 002201     D5            push de
; 002202     FDE1          pop iy
; 002204     C9            ret 
