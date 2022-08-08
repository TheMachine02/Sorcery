define	ROOT_USER			$00	; maximal permission
define	SUPER_USER			$01	; almost maximal permission
; anything above this is an uprivilieged uid


user_perm:
; NOTE : expect to return to the trampoline at the current code level (so, first routine to be called in the routine, and will exit the routine itself)
; check for the thread permission currently executing this code span
; is it superuser or root ?
; destroy register a
	push	hl
	ld	hl, (kthread_current)
	ld	a, (hl)
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	ld	a, (hl)
	pop	hl
	and	a, 11111110b
	ret	z
.permission_failed:
	pop	af	; throw away the return adress
	ld	hl, -EPERM
	ret
	
sysdef _geteuid
; uid_t getuid()
geteuid:
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

sysdef	_getuid
getuid:
	ld	iy, (kthread_current)
	or	a, a
	sbc	hl, hl
	ld	l, (iy+KERNEL_THREAD_RUID)
	ret
	
sysdef	_setreuid
; int setreuid(uid_t ruid, uid_t euid); 
setreuid:
; if the process is not privileged, can only set euid to either euid, ruid ou suid
; else, it's free
; TODO : implement
	ld	hl, -EPERM
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
