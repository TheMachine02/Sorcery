; set of CEmu software debug command ;
macro dbg command,func,data
	if	CONFIG_DEBUG
	match =cmd?, command
		push	af
		push	hl
		scf
		sbc	hl, hl
		ld	(hl), a
		pop	hl
		pop	af
	else match =thread?, command
		push	iy
		ld	iy, DEBUG_THREAD
		call	kthread.create
		pop	iy
	else match =open?, command
		push	af
		push	hl
		scf
		sbc	hl, hl
		ld	(hl), 2
		pop	hl
		pop	af
	else match =set?, command
		push	de
		ld	de, data
		push	af
		push	hl
		scf
		sbc	hl, hl
		match =break?, func
			ld	(hl), 3
		else match =watch
			ld	(hl), 11
		end match
		pop	hl
		pop	af
		pop	de
	else match =rm?, command
		push	de
		ld	de, data
		push	af
		push	hl
		scf
		sbc	hl, hl
		match =break?, func
			ld	(hl), 4
		else match =watch?, func
			ld	(hl), 8
		end match
		pop	hl
		pop	af
		pop	de
	else
	err 'dbg : invalid argument'
	end match
	end if
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

if CONFIG_DEBUG

DEBUG_THREAD:
	ret
 
 end if
