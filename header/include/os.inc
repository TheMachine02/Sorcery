; ----------------------

macro os_private
	local os
	element os.base

 	postpone
		os.size = $% - os.start_off
		os.end = os.size + $20000
	end postpone

 	macro os_rom?
		os.start = $
		os.start_off = $%
		org $20000
	end macro
	
	macro os_create?
		di
		call	.create
		rst	0
	.create:
		call	.unlock
		
		ld	a,$02
	.erase:
		push	af
		call	.sectorerase
		pop	af
		inc	a
		cp	a,$0C
		jr	nz,.erase

		ld	hl,os.start
		ld	de,$20000
		ld	bc,os.size
		call	$2e0

		call	.lock
		xor	a,a
		ret

	.sectorerase:
		ld	bc, $f8
		push	bc
		jp	$2dc

	.unlock:
		ld	bc, $24
		ld	a, $8c
		call	.write
		ld	bc, $06
		call	.read
		or	a, 4
		call	.write
		ld	bc, $28
		ld	a, $4
		jp	.write
	.lock:
		ld	bc, $28
		xor	a, a
		call	.write
		ld	bc, $06
		call	.read
		res	2, a
		call	.write
		ld	bc, $24
		ld	a, $88
		jp	.write
	.write:
		ld	de, $C979ED
		ld	hl, $D1887C - 3
		ld	(hl), de
		jp	(hl)
	.read:
		ld	de, $C978ED
		ld	hl, $0D1887C - 3
		ld	(hl), de
		jp	(hl)
	end macro
	
end macro

; ----------------------

os_private
purge os_private
