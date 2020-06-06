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
; - decompresses files, packed with lz4 command line tool, preferably with options -Sx -B4
; input parameters:
; HL - pointer to the buffer with compressed source data
; DE - pointer to the destination buffer for decompressed data
; on exit:
; A  - contains exit code: 
; 	0 - decompression successful
;	1 - compressed size is bigger than 64kb
;	2 - unsupported version of lz4 compression format
; HL - the number of decompressed bytes
; Contents of AF,BC,DE,HL are not preserved.
; LZ4_decompress_raw
; - decompresses raw LZ4 compressed data 
; input parameters:
; HL - pointer to the buffer with compressed source data
; DE - pointer to the destination buffer for decompressed data
; BC - size of the compressed data
; on exit:
; A  - exit code: 
; 	0 - decompression successful
; HL - the number of decompressed bytes

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
; check if compressed size is in 24 bits
	ld	a, (hl)
	or	a, a
	jr	nz, .decompress_error
	inc	hl

; decompress raw lz4 data packet
; on entry hl - start of packed buffer, de - destination buffer, bc - size of packed data
.decompress_raw:
	push	de							; store original destination pointer
	push	hl							; store start of compressed data source
	add	hl, bc       				; calculate end address of compressed block
	push	hl							; move end address of compressed data to bc
	pop	bc	
	pop	hl							; restore start of compressed data source
	push	bc							; store end address of compessed data
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
; calculate total literal size by adding contents of following bytes
	push	de							; store destination
	ex	de, hl
; a = size of literal to copy, de=pointer to data to be added
	sbc	hl, hl
	ld	l, a			; set hl with size of literal to copy 
.calc_loop:
	ld	a, (de)						; get additional literal size to add 
	inc	de
	ld	c, a							; set bc to the length of literal
	add	hl, bc						; add it to the total literal length
	inc	a						; if literal=255
	jr	z, .calc_loop				; continue calculating the total literal size
; store total literal size to copy in bc
	push	hl
	pop	bc	
	ex	de, hl						; hl now contains current compressed data pointer  
	pop	de							; restore destination to de 
.copy_literals:
	ldir								; copy literal to destination
.skip_calc:
; check for end of compressed data
	pop	af
	pop	bc							; restore end address of compressed data 
	sbc	hl, bc						; check if we reached the end of compressed data buffer
	add	hl, bc
	jr	z, .decompress_success				; decompression finished
	push	bc							; store end address of compressed data

; Copy Matches
	and	a, $0F							; token can be max 15 - mask out unimportant bits. resets also c flag for sbc later
; get the offset
	inc.s	bc	; rest bcu
	ld	c, (hl)
	inc	hl
	ld	b, (hl)							; bc now contains the offset
	inc	hl
	push	hl							; store current compressed data pointer
	push	de							; store destination pointer

	ex	de, hl
	sbc	hl, bc   					; calculate from the offset the new decompressed data source to copy from
; hl contains new copy source, de source ptr
	ld	b, 0     					; load bc with the token
	ld	c, a
	cp	a, $0F							; if matchlength <15
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
	push	hl
	pop	bc		; store total matchlength to copy in bc
	pop	hl							; restore current decompressed data source
	pop	iy							; set stack to proper position by restoring destination pointer temporarily into af  
	ex	de, hl
	ex	(sp),hl						; update current compressed data pointer on the stack to the new value from de
	ex	de, hl 
	push	iy							; restore stack

.copy_matches:
	pop	de							; restore destination pointer
	inc	bc							; add base length of 4 to get the correct size of matchlength 
	inc	bc
	inc	bc
	inc	bc
	ldir								; copy match
	pop	hl							; restore current compressed data source
	jr	.get_token				; continue decompression
.decompress_success:
	pop	hl							; store destination pointer 
	sbc	hl, de						; calculate the number of decompressed bytes 
	xor	a, a							; clear exit code
	ret
