; set of CEmu software debug command ;
macro dbg_cmd
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), a
	pop	hl
end macro

macro dbg_open
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 2
	pop	hl
end macro

macro dbg_set_break
; de = break point adress
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 3
	pop	hl
end macro
	
macro dbg_rem_break
; de = break point adress
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 4
	pop	hl
end macro
	
macro dbg_set_read_watch
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 5
	pop	hl
end macro
	
macro dbg_set_write_watch
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 6
	pop	hl
end macro
	
macro dbg_set_rw_watch
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 7
	pop	hl
end macro
	
macro dbg_set_watch
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 11
	pop	hl
end macro
	
macro dbg_rm_watch
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 8
	pop	hl
end macro
	
macro dbg_rm_all_break
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 9
	pop	hl
end macro

macro dbg_rm_all_watch
	push	hl
	scf
	sbc	hl, hl
	ld	(hl), 10
	pop	hl
end macro
