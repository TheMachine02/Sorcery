define	RING_BUFFER		$0
define	RING_BUFFER_HEAD	$0
define	RING_BUFFER_TAIL	$3
define	RING_BUFFER_SIZE	$6
define	RING_BUFFER_BOUND_UPP	$9
define	RING_BUFFER_BOUND_LOW	$C

define	RING_BUFFER_STRUCT_SIZE	12
define	RING_BUFFER_MAX_SIZE	1024-RING_BUFFER_STRUCT_SIZE

ring_buffer:

.create:
	lea	de, iy+RING_BUFFER_BOUND_LOW
	ld	(iy+RING_BUFFER_HEAD), de
	ld	(iy+RING_BUFFER_TAIL), de
	ld	bc, RING_BUFFER_MAX_SIZE
	ld	hl, KERNEL_MM_NULL
	ldir
	ld	(iy+RING_BUFFER_BOUND_UPP), de
	ld	(iy+RING_BUFFER_SIZE), bc
	ret

.length:
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	bc, (iy+RING_BUFFER_TAIL)
	or	a, a
	sbc	hl, bc
	ret	nc
; if carry, tail > head, so length = (RING_BUFFER_BOUND_UPP - tail) + head- RING_BUFFER_BOUND_LOW
; = head - tail + RING_BUFFER_MAX_SIZE
	ld	bc, RING_BUFFER_MAX_SIZE
	add	hl, bc
	ret
	
.increment:
	ld	bc, (iy+RING_BUFFER_BOUND_UPP)
	inc	hl
	or	a, a
	sbc	hl, bc
	add	hl, bc
	ret	nz
	lea	hl, iy+RING_BUFFER_BOUND_LOW
	ret

.decrement:
	lea	bc, iy+RING_BUFFER_BOUND_LOW
	scf
	sbc	hl, bc
	add	hl, bc
	ret	nc
	ld	hl, (iy+RING_BUFFER_BOUND_UPP)
	dec	hl
	ret

.write:
; ; a = char
; ; write a in head
; ; reset head value
; ; increment pointer
; ; check if full, else make head = tail
	call	.length
	ld	bc, (iy+RING_BUFFER_SIZE)
	or	a, a
	sbc	hl, bc
	jr	c, .update
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	(hl), a
	ld	bc, (iy+RING_BUFFER_BOUND_UPP)
	inc	hl
	xor	a, a
	sbc	hl, bc
	add	hl, bc
	jr	nz, .write_rewind
	lea	hl, iy+RING_BUFFER_BOUND_LOW
.write_rewind:
	ld	(hl), a
	ld	(iy+RING_BUFFER_HEAD), hl
	ld	hl, (iy+RING_BUFFER_SIZE)
; why single optimization break stuff ? dunno, to investigate
	ld	bc, RING_BUFFER_MAX_SIZE
	or	a, a
	sbc	hl, bc
	jr	z, .write_full
	add	hl, bc
	inc	hl
	ld	(iy+RING_BUFFER_SIZE), hl
	ret
.write_full:
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	(iy+RING_BUFFER_TAIL), hl
	ret
	
.update:
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	(hl), a
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	(hl), a
	ld	bc, (iy+RING_BUFFER_BOUND_UPP)
	inc	hl
	xor	a, a
	sbc	hl, bc
	add	hl, bc
	jr	nz, .update_rewind
	lea	hl, iy+RING_BUFFER_BOUND_LOW
.update_rewind:
	ld	(iy+RING_BUFFER_HEAD), hl
	ret
	
.read:
	ld	hl, (iy+RING_BUFFER_SIZE)
	ld	a, l
	or	a, h
	ret	z
	dec	hl
	ld	(iy+RING_BUFFER_SIZE), hl
	ld	hl, (iy+RING_BUFFER_TAIL)
	ld	a, (hl)
	ld	bc, (iy+RING_BUFFER_BOUND_UPP)
	inc	hl
	sbc	hl, bc
	add	hl, bc
	jr	nz, .read_rewind
	lea	hl, iy+RING_BUFFER_BOUND_LOW
.read_rewind:
	ld	(iy+RING_BUFFER_TAIL), hl
	ret

.flush:
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	bc, (iy+RING_BUFFER_BOUND_UPP)
	xor	a, a
	ld	(hl), a
	inc	hl
	sbc	hl, bc
	add	hl, bc
	jr	nz, .flush_rewind
	lea	hl, iy+RING_BUFFER_BOUND_LOW
.flush_rewind:
	ld	(iy+RING_BUFFER_TAIL), hl
	ld	(iy+RING_BUFFER_HEAD), hl
	ld	(hl), a
	or	a, a
	sbc	hl, hl
	ld	(iy+RING_BUFFER_SIZE), hl
	ret
	
.remove_head:
; suppr behaviour
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	a, (hl)
	or	a, a
	ret	z
	ld	bc, (iy+RING_BUFFER_BOUND_UPP)
	jr	.remove_collapse

.remove:
; backspace behaviour
	ld	hl, (iy+RING_BUFFER_HEAD)
	call	.decrement
	ld	a, (hl)
	or	a, a
	ret	z
	ld	(iy+RING_BUFFER_HEAD), hl
	ld	bc, (iy+RING_BUFFER_BOUND_UPP)
.remove_collapse:
	ex	de, hl
	sbc	hl, hl
	add	hl, de
	inc	hl
	sbc	hl, bc
	add	hl, bc
	jr	nz, .remove_rewind
	lea	hl, iy+RING_BUFFER_BOUND_LOW
.remove_rewind:
	ld	a, (hl)
	ld	(de), a
	or	a, a
	jr	nz, .remove_collapse
	ld	hl, (iy+RING_BUFFER_SIZE)
	dec	hl
	ld	(iy+RING_BUFFER_SIZE), hl
	cpl
	ret
