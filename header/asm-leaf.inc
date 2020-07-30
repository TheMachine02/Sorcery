
macro struct? name
	macro end?.struct?!
			end namespace
		end struc
		virtual at 0
			name name
			sizeof.name = $
		end virtual
		purge end?.struct?
	end macro
	struc name
		label . : sizeof.name
		namespace .
end macro

struct Leaf24_Shdr
	sh_name 	rl 1
	sh_type 	rb 1
	sh_flags	rb 1
	sh_addr 	rl 1
	sh_offset	rl 1
	sh_size 	rl 1
	sh_info 	rb 1
	sh_pad		rb 1
end struct

struct Leaf24_Sym
	st_name 	rl 1
	st_value	rl 1
	st_info 	rb 1
	st_shndx	rb 1
end struct

struct Leaf24_Rel
	r_offset	rl 1
	r_info		rl 1
end struct

purge struct?

define	LEAF_HEADER		0
define	LEAF_HEADER_IDENT	0	; 5 bytes
define	LEAF_IDENT		0	; start
define	LEAF_IDENT_MAG0		0	; $7F
define	LEAF_IDENT_MAG1		1	; 'L'
define	LEAF_IDENT_MAG2		2	; 'E'
define	LEAF_IDENT_MAG3		3	; 'A'
define	LEAF_IDENT_MAG4		4	; 'F'
define	LEAF_HEADER_TYPE	5	; 1 byte, LT_EXEC
define	LEAF_HEADER_MACHINE	6	; 1 byte, default, LM_EZ80_ADL
define	LEAF_HEADER_FLAGS	7	; 1 byte (most if reallocatable or static + specific)
define	LEAF_HEADER_ENTRY	8	; 3 bytes, symbol
define	LEAF_HEADER_SHOFF	11	; 3 bytes, section offset in file (usually at the end)
define	LEAF_HEADER_SHNUM	14	; 1 bytes, number of section
define	LEAF_HEADER_SHSTRNDX	15	; 1 bytes, string section index

; header is 16 bytes

define	LEAF_SECTION		0
define	LEAF_SECTION_NAME	0	; 3 bytes, offset into the str table
define	LEAF_SECTION_TYPE	3	; 1 byte, type
define	LEAF_SECTION_FLAGS	4	; flags, 1 byte
define	LEAF_SECTION_ADDR	5	; virtual adress if static or symbol index if not (rel have symbol of the section they are reallocating)
define	LEAF_SECTION_OFFSET	8	; offset in file 
define	LEAF_SECTION_SIZE	11	; size of the section
define	LEAF_SECTION_INFO	14	; useless
define	LEAF_SECTION_PAD	15	; pad to 16 bytes

