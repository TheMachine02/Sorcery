define	RING			$0
define	RING_HEAD		$0
define	RING_TAIL		$3
define	RING_SIZE		$6
define	RING_BOUND_UPP		$9
define	RING_BOUND_LOW		$C
define	RING_ENDPOINT		$F
define	RING_WRITE_OPEN		1
define	RING_READ_OPEN		2
define	RING_STRUCT_SIZE	16
define	RING_MAX_SIZE		256

ring:

.create:
; hl is buffer
; iy is the ring control structure
	ex	de, hl
	ld	(iy+RING_BOUND_LOW), de
	ld	(iy+RING_HEAD), de
	ld	(iy+RING_TAIL), de
	ld	bc, RING_MAX_SIZE
	ld	hl, KERNEL_MM_NULL
	ldir
	ld	(iy+RING_BOUND_UPP), de
	ld	(iy+RING_SIZE), bc
	ld	(iy+RING_ENDPOINT), c
	ret

.length:
	ld	hl, (iy+RING_HEAD)
	ld	bc, (iy+RING_TAIL)
	or	a, a
	sbc	hl, bc
	ret	nc
; if carry, tail > head, so length = (RING_BOUND_UPP - tail) + head- RING_BOUND_LOW
; = head - tail + RING_MAX_SIZE
	ld	bc, RING_MAX_SIZE
	add	hl, bc
	ret
	
.write:
; iy is the ring read, de is source buffer, bc is size
	push	bc
.write_loop:
	push	bc
	ld	hl, (iy+RING_SIZE)
	ld	bc, RING_MAX_SIZE
	or	a, a
	sbc	hl, bc
	jr	z, .write_full
	add	hl, bc
	inc	hl
.write_size:
	ld	(iy+RING_SIZE), hl
	ld	hl, (iy+RING_HEAD)
	ld	a, (de)
	ld	(hl), a
	inc	de
	inc	hl
	ld	bc, (iy+RING_BOUND_UPP)
	or	a, a
	sbc	hl, bc
	add	hl, bc
	jr	nz, .write_rewind
	ld	hl, (iy+RING_BOUND_LOW)
.write_rewind:
	ld	(iy+RING_HEAD), hl
	pop	bc
	cpi
	jp	pe, .write_loop
	pop	hl
	ret
.write_full:
	ld	hl, (iy+RING_TAIL)
	inc	hl
	ld	bc, (iy+RING_BOUND_UPP)
	or	a, a
	sbc	hl, bc
	add	hl, bc
	jr	nz, .write_tail_rewind
	ld	hl, (iy+RING_BOUND_LOW)
.write_tail_rewind:
	ld	(iy+RING_TAIL), hl
	ld	hl, RING_MAX_SIZE
	jr	.write_size

.read:
; iy is the ring read, de is destination buffer, bc is size
	push	bc
.read_loop:
	ld	hl, (iy+RING_SIZE)
	ld	a, l
	or	a, h
	jr	z, .read_empty
	dec	hl
	ld	(iy+RING_SIZE), hl
	ld	hl, (iy+RING_TAIL)
	ldi
	push	af
	push	bc
	ld	bc, (iy+RING_BOUND_UPP)
	or	a, a
	sbc	hl, bc
	add	hl, bc
	jr	nz, .read_rewind
	ld	hl, (iy+RING_BOUND_LOW)
.read_rewind:
	ld	(iy+RING_TAIL), hl
	pop	bc
	pop	af
; if po set, we have read all
	jp	pe, .read_loop
	pop	hl
	ret
.read_empty:
; bc is our data left to be read
	pop	hl
	sbc	hl, bc
	ret

.flush:
; drain the ring, make head = tail and set the value pointed to 0
	ld	hl, (iy+RING_HEAD)
	ld	(iy+RING_TAIL), hl
	xor	a, a
	ld	(hl), a
	sbc	hl, hl
	ld	(iy+RING_SIZE), hl
	ret
