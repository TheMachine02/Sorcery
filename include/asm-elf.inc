; type ;
define	ELF_EXEC		1
define	ELF_SO			2
; section type ;
define	ELF_NULL		0
define	ELF_RW_DATA		2
define	ELF_RW_INSTR		2
define	ELF_RO_DATA		3
define	ELF_RW_ZERO		4
define	ELF_DYNAMIC		5
; header size ;
define	ELF_HEADER_SIZE		6
; section ;
define	ELF_SECTION_HEADER	0
define	ELF_SECTION_HEADER_SIZE	8
define	ELF_SECTION_TYPE	0
define	ELF_SECTION_OFFSET	2
define	ELF_SECTION_SIZE	5

define	ELF_REALLOC_SIZE	4
define	ELF_REALLOC_OFFSET	0
define	ELF_REALLOC_SECTION	3

define	ELF_MAG0		0
define	ELF_MAG1		1
define	ELF_MAG2		2
define	ELF_MAG3		3
define	ELF_TYPE		4
define	ELF_VERSION		5

section_allocsize = 0
lib_count = -1
virtual
	elf.dynamic_name::
end virtual

macro elf? type*
	virtual
		elf.section_header::
	end virtual
	
	org 0
	elf_ident         db 0x8F, 'E', 'L', 'F'
	elf_type          db type
	elf_version       db 1
elf.start:
	org	$

	postpone
		size = $ - $$ - section_allocsize
		virtual elf.section_header
			dl size
			load elf.section_header0: $-$$ from $$
		end virtual
	end postpone
	elf.section_headerbyte:
	elf_shnum         db (lengthof elf.section_header0)/8
	db elf.section_header0
	
	postpone
		section dynamic, ELF_DYNAMIC
		elf_dynamic=$
		virtual elf.dynamic_name
			load elf.dynamic_name0: $-$$ from $$
		end virtual
		db elf.dynamic_name0
	end postpone
end macro

macro private
	local section_index, current_reloc
	section_index = 0
	macro section? section_name, type*
		section_name:
		local base, reloc_area, reloc_data
		virtual
		reloc_area::
		end virtual

		if section_index
			size = $ - $$ - section_allocsize
			virtual elf.section_header
				dl size
			end virtual
		end if

		current_reloc equ reloc_area
		element base: section_index
		postpone
			virtual reloc_area
				load reloc_data: $ - $$ from $$
			end virtual
		end postpone
			virtual elf.section_header
				db   type,0x00
				dl	$%% 
			end virtual
		section_allocsize = lengthof reloc_data + 1
		section base - lengthof reloc_data - 1
		db ( lengthof reloc_data ) /4
		db reloc_data
		section_index = section_index + 1
		
	end macro
	macro @ez80.word @value*
		local value, addr
		value = @value
		if value relativeto value element 1 & elementsof value
			addr = $
			assert addr relativeto addr element 1 & addr metadata 1 + 1 = section_index
			virtual current_reloc
				@ez80.word addr scale 0
				db value metadata 1
			end virtual
			@ez80.word value scale 0
		else
			@ez80.word value
		end if
	end macro
	
end macro
private
purge private

macro library? lib_name
	local count
	count=0
	macro export? arg
		arg=(count*4) + elf_dynamic + (lib_count*65536)
		count = count + 1
	end macro
	virtual elf.dynamic_name
		db lib_name, 0
	end virtual
	lib_count = lib_count + 1
end macro
