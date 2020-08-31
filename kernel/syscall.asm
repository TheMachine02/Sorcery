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
	push	iy
	ld	iy, (kthread_current)
	or	a, a
	sbc	hl, hl
	ld	l, (iy+KERNEL_THREAD_PPID)
	pop	iy
	ret
