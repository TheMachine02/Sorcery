; set of CEmu software debug command ;

dbg_cmd:
	scf
	sbc	hl, hl
	ld	(hl), a
	ret

dbg_open:
	scf
	sbc	hl, hl
	ld	(hl), 2
	ret

dbg_set_break:
; de = break point adress
	scf
	sbc	hl, hl
	ld	(hl), 3
	ret
	
dbg_rem_break:
; de = break point adress
	scf
	sbc	hl, hl
	ld	(hl), 4
	ret
	
dbg_set_read_watch:
	scf
	sbc	hl, hl
	ld	(hl), 5
	ret
	
dbg_set_write_watch:
	scf
	sbc	hl, hl
	ld	(hl), 6
	ret
	
dbg_set_rw_watch:
	scf
	sbc	hl, hl
	ld	(hl), 7
	ret
	
dbg_set_watch:
	scf
	sbc	hl, hl
	ld	(hl), 11
	ret
	
dbg_rm_watch:
	scf
	sbc	hl, hl
	ld	(hl), 8
	ret
	
dbg_rm_all_break:
	scf
	sbc	hl, hl
	ld	(hl), 9
	ret

dbg_rm_all_watch:
	scf
	sbc	hl, hl
	ld	(hl), 10
	ret
