dzx7t:
.uncompress:
; Routine copied from the C toolchain & speed optimized
;  Input:
;   HL = compressed data pointer
;   DE = output data pointer
	ld	a, 128
.copy_byte_loop:
	ldi
.main_loop:
	add	a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
	rla
	jr nc, .copy_byte_loop
	push	de
	ld	de, 0
	ld	bc, 1
.len_size_loop:
	inc	d
	add	a, a
 	jr	nz,$+5
	ld	a,(hl)
	inc	hl
	rla
   	jr	nc, .len_size_loop
	jr	.len_value_start
.len_value_loop:
	add     a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
    rla
    rl   c
    rl   b
    jr   c, .exit        ; check end marker
.len_value_start:
    dec     d
    jr      nz, .len_value_loop
    inc     bc             ; adjust length
; determine offset
    ld      e, (hl)           ; load offset flag (1 bit) + offset value (7 bits)
    inc     hl
    sla e
    inc e
    jr      nc, .offset_end    ; if offset flag is set, load 4 extra bits
    add     a, a              ; check next bit
    jr nz,$+5
	ld a,(hl)
	inc hl
	rla
    rl      d              ; insert first bit into D
    add     a, a              ; check next bit
 	jr nz,$+5
	ld a,(hl)
	inc hl
	rla
    rl      d              ; insert second bit into D
    add     a, a              ; check next bit
 	jr nz,$+5
	ld a,(hl)
	inc hl
	rla
    rl      d              ; insert third bit into D
    add     a, a              ; check next bit
 	jr nz,$+5
	ld a,(hl)
	inc hl
	rla
    ccf
    jr  c, .offset_end
    inc d              ; equivalent to adding 128 to DE
.offset_end:
    rr      e              ; insert inverted fourth bit into E
; copy previous sequence
    ex      (sp), hl          ; store source, restore destination
    push    hl             ; store destination
    sbc     hl, de            ; HL = destination - offset - 1
    pop     de             ; DE = destination
    ldir
.exit:
    pop     hl             ; restore source address (compressed data)
    jr      nc, .main_loop
    ret

 
