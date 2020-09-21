; RAM reallocated routine for PIC code in library and user process and most essentially XIP
; see doc in doc/pic

; swap interrupt and all shadow in 12 cycles
macro	exxi
	if defined SWAP
		ex	af, af'
		exx
		ei	
	restore SWAP
	else
		di
		exx
		ex	af, af'
	define SWAP 1
	end if
end	macro

; call [cc,] (plt+offset)
__sorcery_extern_call_cc:
	exxi
	pop	hl
	ld	de, (hl)
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	push	hl
	ex	de, hl
; bc' is the base .data section with plt table at negative offset
	add	hl, bc
	push	hl
	exxi
	ret

; call [cc,] (pc+offset)
__sorcery_relative_call_cc:
	exxi
	pop	hl
	ld	de, (hl)
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	push	hl
	add	hl, de
	push	hl
	exxi
	ret

; jp [cc,] (pc+offset)
__sorcery_relative_jp_cc:
	exxi
	pop	hl
	ld	de, (hl)
	add	hl, de
	push	hl
	exxi
	ret
	
; C optimized version wich does framesetting in same time (and destroy for that both hl & ix)
; you need to pop ix before ret in the calledd routine, as per C standard
; call frameset0 is a NOP, call _frameset should do add hl,sp / ld sp, hl
__sorcery_extern_call_C:
	ex	(sp), ix
	lea	hl, ix+4
	ex	(sp), hl
	push	hl
; grab the offset and add the plt base (bc')
	ld	ix, (ix+0)
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
	ex	de, hl
; get the offset and add it to the pc
	ld	de, (ix+0)
	add	ix, de
	ex	de, hl
	lea	hl, ix+0
	ld	ix, 0
	add	ix, sp
	jp	(hl)
