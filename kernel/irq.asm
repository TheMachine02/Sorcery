define	KERNEL_IRQ_POWER		1
define	KERNEL_IRQ_TIMER1		2
define	KERNEL_IRQ_TIMER2		4
define	KERNEL_IRQ_TIMER3		8
define	KERNEL_IRQ_KEYBOARD		16
define	KERNEL_IRQ_LCD			32
define	KERNEL_IRQ_RTC			64
define	KERNEL_IRQ_USB			128

define	irq_handler   		$D00140
define	irq_handler_001		$D00140
define	irq_handler_002		$D00144
define	irq_handler_004		$D00148
define	irq_handler_008		$D0014C
define	irq_handler_016		$D00150
define	irq_handler_032		$D00154
define	irq_handler_064		$D00158
define	irq_handler_128		$D0015C

kirq:
.init:
	di
	ld	hl, irq_handler
	ld 	de, 4
	ld	b, 8
	ld	a, $C9
.init_handler:
	ld	(hl), a
	add	hl, de
	djnz	.init_handler
	ret

.free:
; disable the IRQ then remove the handler
	call	.disable
	push	de
	call    .extract_line
	ld	a, $C9
	ld	(hl), a
	ex	de, hl
	pop	de
	ret
        
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
	ld	bc, irq_handler
	add	hl, bc
	pop	af
	pop	bc
; hl = line, de = old hl, bc safe, af safe
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

.enable:
	push	hl
	push	bc
; enable a specific IRQ or a specific IRQ combinaison
	ld	c, a
	rra
	rra
	and	00111100b
	ld	b, a
; this is the second byte for interrupt mask
	ld	a, c
	and	00001111b
; critical section ;
	ld	hl, i
	push	af
	di
; this is the first byte
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	or	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	or	a, b
	ld	(hl), a
	pop	af
	ld	a, c
	pop	bc
	pop	hl
	ret	po
	ei	
	ret
    
.disable:
	push	hl
	push	bc
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
; critical section ;
	ld	hl, i
	push	af
	di
; this is the first byte
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	and	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	and	a, b
	ld	(hl), a
	pop	af
	ld	a, c
	pop	bc
	pop	hl
	ret	po
	ei
	ret
