define	KERNEL_IRQ_POWER		1
define	KERNEL_IRQ_TIMER1		2
define	KERNEL_IRQ_TIMER2		4
define	KERNEL_IRQ_TIMER3		8
define	KERNEL_IRQ_KEYBOARD		16
define	KERNEL_IRQ_LCD			32
define	KERNEL_IRQ_RTC			64
define	KERNEL_IRQ_USB			128

define	KERNEL_IRQ_HANDLER   		$D00110
define	KERNEL_IRQ_HANDLER_001		$D00110
define	KERNEL_IRQ_HANDLER_002		$D00114
define	KERNEL_IRQ_HANDLER_004		$D00118
define	KERNEL_IRQ_HANDLER_008		$D0011C
define	KERNEL_IRQ_HANDLER_016		$D00120
define	KERNEL_IRQ_HANDLER_032		$D00124
define	KERNEL_IRQ_HANDLER_064		$D00128
define	KERNEL_IRQ_HANDLER_128		$D0012C

kirq:
.init:
	di
	ld	hl, KERNEL_IRQ_HANDLER
	ld	bc, 4
	ld 	de, .handler
	ld	a, 8
.init_handler:
	ld	(hl), de
	add	hl, bc
	dec	a
	jr	nz, .init_handler
	ret

.handler:
	ret

.free:
; disable the IRQ then remove the handler
	call	.disable
	push	de
	call    .extract_line
	ld	de, .handler
	ld	(hl), de
	ex	de, hl
	pop	de
	ret
    
.request:
; a = IRQ, hl = interrupt routine
; check the interrupt routine is in *RAM*
	push	de
	call	.extract_line
	ld	(hl), $C3
	inc	hl
	ld	(hl), de
	ex	de, hl
	pop	de
; register the handler then enable the IRQ    
	jr	.enable
    
.extract_line:
	push	bc
	push	af
	ld	b, $FF
.extract_bit:
	inc	b
	rra
	jr	nc, .extract_bit
	ld	a, b
	ex	de, hl
	add	a, a
	add	a, a
	sbc	hl, hl
	ld	l, a
	ld	bc, KERNEL_IRQ_HANDLER
	add	hl, bc
	pop	af
	pop	bc
; hl = line, de = old hl, bc safe, af safe
	ret

.enable:
	push	hl
	push	bc
	push	af
; enable a specific IRQ or a specific IRQ combinaison
	ld	c, a
	rra
	rra
	and	00111100b
	ld	b, a
; this is the second byte for interrupt mask
	ld	a, c
	and	00001111b
	ld	c, a
; critical section ;
	tstdi
; this is the first byte
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	ld	a, (hl)
	or	a, c
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	or	a, b
	ld	(hl), a
	tstei
	pop	af
	pop	bc
	pop	hl
	ret
    
.disable:
	push	hl
	push	bc
	push	af
; enable a specific IRQ
	ld	c, a
	rra
	rra
	cpl
	and	00111100b
	ld	b, a
; this is the second byte for interrupt mask
	ld	a, c
	cpl
	and	00001111b
	ld	c, a
; critical section ;
	tstdi
; this is the first byte
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	ld	a, (hl)
	and	a, c
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	and	a, b
	ld	(hl), a
	tstei
	pop	af
	pop	bc
	pop	hl
	ret
