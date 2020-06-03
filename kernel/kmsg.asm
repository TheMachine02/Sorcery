define	KERNEL_INFO				$1
define	KERNEL_WARNING				$2
define	KERNEL_ERROR				$4
define	KERNEL_MESSAGE_BUFFER_SIZE		$000400
define	KERNEL_MESSAGE_BUFFER_ADDRESS		$D00800
define	KERNEL_MESSAGE_BUFFER_END		$D00C00

; The first three bytes stand for the offset of the next location to write a kernel message.
define	kmsg_current_offset			$D00800

kmsg:
.init:
; initialize the circular buffer
	ld	hl, KERNEL_MESSAGE_BUFFER_ADDRESS
	ld	bc, KERNEL_MESSAGE_BUFFER_SIZE
	ld	de, KERNEL_DEV_NULL
	ldir
	ret
	
.printk:
;***************************************************************
;* INPUT
;*	- A : Kernel message type :
;*			KERNEL_INFO, KERNEL_WARNING or KERNEL_ERROR.
;*	- BC : address of the 0-terminated string.
;* OUTPUT
;*	- A and the message pointed by HL are copied into BUFFER_ADDR (circularly).
;***************************************************************
; writing to the memory buffer should be atomic
	tstdi
	push	bc
	ld	ix, KERNEL_MESSAGE_BUFFER_ADDRESS
	ld	hl, (ix)
	lea	de, ix+0
	add	hl, de
	ex	de, hl
	ld	bc, KERNEL_MESSAGE_BUFFER_SIZE
	add	hl, bc
	pop	bc
	ex	de, hl
	ld 	(hl), a
	inc	hl
.printk_loop:
	push	hl
	or	a, a
	sbc	hl, de
	pop	hl
	jr	c, .printk_buffer_free0
	lea	hl, ix+3
.printk_buffer_free0:
	ld	a, (bc)
	ld	(hl), a
	inc	hl
	inc	bc
	or	a, a
	jr	nz, .printk_loop
; last check
	ex	de, hl
	or	a, a
	sbc	hl, de
	jr	c, .printk_buffer_free1
	lea	de, ix+3
.printk_buffer_free1:
	ld	(ix), de
	tstei
	ret


demsg:
;***************************************************************
;* Use this to display information stored by printk.
;***************************************************************
	ld	ix, KERNEL_MESSAGE_BUFFER_ADDRESS
	ld	bc, (ix)
	lea	de, ix+3
	add	ix,bc
	lea	hl,ix+0
	xor	a, a
	cp	a, (hl)
	jr	z, .buffer_not_full
	ld	bc, KERNEL_MESSAGE_BUFFER_END
.loop_for_next_0B:
	inc	hl
	push	hl
	or	a, a
	sbc	hl,bc
	pop	hl
	jr	c, .noproblemo
	sbc	hl,hl
	add	hl,de
.noproblemo:
	cp	a, (hl)
	jr	nz, .loop_for_next_0B
	inc	hl
.loop:
	ld	a, (hl)
; DO SOMETHING ACCORDING TO THE MESSAGE TYPE VALUE
;	-> different colors ?
	inc	hl
	push	de
	push	ix
;	call	displaySTR ; à remplacer -> système de feed avec la console ? (faire attention, le buffer est circulaire)
	pop	ix
	pop	de
	inc	hl
	push	hl
	lea	de,ix+0
	or	a, a
	sbc	hl,de
	pop	hl
	jr	nz, .loop
	ret

.buffer_not_full:
	ld	bc, KERNEL_MESSAGE_BUFFER_END
.loop_for_next_non0B:
	inc	hl
	push	hl
	or	a, a
	sbc	hl,bc
	pop	hl
	jr	c, .noproblemo2
	sbc	hl,hl
	add	hl,de
.noproblemo2:
	cp	a, (hl)
	jr	z, .loop_for_next_non0B
	jr	.loop
