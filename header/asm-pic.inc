; RAM reallocated routine for runtime virtual to physical translation, code in library and user process and most essentially XIP
; see doc in doc/pic

macro call argcc, argpc
	match (=PC?+d), argcc
		call	__sorcery_relative_call_cc
		jp	d
	else match (=$+d), argcc
		call	__sorcery_relative_call_cc
		jp	d	
	else
		match (=PC?+d), argpc
			call	argcc, __sorcery_relative_call_cc
			jp	argcc, d
		else match (=$+d), argpc
			call	argcc, __sorcery_relative_call_cc
			jp	argcc, d
		else
			call	argcc, argpc
		end match
	end match
end macro

macro jp argcc, argpc
	match (=PC?+d), argcc
		call	__sorcery_relative_jp_cc
		jp	d+3
	else  match (=$?+d), argcc
		call	__sorcery_relative_jp_cc
		jp	d+3
	else
		match (=PC?+d), argpc
			call	argcc, __sorcery_relative_jp_cc
			jp	argcc, d+3
		else match (=$?+d), argpc
			call	argcc, __sorcery_relative_jp_cc
			jp	argcc, d+3
		else
			jp	argcc, argpc
		end match
	end match
end macro

; extern symbol call. Expect bc' as the base data adress, given negative offset

; call [cc,] (plt+offset)
__sorcery_extern_call_cc:
	di
	exx
	ex	af, af'
	pop	hl
	inc	hl
	ld	de, (hl)
	inc	hl
	inc	hl
	inc	hl
	push	hl
	ex	de, hl
; bc' is the base .data section with plt table at negative offset
	add	hl, bc
	push	hl
	ex	af, af'
	exx
	ei
	ret

; jp [cc,] (plt+offset)
__sorcery_extern_jp_cc:
	di
	exx
	ex	af, af'
	pop	hl
	inc	hl
	ld	hl, (hl)
	add	hl, bc
	push	hl
	ex	af, af'
	exx
	ei
	ret
	
; In section call and jp. For intersection or library call, see plt
	
; call [cc,] (pc+offset)
__sorcery_relative_call_cc:
	di
	exx
	ex	af, af'
	pop	hl
	inc	hl
	ld	de, (hl)
	inc	hl
	inc	hl
	inc	hl
	push	hl
	add	hl, de
	push	hl
	ex	af, af'
	exx
	ei
	ret

; jp [cc,] (pc+offset)
__sorcery_relative_jp_cc:
	di
	exx
	ex	af, af'
	pop	hl
	inc	hl
	ld	de, (hl)
	add	hl, de
	push	hl
	ex	af, af'
	exx
	ei
	ret
	
; C optimized version wich does framesetting in same time (and destroy for that both hl & ix & de)
; you need to pop ix before ret in the calledd routine, as per C standard
; call frameset0 is a NOP, call _frameset should do add hl,sp / ld sp, hl
__sorcery_extern_call_C:
	ex	(sp), ix
	lea	hl, ix+4
	ex	(sp), hl
	push	hl
; grab the offset and add the plt base (bc')
	ld	ix, (ix+1)
	exx
	add	ix, bc
	exx
	lea	hl, ix+0
	ld	ix, 0
	add	ix, sp
	jp	(hl)

; jump to a C function, with ix framesetting
; de, hl, ix can be destroyed
__sorcery_extern_jp_C:
	ex	(sp), ix
	ld	ix, (ix+1)
	exx
	add	ix, bc
	exx
	lea	hl, ix+0
	ld	ix, 0
	add	ix, sp
	jp	(hl)	
	
; stack : pc+4, ix, ix = sp, jp (pc)+offset
; stack : pc
__sorcery_relative_call_C:
	ex	(sp), ix
; ix = pc, stack = ix
	lea	hl, ix+4
; push back the return adress on stack
	ex	(sp), hl
; push ix back
	push	hl
; now ix and hl are free
; get the offset and add it to the pc
	ld	de, (ix+1)
	lea	hl, ix+0
	add	hl, de
	ld	ix, 0
	add	ix, sp
	jp	(hl)
	
__sorcery_relative_jp_C:
	ex	(sp), ix
	ld	de, (ix+1)
	lea	hl, ix+0
	add	hl, de
	ld	ix, 0
	add	ix, sp
	jp	(hl)
	