; relocation, 6 bytes ;
define	LEAF_REL		0
define	LEAF_REL_OFFSET		0	; offset within section of the data to realloc (rel section are section defined with INFO
define	LEAF_REL_INFO		3	; more info (symbol index)

; if SHN_ABS : do (OFFSET) = symbol_value + (OFFSET)
; if SHN_UNDEF, it is extern

; symbol structure, 8 bytes
define	LEAF_SYMBOL		0
define	LEAF_SYMBOL_NAME	0	; 3 bytes, index is str table
define	LEAF_SYMBOL_VALUE	3	; 3 bytes, value : either 0 or offset in section
define	LEAF_SYMBOL_INFO	6	; 1 byte, type (func, global etc)
define	LEAF_SYMBOL_SHNDX	7	; 1 bytes, section index, 0 is UNDEF, 0xFF is SHN_ABS

;define	LEAF_ST_BIND(INFO)	((INFO) >> 4)
;define	LEAF_ST_TYPE(INFO)	((INFO) & $0F)

; machine
define	LM_EZ80_ADL		0
define	LM_EZ80_COMP		1
define	LM_Z80			2
; type
define	LT_NONE			0
define	LT_REL			1
define	LT_EXEC			2
define	LT_DYN			3
define	LT_CORE			4
; flags
define	LF_COMPRESSED		$1
define	LF_STATIC		$2
define	LF_REALLOC		$4
 
; section type
define	SHT_NULL		0
define	SHT_PROGBITS		1
define	SHT_SYMTAB		2
define	SHT_STRTAB		3
define	SHT_HASH		4
define	SHT_DYNAMIC		5
define	SHT_NOBITS		6
define	SHT_REL			7
define	SHT_INTERP		8

; section flags
define	SHF_WRITE		$1
define	SHF_ALLOC		$2
define	SHF_EXECINSTR		$4

; special section indexes
define	SHN_UNDEF		0
define	SHN_ABS			0xFF

define	STB_LOCAL		0
define	STB_GLOBAL		1
define	STB_WEAK		2

define	STT_NOTYPE		0
define	STT_OBJECT		1
define	STT_FUNC		2
define	STT_SECTION		3
define	STT_FILE		4
define	STT_COMMON		5
define	STT_TLS			6

R_Z80_NONE	= 0
R_Z80_8		= 1
R_Z80_8_DIS	= 2
R_Z80_8_PCREL	= 3
R_Z80_16	= 4
R_Z80_24	= 5
R_Z80_32	= 6
R_Z80_BYTE0	= 7
R_Z80_BYTE1	= 8
R_Z80_BYTE2	= 9
R_Z80_BYTE3	= 10
R_Z80_WORD0	= 11
R_Z80_WORD1	= 12

LEAF::

namespace LEAF
	if	defined LEAF.settings.machine
		MACHINE := LEAF.settings.machine
	else
		MACHINE := LM_EZ80_ADL
		assume ADL = 1
	end if
		
	if	defined LEAF.settings.flags
		FLAGS := LEAF.settings.flags
	else
		FLAGS := LF_REALLOC
	end if
	
	if	defined	LEAF.settings.type
		TYPE := LEAF.settings.type
	else
		TYPE := LT_EXEC
	end if
	
	Header:

	e_ident 	db 0x7F,'LEAF'
	e_type		db TYPE
	e_machine	db MACHINE
	e_flags		db FLAGS
	e_entry 	dl 0
	e_shoff 	dl SECTION_TABLE_OFFSET
	e_shnum 	db NUMBER_OF_SECTIONS
	e_shstrndx	db STRING_TABLE_SECTION_INDEX

	Content:

	virtual at 0
		section_table:: rb NUMBER_OF_SECTIONS * sizeof Leaf24_Shdr
	end virtual

	virtual at 0
		symbol_table:: rb NUMBER_OF_SYMBOLS * sizeof Leaf24_Sym
	end virtual

	virtual at 0
		string_table::
		_null db 0
		_symtab db '.symtab',0
		_strtab db '.strtab',0
		SECTION_NAME_POSITION = $
		rb SECTION_NAME_TABLE_SIZE - $
		STRING_POSITION = $
		rb STRING_TABLE_SIZE - $
	end virtual

	virtual at 0
		relocations:: rb NUMBER_OF_RELOCATIONS * sizeof Leaf24_Rel
	end virtual

	element relocatable?

	macro section_org
		local sym
		element sym : relocatable * SECTION_INDEX + SECTION_SYMBOL_INDEX
		SECTION_BASE = sym
		org sym
	end macro

	RELOCATION_INDEX = 0
	SECTION_INDEX = 1
	SECTION_SYMBOL_INDEX = SECTION_INDEX
	SECTION_RELOCATION_INDEX = RELOCATION_INDEX
	SYMBOL_INDEX = NUMBER_OF_SECTION_SYMBOLS

	SECTION_OFFSET = $%
	SECTION_NAME = '.flat'
	SECTION_FLAGS = SHF_ALLOC + SHF_WRITE + SHF_EXECINSTR
	DEFINED_SECTION = 0
	
	SECTION_STATIC_BASE = 0
	
	if LEAF.FLAGS = LF_REALLOC
		section_org
	else
		SECTION_STATIC_BASE=$
		org SECTION_STATIC_BASE
	end if
	
end namespace

macro entry? address*
	; store the symbol entry if not virtual
	namespace LEAF
		if LEAF.FLAGS = LF_REALLOC
			
		match value =as? str, address
			SYMBOL_VALUE = value
			SYMBOL_NAME = string str
		else
			SYMBOL_VALUE = address
			SYMBOL_NAME = `address
		end match

		if SYMBOL_VALUE relativeto 1 elementof SYMBOL_VALUE & 1 elementof (1 metadataof SYMBOL_VALUE) relativeto relocatable & 1 scaleof (1 metadataof SYMBOL_VALUE) > 0
			SYMBOL_SECTION_INDEX = 1 scaleof (1 metadataof SYMBOL_VALUE)
			SYMBOL_VALUE = SYMBOL_VALUE - 1 elementof SYMBOL_VALUE
		else
			SYMBOL_SECTION_INDEX = SHN_ABS
		end if
		store STRING_POSITION at symbol_table : Leaf24_Sym.st_name + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SYMBOL_NAME : lengthof SYMBOL_NAME at string_table:STRING_POSITION
		STRING_POSITION = STRING_POSITION + lengthof SYMBOL_NAME + 1
		store SYMBOL_VALUE at symbol_table : Leaf24_Sym.st_value + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SYMBOL_SECTION_INDEX at symbol_table : Leaf24_Sym.st_shndx + SYMBOL_INDEX * sizeof Leaf24_Sym
		store STT_FUNC + STB_GLOBAL shl 4 at symbol_table : Leaf24_Sym.st_info + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SYMBOL_INDEX at LEAF:e_entry
		SYMBOL_INDEX = SYMBOL_INDEX + 1
		else
			store address at LEAF:e_entry
		end if
	end namespace
end macro

macro section?
	namespace LEAF

		SECTION_SIZE = $% - SECTION_OFFSET

		if DEFINED_SECTION | SECTION_SIZE > 0

			store SECTION_OFFSET at section_table : Leaf24_Shdr.sh_offset + SECTION_INDEX * sizeof Leaf24_Shdr
			store SECTION_SIZE at section_table : Leaf24_Shdr.sh_size + SECTION_INDEX * sizeof Leaf24_Shdr
			store SECTION_FLAGS at section_table : Leaf24_Shdr.sh_flags + SECTION_INDEX * sizeof Leaf24_Shdr
			if FLAGS = LF_STATIC
				store SECTION_STATIC_BASE at section_table : Leaf24_Shdr.sh_addr + SECTION_INDEX * sizeof Leaf24_Shdr
			else	
				store SECTION_SYMBOL_INDEX at section_table : Leaf24_Shdr.sh_addr + SECTION_INDEX * sizeof Leaf24_Shdr
			end if

			if $%% = SECTION_OFFSET
				store SHT_NOBITS at section_table : Leaf24_Shdr.sh_type + SECTION_INDEX * sizeof Leaf24_Shdr
				section $
			else
				store SHT_PROGBITS at section_table : Leaf24_Shdr.sh_type + SECTION_INDEX * sizeof Leaf24_Shdr
				UNINITIALIZED_LENGTH = $% - $%%
				section $
				db UNINITIALIZED_LENGTH dup 0
			end if

			store 0 at symbol_table : Leaf24_Sym.st_value + SECTION_SYMBOL_INDEX * sizeof Leaf24_Sym
			store SECTION_INDEX at symbol_table : Leaf24_Sym.st_shndx + SECTION_SYMBOL_INDEX * sizeof Leaf24_Sym
			store STT_SECTION + STB_LOCAL shl 4 at symbol_table : Leaf24_Sym.st_info + SECTION_SYMBOL_INDEX * sizeof Leaf24_Sym

			if RELOCATION_INDEX > SECTION_RELOCATION_INDEX

				store RELOCATIONS_OFFSET + SECTION_RELOCATION_INDEX * sizeof Leaf24_Rel at section_table : Leaf24_Shdr.sh_offset + (SECTION_INDEX+1) * sizeof Leaf24_Shdr
				store (RELOCATION_INDEX - SECTION_RELOCATION_INDEX) * sizeof Leaf24_Rel at section_table : Leaf24_Shdr.sh_size + (SECTION_INDEX+1) * sizeof Leaf24_Shdr
				store SHT_REL at section_table : Leaf24_Shdr.sh_type + (SECTION_INDEX+1) * sizeof Leaf24_Shdr
				store SECTION_SYMBOL_INDEX at section_table : Leaf24_Shdr.sh_addr + (SECTION_INDEX+1) * sizeof Leaf24_Shdr

				store SECTION_NAME_POSITION at section_table : Leaf24_Shdr.sh_name + (SECTION_INDEX+1) * sizeof Leaf24_Shdr
				store SECTION_NAME_POSITION + 4 at section_table : Leaf24_Shdr.sh_name + SECTION_INDEX * sizeof Leaf24_Shdr
				store SECTION_NAME_POSITION + 4 at symbol_table : Leaf24_Sym.st_name + SECTION_SYMBOL_INDEX * sizeof Leaf24_Sym
				store '.rel' + SECTION_NAME shl (4*8) : 4 + lengthof (string SECTION_NAME) at string_table:SECTION_NAME_POSITION
				SECTION_NAME_POSITION = SECTION_NAME_POSITION + 4 + lengthof (string SECTION_NAME) + 1

				SECTION_INDEX = SECTION_INDEX + 2
				SECTION_SYMBOL_INDEX = SECTION_SYMBOL_INDEX + 1

			else
				store SECTION_NAME_POSITION at section_table : Leaf24_Shdr.sh_name + SECTION_INDEX * sizeof Leaf24_Shdr
				store SECTION_NAME_POSITION at symbol_table : Leaf24_Sym.st_name + SECTION_SYMBOL_INDEX * sizeof Leaf24_Sym
				store SECTION_NAME : lengthof (string SECTION_NAME) at string_table:SECTION_NAME_POSITION
				SECTION_NAME_POSITION = SECTION_NAME_POSITION + lengthof (string SECTION_NAME) + 1

				SECTION_INDEX = SECTION_INDEX + 1
				SECTION_SYMBOL_INDEX = SECTION_SYMBOL_INDEX + 1

			end if

		end if

	end namespace
end macro

macro section? declaration*
	namespace LEAF

		section

		DEFINED_SECTION = 1
		SECTION_FLAGS = SHF_ALLOC
		SECTION_OFFSET = $%
		SECTION_ALIGN = 1

		match name attributes, declaration

			SECTION_NAME = name

			local seq,list
			match flags =align? boundary, attributes
				SECTION_ALIGN = boundary
				define seq flags
			else match =align? boundary, attributes
				SECTION_ALIGN = boundary
				define seq
			else
				define seq attributes
			end match
			while 1
				match car cdr, seq
					define list car
					define seq cdr
				else
					match any, seq
						define list any
					end match
					break
				end match
			end while
			irpv attribute, list
				match =writeable?, attribute
					SECTION_FLAGS = SECTION_FLAGS or SHF_WRITE
				else match =executable?, attribute
					SECTION_FLAGS = SECTION_FLAGS or SHF_EXECINSTR
				else match =readable?, attribute
					SECTION_FLAGS = SHF_ALLOC
				else
					err 'invalid argument'
				end match
			end irpv

		else

			SECTION_NAME = declaration

		end match

		if FLAGS = LF_REALLOC
			section_org
		else
			SECTION_STATIC_BASE=$
			org SECTION_STATIC_BASE
		end if

		SECTION_RELOCATION_INDEX = RELOCATION_INDEX

	end namespace
end macro

macro public? declaration*
	namespace LEAF
		match value =as? str, declaration
			SYMBOL_VALUE = value
			SYMBOL_SIZE = sizeof value
			SYMBOL_NAME = string str
		else
			SYMBOL_VALUE = declaration
			SYMBOL_SIZE = sizeof declaration
			SYMBOL_NAME = `declaration
		end match
		if SYMBOL_VALUE relativeto 1 elementof SYMBOL_VALUE & 1 elementof (1 metadataof SYMBOL_VALUE) relativeto relocatable & 1 scaleof (1 metadataof SYMBOL_VALUE) > 0
			SYMBOL_SECTION_INDEX = 1 scaleof (1 metadataof SYMBOL_VALUE)
			SYMBOL_VALUE = SYMBOL_VALUE - 1 elementof SYMBOL_VALUE
		else
			SYMBOL_SECTION_INDEX = SHN_ABS
		end if
		store STRING_POSITION at symbol_table : Leaf24_Sym.st_name + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SYMBOL_NAME : lengthof SYMBOL_NAME at string_table:STRING_POSITION
		store SYMBOL_VALUE at symbol_table : Leaf24_Sym.st_value + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SYMBOL_SECTION_INDEX at symbol_table : Leaf24_Sym.st_shndx + SYMBOL_INDEX * sizeof Leaf24_Sym
		if SYMBOL_SIZE
			store STT_OBJECT + STB_GLOBAL shl 4 at symbol_table : Leaf24_Sym.st_info + SYMBOL_INDEX * sizeof Leaf24_Sym
		else
			store STT_FUNC + STB_GLOBAL shl 4 at symbol_table : Leaf24_Sym.st_info + SYMBOL_INDEX * sizeof Leaf24_Sym
		end if
		STRING_POSITION = STRING_POSITION + lengthof SYMBOL_NAME + 1
		SYMBOL_INDEX = SYMBOL_INDEX + 1
	end namespace
end macro

macro extern? declaration*
	namespace LEAF
		if ~definite declaration
		label declaration
		SYMBOL_NAME = `declaration
		store STRING_POSITION at symbol_table : Leaf24_Sym.st_name + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SYMBOL_NAME : lengthof SYMBOL_NAME at string_table:STRING_POSITION
		store STT_NOTYPE + STB_GLOBAL shl 4 at symbol_table : Leaf24_Sym.st_info + SYMBOL_INDEX * sizeof Leaf24_Sym
		store 0 at symbol_table : Leaf24_Sym.st_value + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SHN_UNDEF at symbol_table : Leaf24_Sym.st_shndx + SYMBOL_INDEX * sizeof Leaf24_Sym
		STRING_POSITION = STRING_POSITION + lengthof SYMBOL_NAME + 1
		SYMBOL_INDEX = SYMBOL_INDEX + 1
		end if
	end namespace
end macro

macro private? address*
end macro

macro static? declaration*
	namespace LEAF
	match name address, declaration
		label name
		SYMBOL_NAME = `name
		store STRING_POSITION at symbol_table : Leaf24_Sym.st_name + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SYMBOL_NAME : lengthof SYMBOL_NAME at string_table:STRING_POSITION
		store STT_FUNC + STB_LOCAL shl 4 at symbol_table : Leaf24_Sym.st_info + SYMBOL_INDEX * sizeof Leaf24_Sym
		store address at symbol_table : Leaf24_Sym.st_value + SYMBOL_INDEX * sizeof Leaf24_Sym
		store SHN_ABS at symbol_table : Leaf24_Sym.st_shndx + SYMBOL_INDEX * sizeof Leaf24_Sym
		STRING_POSITION = STRING_POSITION + lengthof SYMBOL_NAME + 1
		SYMBOL_INDEX = SYMBOL_INDEX + 1
	end match
	end namespace
end macro

element _GLOBAL_OFFSET_TABLE_
RVA? equ -_GLOBAL_OFFSET_TABLE_+
element PLT?

calminstruction calminstruction?.init? var*, val:0
	compute val, val
	publish var, val
end calminstruction

calminstruction calminstruction?.initsym? var*, val&
	publish var, val
end calminstruction

calminstruction calminstruction?.unique? name
	local counter, buffer
	init counter
	compute counter, counter + 1
	arrange buffer, name#counter
	publish name, buffer
end calminstruction

calminstruction calminstruction?.asm? line&
	local tmp, ln, buffer
	initsym tmp, unique ln
	assemble tmp
	publish ln, line
	arrange buffer, =assemble ln
	assemble buffer
end calminstruction

calminstruction @ez80.word size*, value*
	proxy size, value
	compute size, size
	compute value, value
	check	~ value relativeto 0 & value relativeto 1 elementof value & 1 elementof (1 metadataof value) relativeto LEAF.relocatable
	jyes	r_24
	
plain:
	emit @size: @value
	exit
	local	offset, info
r_24:
	compute info, R_Z80_24 + (0 scaleof (1 metadataof value)) shl 8
	check	LEAF.FLAGS = LF_REALLOC
	jno	no_realloc
	jump	add_relocation
no_realloc:
	asm	emit @size: 0 scaleof value
	exit	
add_relocation:
	compute offset, $%
	asm	emit @size: 0 scaleof value
	check	$% > offset
	jno	done
	compute offset, offset - LEAF.SECTION_OFFSET
	local	Rel
	compute Rel, LEAF.RELOCATION_INDEX * sizeof Leaf24_Rel
	asm	store offset at LEAF.relocations : Rel + Leaf24_Rel.r_offset
	asm	store info at LEAF.relocations : Rel + Leaf24_Rel.r_info
	compute LEAF.RELOCATION_INDEX, LEAF.RELOCATION_INDEX + 1
    done:
end calminstruction

postpone
	purge section?
	section
	namespace LEAF

		SECTION_NAME_TABLE_SIZE := SECTION_NAME_POSITION
		STRING_TABLE_SIZE := STRING_POSITION

		NUMBER_OF_SECTION_SYMBOLS := SECTION_SYMBOL_INDEX
		NUMBER_OF_SYMBOLS := SYMBOL_INDEX
		SYMBOL_TABLE_SIZE := NUMBER_OF_SYMBOLS * sizeof Leaf24_Sym

		NUMBER_OF_RELOCATIONS := RELOCATION_INDEX
		rb (-$%) and 11b
		RELOCATIONS_OFFSET = $%
		load byte_sequence : NUMBER_OF_RELOCATIONS * sizeof Leaf24_Rel from relocations:0
		db byte_sequence

		store _symtab at section_table : Leaf24_Shdr.sh_name + SECTION_INDEX * sizeof Leaf24_Shdr
		store $% at section_table : Leaf24_Shdr.sh_offset + SECTION_INDEX * sizeof Leaf24_Shdr
		store SYMBOL_TABLE_SIZE at section_table : Leaf24_Shdr.sh_size + SECTION_INDEX * sizeof Leaf24_Shdr
		store SHT_SYMTAB at section_table : Leaf24_Shdr.sh_type + SECTION_INDEX * sizeof Leaf24_Shdr
		SYMBOL_TABLE_SECTION_INDEX := SECTION_INDEX
		load byte_sequence : SYMBOL_TABLE_SIZE from symbol_table:0
		db byte_sequence
		SECTION_INDEX = SECTION_INDEX + 1

		store _strtab at section_table : Leaf24_Shdr.sh_name + SECTION_INDEX * sizeof Leaf24_Shdr
		store $% at section_table : Leaf24_Shdr.sh_offset + SECTION_INDEX * sizeof Leaf24_Shdr
		store STRING_TABLE_SIZE at section_table : Leaf24_Shdr.sh_size + SECTION_INDEX * sizeof Leaf24_Shdr
		store SHT_STRTAB at section_table : Leaf24_Shdr.sh_type + SECTION_INDEX * sizeof Leaf24_Shdr
		STRING_TABLE_SECTION_INDEX := SECTION_INDEX
		load byte_sequence : STRING_TABLE_SIZE from string_table:0
		db byte_sequence
		SECTION_INDEX = SECTION_INDEX + 1

		NUMBER_OF_SECTIONS := SECTION_INDEX
		SECTION_TABLE_OFFSET := $%
		load byte_sequence : NUMBER_OF_SECTIONS * sizeof Leaf24_Shdr from section_table:0
		db byte_sequence

	end namespace
end postpone
