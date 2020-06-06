;
; LZ4 decompression algorithm - Copyright (c) 2011-2015, Yann Collet
; All rights reserved. 
; LZ4 implementation for z80 and compatible processors - Copyright (c) 2013-2015 Piotr Drapich
; All rights reserved.
;
; Redistribution and use in source and binary forms, with or without modification, 
; are permitted provided that the following conditions are met: 
; 
; * Redistributions of source code must retain the above copyright notice, this 
;   list of conditions and the following disclaimer. 
; 
; * Redistributions in binary form must reproduce the above copyright notice, this 
;   list of conditions and the following disclaimer in the documentation and/or 
;   other materials provided with the distribution. 
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
; DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR 
; ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES 
; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON 
; ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 

; Ported to ez80 by TheMachine02

; Available functions:
; LZ4_decompress
; - decompresses files, packed with lz4
; input parameters:
; HL - pointer to the buffer with compressed source data
; DE - pointer to the destination buffer for decompressed data
; on exit:
; A  - contains exit code: 
; 	0 - decompression successful
;	2 - unsupported version of lz4 compression format
; Contents of AF,BC,DE,HL are not preserved.

define	LZ4_VERSION4		4
define	LZ4_VERSION3		3
define	LZ4_VERSION2		2

lz4:

.decompress:
; check the magic number
	ld	bc, 0
	ld	a, (hl)
	cp	a, LZ4_VERSION4
	jr	z, .version_4
	cp	a, LZ4_VERSION3
	jr	z, .version_3_legacy
	cp	a, LZ4_VERSION2
	jr	z, .version_2_legacy
.version_not_supported:
	ld	a,2
	jr	.decompress_finished
.decompress_error:
	ld	a, 1
.decompress_finished:
	ret
.version_4:
; check version 1.41 magic 
	inc	hl
	ld	a, (hl)
	inc	hl
	cp	a, $22
	jr	nz, .version_not_supported
	ld	a, (hl)
	inc	hl
	cp	a, $4D
	jr	nz, .version_not_supported
	ld	a, (hl)
	inc	hl
	cp	a, $18
	jr	nz, .version_not_supported
; parse version 1.41 spec header
	ld	a, (hl)
	inc	hl
; check version bits for version 01
	bit	7, a
	jr	nz, .version_not_supported
	bit	6, a
	jr	z, .version_not_supported
; is content size set?
	bit	3, a
	jr	z, .no_content_size
; skip content size
	ld	c, 8
.no_content_size:
	bit	0, a
	jr	z, .no_preset_dictionary
; skip dictionary id
	inc	c
	inc	c
	inc	c
	inc	c
.no_preset_dictionary:
	ld	a, (hl)
	inc	hl
; strip reserved bits (and #70) and check if block max size is set to 64kb (4)
	and	$40
	jr	z, .version_not_supported
; skip header checksum
	inc	bc
	jr	.start_decompression
.version_3_legacy:
	ld	c, 8
.version_2_legacy:
	inc	hl
	ld	a, (hl)
	inc	hl
	cp	$21
	jr	nz, .version_not_supported
	ld	a, (hl)
	inc	hl
	cp	$4c
	jr	nz, .version_not_supported
	ld	a, (hl)
	inc	hl
	cp	$18
	jr	nz, .version_not_supported
.start_decompression:
	add	hl, bc
; load low 24 bit of compressed block size to bc
	ld	bc, (hl)
	inc	hl
	inc	hl
	inc	hl
	inc	hl

; decompress raw lz4 data packet
; on entry hl - start of packed buffer, de - destination buffer, bc - size of packed data
.decompress_raw:
	push	de
	ex	(sp), ix
	push	hl							; store start of compressed data source
	add	hl, bc       				; calculate end address of compressed block
	ex	hl, (sp)
	ld	bc, 0
; get decompression token
.get_token:
	xor	a, a 							; reset c flag for sbc later
	ld	a, (hl)						; read token
	inc	hl
	push	af							; store token
; unpack 4 high bits to get the length of literal
	rlca
	rlca
	rlca
	rlca
; copy literals
	and	a, $0F							; token can be max 15 - mask out unimportant bits
	jr	z, .skip_calc   			; there is no literals, skip calculation of literal size
	ld	c, a							; set the count for calculation
	cp	a, $0F							; if literal size <15
	jr	nz, .copy_literals		; copy literal, else
; ; calculate total literal size by adding contents of following bytes
	ex	de, hl
; ; a = size of literal to copy, de=pointer to data to be added
	sbc	hl, hl
	ld	l, a			; set hl with size of literal to copy 
.calc_loop:
	ld	a, (de)						; get additional literal size to add 
	inc	de
	ld	c, a							; set bc to the length of literal
	add	hl, bc						; add it to the total literal length
	inc	a						; if literal=255
	jr	z, .calc_loop				; continue calculating the total literal size
; ; store total literal size to copy in bc
	push	hl
	pop	bc	
	ex	de, hl						; hl now contains current compressed data pointer  
.copy_literals:
	lea	de, ix+0
	add	ix, bc
	ldir								; copy literal to destination
.skip_calc:
; check for end of compressed data
	pop	af
	pop	de							; restore end address of compressed data 
	sbc	hl, de						; check if we reached the end of compressed data buffer
	add	hl, de
	jr	z, .decompress_success				; decompression finished
	push	de							; store end address of compressed data
; Copy Matches
	and	a, $0F							; token can be max 15 - mask out unimportant bits. resets also c flag for sbc later
; get the offset
	ld	c, (hl)
	inc	hl
	ld	b, (hl)							; bc now contains the offset
	inc	hl
	push	hl							; store current compressed data pointer
	lea	de, ix+0
	ex	de, hl
	sbc	hl, bc   					; calculate from the offset the new decompressed data source to copy from
; hl contains new copy source, de source ptr
	ld	b, 0     					; load bc with the token
	add	a, 4
	ld	c, a
	cp	a, $13							; if matchlength <15
	jr	nz, .copy_matches				; copy matches. else 

; calculate total matchlength by adding additional bytes
	push	hl							; store current decompressed data source
; a = size of match to copy, de= pointer to data to be added
	sbc	hl, hl     					; set hl with initial matchlength to copy
	ld	l, a
.calc_loop2:
	ld	a, (de)						; get additional matchlength to add
	inc	de
	ld	c, a							; set bc to the matchlength
	add	hl, bc						; add it to the total match length
	inc	a						; if matchlength=255
	jr	z, .calc_loop2				; continue calculating the total match length		
	ex	(sp), hl
	pop	bc		; store total matchlength to copy in bc ; restore current decompressed data source
	ex	de, hl
	ex	(sp),hl						; update current compressed data pointer on the stack to the new value from de
	ex	de, hl 
.copy_matches:
	lea	de, ix+0
	add	ix, bc
	ldir								; copy match
	pop	hl							; restore current compressed data source
	jr	.get_token				; continue decompression
.decompress_success:
	pop	ix
	xor	a, a							; clear exit code
	ret
