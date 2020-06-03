include 'include/ez80.inc'
include 'include/asm-elf.inc'

elf ELF_SO

section .jump, ELF_RW_INSTR
	jp	draw_black

section .text, ELF_RW_INSTR
draw_black:
	ld	de, ($E30014)
	ld	bc, 320*26
	ld	hl, $E40000
	ldir
	ret
