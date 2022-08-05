include "asm-leaf-def.inc"

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
	st_shndx	rb 1
	st_value	rl 1
	st_name 	rl 1
	st_info 	rb 1
end struct

struct Leaf24_Rel
	r_offset	rl 1
	r_info		rl 1
	r_type		rb 1
	r_pad		rb 1
end struct

purge struct?

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

	e_ident 	db $C9,'LEAF'
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
		store SYMBOL_INDEX * sizeof Leaf24_Sym at LEAF:e_entry
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
			if (FLAGS and LF_STATIC)
				store SECTION_STATIC_BASE at section_table : Leaf24_Shdr.sh_addr + SECTION_INDEX * sizeof Leaf24_Shdr
			else	
				store SECTION_SYMBOL_INDEX * sizeof Leaf24_Sym at section_table : Leaf24_Shdr.sh_addr + SECTION_INDEX * sizeof Leaf24_Shdr
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
				store SECTION_SYMBOL_INDEX * sizeof Leaf24_Sym at section_table : Leaf24_Shdr.sh_addr + (SECTION_INDEX+1) * sizeof Leaf24_Shdr

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

;macro static? declaration*
;	namespace LEAF
;	match name address, declaration
;		label name
;		SYMBOL_NAME = `name
;		store STRING_POSITION at symbol_table : Leaf24_Sym.st_name + SYMBOL_INDEX * sizeof Leaf24_Sym
;		store SYMBOL_NAME : lengthof SYMBOL_NAME at string_table:STRING_POSITION
;		store STT_FUNC + STB_LOCAL shl 4 at symbol_table : Leaf24_Sym.st_info + SYMBOL_INDEX * sizeof Leaf24_Sym
;		store address at symbol_table : Leaf24_Sym.st_value + SYMBOL_INDEX * sizeof Leaf24_Sym
;		store SHN_ABS at symbol_table : Leaf24_Sym.st_shndx + SYMBOL_INDEX * sizeof Leaf24_Sym
;		STRING_POSITION = STRING_POSITION + lengthof SYMBOL_NAME + 1
;		SYMBOL_INDEX = SYMBOL_INDEX + 1
;	end match
;	end namespace
;end macro

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
	compute info, (0 scaleof (1 metadataof value))
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
	asm	store info * sizeof Leaf24_Sym at LEAF.relocations : Rel + Leaf24_Rel.r_info
	asm	store R_Z80_24 at LEAF.relocations : Rel + Leaf24_Rel.r_type
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
