_syscall:
; jumper to syscall ?

; end syscall here

; syscall_0arg	_get_pid
_get_pid:
; REGSAFE and ERRNO compliant
; pid_t getpid()
; return value is register hl
	ld	hl, (kthread_current)
	ld	l, (hl)
	ld	h, 1
	mlt	hl
	ret
  
; syscall_0arg	_get_ppid
_get_ppid:
; REGSAFE and ERRNO compliant
; pid_t getppid()
; return value is register hl
	push	de
	ld	hl, (kthread_current)
	ld	de, KERNEL_THREAD_PPID
	add	hl, de
	ld	e, (hl)
	ex	de, hl
	pop	de
	ret

_uadmin:
; cmd, fn, mdep
	ret

; pri
_nice:
; hl = nice, return the new nice value
	ld	iy, (kthread_current)
	ld	a, (iy+KERNEL_THREAD_NICE)
	add	a, l
; between -20 and 19
	jp	m, .check_max
	cp	a, 20
	jr	c, .return
	ld	a, NICE_PRIO_MIN
	jr	.return
.check_max:
	cp	a, -20
	jr	nc, .return
	ld	a, NICE_PRIO_MAX
.return:
	ld	(iy+KERNEL_THREAD_NICE), a
	add	a, a
	sbc	hl, hl
	rra
	ld	l, a
	ret

_sbrk:
; increment as hl
	ld	iy, (kthread_current)
	ld	de, (iy+KERNEL_THREAD_BREAK)
	add	hl, de
; now check : that sp - 512 > hl and that hl > iy + 256+13
	lea	bc, iy+13
	inc	d
	or	a, a
	sbc	hl, bc
	jr	c, .break_error
	add	hl, bc
; now check with sp
	push	hl
	ld	hl, -512
	add	hl, sp
	pop	bc
	or	a, a
	sbc	hl, bc
	jr	c, .break_error
; all good, return the old break value
	ex	de, hl
	ret	
.break_error:
	scf
	sbc	hl, hl
	ld	l, -ENOMEM
	ld	(iy+KERNEL_THREAD_ERRNO), hl
	ret
