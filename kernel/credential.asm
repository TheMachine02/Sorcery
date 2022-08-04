define	ROOT_USER			$00	; maximal permission
define	SUPER_USER			$01	; almost maximal permission
; anything above this is an uprivilieged uid


user_perm:
; NOTE : expect to return to the trampoline at the current code level (so, first routine to be called in the routine, and will exit the routine itself)
; check for the thread permission currently executing this code span
; is it superuser or not ?
	push	af
	push	hl
	ld	hl, (kthread_current)
assert KERNEL_THREAD_PID = 0
	ld	a, (hl)
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	and	a, 11111110b
	pop	hl
	jr	nz, .permission_failed
	pop	af
	ret
.permission_failed:
	pop	af
	pop	af	; throw away the return adress
	ld	hl, -EPERM
	ret
	
sysdef _getuid
; uid_t getuid()
getuid:
	ld	hl, (kthread_current)
	ld	a, (hl)
	ld	hl, kthread_pid_map
	add	a, a
	add	a, a
	ld	l, a
	ld	a, (hl)
	sbc	hl, hl
	ld	l, a
	ret	

sysdef	_setuid
setuid:
; TODO : implement
	ld	hl, -EPERM
	ret
	
	
sysdef _getpid
; pid_t getpid()
getpid:
	ld	hl, (kthread_current)
	ld	l, (hl)
	ld	h, 1
	mlt	hl
	ret
  
sysdef _getppid
; pid_t getppid()
getppid:
	ld	hl, (kthread_current)
	ld	de, KERNEL_THREAD_PPID
	add	hl, de
	ld	e, (hl)
	ex	de, hl
	ret
	
sysdef	_getsid
; pid_t getsid()
getsid:
	ld	hl, (kthread_current)
	ld	de, KERNEL_THREAD_SID
	add	hl, de
	ld	e, (hl)
	ex	de, hl
	ret
	
sysdef	_setsid
setsid:
	ld	iy, (kthread_current)
	ld	a, (iy+KERNEL_THREAD_PID)
	ld	hl, kthread_pid_map + KERNEL_THREAD_MAP_SIZE + 1
	ld	de, KERNEL_THREAD_MAP_SIZE
	ld	b, 63
.__setsid_check:
	ld	ix, (hl)
	cp	a, (ix+KERNEL_THREAD_SID)
	jr	z, .__setsid_error
	add	hl, de
	djnz	.__setsid_check
; all good
	ld	(iy+KERNEL_THREAD_SID), a
	or	a, a
	sbc	hl, hl
	ld	l, a
	ret
.__setsid_error:
	ld	hl, -EPERM
	ret
