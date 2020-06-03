define	KERNEL_INFO			1
define	KERNEL_WARNING		2
define	KERNEL_ERROR		4

define	BUFFER_SIZE			0x000800 ; 2048
define	BUFFER_ADDR			0xD20000 ; à changer

; The first three bytes of the tmpfs file stand for the offset of the next location to write a kernel message.


init_printk:
	; il faut initialiser un espace mémoire rempli de 0 de taille BUFFER_SIZE pour écrire les messages à l'interieur

printk:
	;***************************************************************
	;* INPUT
	;*	- A : Kernel message type :
	;*			KERNEL_INFO, KERNEL_WARNING or KERNEL_ERROR.
	;*	- BC : address of the 0-terminated string.
	;* OUTPUT
	;*	- A and the message pointed by HL are copied into BUFFER_ADDR (circularly).
	;***************************************************************
	push bc
	ld ix,BUFFER_ADDR
	ld hl,(ix)
	lea de,ix+0
	add hl,de
	ex de,hl
	ld bc,BUFFER_SIZE
	add hl,bc
	pop bc
	ex de,hl

	ld (hl),a
	inc hl
.mainloop:
	push hl
	or a
	sbc hl,de
	pop hl
	jq c,.noproblemo
	lea hl,ix+3
.noproblemo:
	ld a,(bc)
	ld (hl),a
	inc hl
	inc bc
	or a
	jq nz,.mainloop
	; last check
	ex de,hl
	or a
	sbc hl,de
	jq c,.noproblemo2
	lea de,ix+3
.noproblemo2:
	ld (ix),de
	ret


demsg:
	;***************************************************************
	;* Use this to display information stored by printk.
	;***************************************************************
	ld ix,BUFFER_ADDR
	ld bc,(ix)
	lea de, ix+3
	add ix,bc
	lea hl,ix+0
	xor a
	cp (hl)
	jq z,.buffer_not_full

	ld bc,BUFFER_ADDR+BUFFER_SIZE
.loopingForNext0B:
	inc hl
	push hl
	or a
	sbc hl,bc
	pop hl
	jq c,.noproblemo
	sbc hl,hl
	add hl,de
.noproblemo:
	cp (hl)
	jq nz,.loopingForNext0B
	inc hl

.display_loop:
	ld a,(hl)
	; DO SOMETHING ACCORDING TO THE MESSAGE TYPE VALUE
	;	-> different colors ?
	inc hl
	push de
	push ix
	call displaySTR ; à remplacer -> système de feed avec la console ? (faire attention, le buffer est circulaire)
	pop ix
	pop de

	inc hl
	push hl
	lea de,ix+0
	or a
	sbc hl,de
	pop hl
	jq nz,.display_loop
	ret

.buffer_not_full:
	; A=0
	ld bc,BUFFER_ADDR+BUFFER_SIZE
.loopingForNextNon0B:
	inc hl
	push hl
	or a
	sbc hl,bc
	pop hl
	jq c,.noproblemo2
	sbc hl,hl
	add hl,de
.noproblemo2:
	cp (hl)
	jq z,.loopingForNextNon0B
	jq .display_loop
