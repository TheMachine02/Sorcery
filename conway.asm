	call	video.irq_lock
	ld hl,$E40000
	ld de,$D40000
	ld bc,$025800
	ldir
	ld hl,$D40000
	ld ($E30010), hl
	
	ld hl,$010101
	ld a,l
	ld ($D4BD3C),a
	ld ($D4BD40),hl
	ld ($D4BDE2),hl
	ld ($D4BDE7),a
	ld ($D4BE89),a
	ld hl, __D1A8BA
	ld de,$E30800
	ld bc,1024
	ldir
	jp $E30800

__D1A8BA:
	ld hl,$E00105
	ld (hl),h
	ld hl,$FFFFFF
	ld ($E30200),hl
	inc hl
	ld ($E3021E),hl
	ld a,$25
	ld ($E30018),a
	di 
	push ix
	push iy
	ld ($E30B17),sp
	ld sp,$D5C80D
	or a,a
	sbc hl,hl
	ld b,$36
D1A8E5:
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5
	djnz D1A8E5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	
	ld sp,166
	ld hl,$D49600
	ld de,$D577A7
	ld ixh,$7C

D1A9AD:
	ld b,$52
	ld a,(hl)
	inc hl
D1A9B1:
	add a,(hl)
	inc hl
	add a,(hl)
	add hl,sp
	add a,(hl)
	dec hl
	ld c,(hl)
	dec hl
	add a,(hl)
	add hl,sp
	add a,(hl)
	inc hl
	add a,c
	jr z,D1A9CD
	sub a,c
	add a,(hl)
	inc hl
	add a,(hl)
	dec hl
	or a,c
	cp a,$03
	jr nz,D1A9CC
	rra 
	ld (de),a
D1A9CC:
	ld a,c
D1A9CD:
	inc de
	add a,(hl)
	inc hl
	add a,(hl)
	inc hl
	add a,(hl)
	sbc hl,sp
	add a,(hl)
	dec hl
	ld c,(hl)
	sbc hl,sp
	add a,(hl)
	add a,c
	jr z,D1A9ED
	sub a,c
	dec hl
	add a,(hl)
	inc hl
	inc hl
	add a,(hl)
	or a,c
	cp a,$03
	jr nz,D1A9EB
	rra 
	ld (de),a
D1A9EB:
	dec hl
	ld a,(hl)
D1A9ED:
	inc hl
	inc de
	djnz D1A9B1
	inc hl
	inc de
	inc de
	dec ixh
	jr nz,D1A9AD

	ld de,$D578F5
	ld sp,$0000A0
	ld hl,$D40000
	ld bc,$000078
D1AA08:
	ld b,$A0
D1AA0A:
	ld a,(de)
	inc de
	dec a
	ld (hl),a
	inc hl
	djnz D1AA0A
	inc de
	inc de
	inc de
	inc de
	inc de
	inc de
	add hl,sp
	dec c
	jr nz,D1AA08

	ld sp,$000140
	ld a,$78
	ld hl,$D40000
	ld de,$D400A0
D1AA29:
	ld c,$A0
	ldir 
	add hl,sp
	ex de,hl
	dec a
	jr nz,D1AA29
	
	ld sp,$D4E70D
	or a,a
	sbc hl,hl
	ld b,$36
D1AA3B:
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5
	djnz D1AA3B
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5
	dl	$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5,$e5e5e5

	ld sp,$0000A6
	ld hl,$D57700
	ld de,$D496A7
	ld ixh,$7C

D1AB03:
	ld b,$52
	ld a,(hl)
	inc hl
D1AB07:
	add a,(hl)
	inc hl
	add a,(hl)
	add hl,sp
	add a,(hl)
	dec hl
	ld c,(hl)
	dec hl
	add a,(hl)
	add hl,sp
	add a,(hl)
	inc hl
	add a,c
	jr z,D1AB23
	sub a,c
	add a,(hl)
	inc hl
	add a,(hl)
	dec hl
	or a,c
	cp a,$03
	jr nz,D1AB22
	rra 
	ld (de),a
D1AB22:
	ld a,c
D1AB23:
	inc de
	add a,(hl)
	inc hl
	add a,(hl)
	inc hl
	add a,(hl)
	sbc hl,sp
	add a,(hl)
	dec hl
	ld c,(hl)
	sbc hl,sp
	add a,(hl)
	add a,c
	jr z,D1AB43
	sub a,c
	dec hl
	add a,(hl)
	inc hl
	inc hl
	add a,(hl)
	or a,c
	cp a,$03
	jr nz,D1AB41
	rra 
	ld (de),a
D1AB41:
	dec hl
	ld a,(hl)
D1AB43:
	inc hl
	inc de
	djnz D1AB07
	inc hl
	inc de
	inc de
	dec ixh
	jr nz,D1AB03


	ld de,$D497F5
	ld sp,$0000A0
	ld hl,$D40000
	ld bc,$000078
D1AB5E:
	ld b,$A0
D1AB60:
	ld a,(de)
	inc de
	dec a
	ld (hl),a
	inc hl
	djnz D1AB60
	inc de
	inc de
	inc de
	inc de
	inc de
	inc de
	add hl,sp
	dec c
	jr nz,D1AB5E


	ld sp,$000140
	ld a,$78
	ld hl,$D40000
	ld de,$D400A0
D1AB7F:
	ld c,$A0
	ldir 
	add hl,sp
	ex de,hl
	dec a
	jr nz,D1AB7F

	or	a, a
	sbc	hl, hl
	add	hl, sp
	ld	sp, ($E30B17)
	push	hl
	ei
	call	video.vsync
; we are pid 1, wait on all children to be reaped
	ld	hl, -1
	ld	bc, 0
	ld	de, WNOHANG
	call	_waitpid
	di
	pop	hl
	ld	($E30B17), sp
	ld	sp, hl
	
	ld	hl,$F5001C
	bit	6,(hl)
	jp	z,$E30822

	ld hl,$D49600
	ld de,$D657FF
D1ABA3:
	dec hl
	ld a,(hl)
	cpl 
	ld (de),a
	dec de
	ld (de),a
	dec de
	ld (de),a
	dec de
	ld (de),a
	dec de
	ld a,h
	or a,l
	jr nz,D1ABA3
	ld sp,$000000
	pop iy
	pop ix
	ei
	ret
