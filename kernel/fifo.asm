define	FIFO		$0
define	FIFO_HEAD	$0
define	FIFO_TAIL	$3
define	FIFO_SIZE	$6
define	FIFO_BOUND_UPP	$9
define	FIFO_BOUND_LOW	$C

define	FIFO_STRUCT_SIZE	15
; TODO : make it variable size
define	FIFO_MAX_SIZE		64

fifo:

.create:
; de is buffer
; iy is the fifo control structure
	ld	(iy+FIFO_BOUND_LOW), de
	ld	(iy+FIFO_HEAD), de
	ld	(iy+FIFO_TAIL), de
	ld	bc, FIFO_MAX_SIZE
	ld	hl, KERNEL_MM_NULL
	ldir
	ld	(iy+FIFO_BOUND_UPP), de
	ld	(iy+FIFO_SIZE), bc
	ret

.length:
	ld	hl, (iy+FIFO_HEAD)
	ld	bc, (iy+FIFO_TAIL)
	or	a, a
	sbc	hl, bc
	ret	nc
; if carry, tail > head, so length = (FIFO_BOUND_UPP - tail) + head- FIFO_BOUND_LOW
; = head - tail + FIFO_MAX_SIZE
	ld	bc, FIFO_MAX_SIZE
	add	hl, bc
	ret
	
.write:
; TODO : implement write from buffer, (de), bc is size
; a = char
; write a character in head of fifo
	ld	hl, (iy+FIFO_HEAD)
	ld	(hl), a
	ld	bc, (iy+FIFO_BOUND_UPP)
	inc	hl
	sbc	hl, bc
	add	hl, bc
	jr	nz, .write_rewind
	ld	hl, (iy+FIFO_BOUND_LOW)
.write_rewind:
	ld	(iy+FIFO_HEAD), hl
	ld	hl, (iy+FIFO_SIZE)
	ld	bc, FIFO_MAX_SIZE
	or	a, a
	sbc	hl, bc
	jr	z, .write_full
	add	hl, bc
	inc	hl
	ld	(iy+FIFO_SIZE), hl
	ret
.write_full:
	ld	hl, (iy+FIFO_HEAD)
	ld	(iy+FIFO_TAIL), hl
	ret

.read:
; iy is the fifo read, de is destination buffer, bc is size
	push	bc
.read_loop:
	ld	hl, (iy+FIFO_SIZE)
	ld	a, l
	or	a, h
	jr	z, .read_empty
	dec	hl
	ld	(iy+FIFO_SIZE), hl
	ld	hl, (iy+FIFO_TAIL)
	ldi
	push	af
	push	bc
	ld	bc, (iy+FIFO_BOUND_UPP)
	sbc	hl, bc
	add	hl, bc
	jr	nz, .read_rewind
	ld	hl, (iy+FIFO_BOUND_LOW)
.read_rewind:
	ld	(iy+FIFO_TAIL), hl
	pop	bc
	pop	af
; if po set, we have read all
	jp	pe, .read
	pop	hl
	ret
.read_empty:
; bc is our data left to be read
	pop	hl
	push	bc
	pop	hl
	ret
	
.flush:
; drain the fifo, make head = tail and set the value pointed to 0
	ld	hl, (iy+FIFO_HEAD)
	ld	(iy+FIFO_TAIL), hl
	ld	(iy+FIFO_HEAD), hl
	xor	a, a
	ld	(hl), a
	sbc	hl, hl
	ld	(iy+FIFO_SIZE), hl
	ret
