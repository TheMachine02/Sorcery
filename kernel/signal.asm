define		KERNEL_SIGNAL_MAX	32

signal:

sysdef	_signal
.signal:
	ret

sysdef _kill
.kill:
.force:
; Send signal to an other thread
; int kill(pid_t pid, int sig)
; register A is signal
; register C is pid
; kill set the signal in the pending mask
; TODO : check permission
; TODO : implement force
	push	iy
	ld	b, a
	tsti
	ld	a, c
	add	a, a
	add	a, a
; can't send signal to PID 0
	jr	z, .__kill_no_thread
	ld	hl, kthread_pid_map
	ld	l, a
	ld	a, (hl)
	or	a, a
	jr	z, .__kill_no_thread
	inc	hl
	ld	iy, (hl)
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_ZOMBIE
	jr	z, .__kill_no_thread
; so now, we may send the signal
; special signal : sigstop and sigcont
	ld	a, b
	cp	a, SIGMAX
	jr	nc, .__kill_no_signal
	cp	a, SIGSTOP
	jr	z, .__kill_send_stop
	cp	a, SIGCONT
	jr	z, .__kill_send_cont
; generic
	call	.mask_operation
; we can mark it pending
	inc	hl
	inc	hl
	inc	hl
	or	a, (hl)
	ld	(hl), a
; it is pending right now
; wake the thread if status is interruptible only
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_INTERRUPTIBLE
	call	z, task_switch_running
; we are done
; recompute signal if needed
	call	.chkset
	rsti
	pop	iy
	ret

.__kill_no_thread:
	ld	a, ESRCH
	jr	.__kill_errno
.__kill_no_permission:
	ld	a, EPERM
	jr	.__kill_errno
.__kill_no_signal:
	ld	a, EINVAL
.__kill_errno:
	rsti
	pop	iy
	scf
	ret

.__kill_send_stop:
; reset all sigcont currently pending
	call	.mask_operation
	inc	hl
	inc	hl
	inc	hl
	or	a, (hl)
assert	SIGCONT = 18
	and	a, not (1 shl 1)
	ld	(hl), a
	ld	a, (iy+KERNEL_THREAD_SIGNAL_CURRENT)
	cp	a, SIGCONT
	jr	nz, .__kill_stop_no_current_reset
	ld	(iy+KERNEL_THREAD_SIGNAL_CURRENT), 0
.__kill_stop_no_current_reset:
; now wake the thread if state is INTERRUPTIBLE
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_INTERRUPTIBLE
	call	z, task_switch_running
; we are done
; recompute signal if needed
	call	.chkset
	rsti
	pop	iy
	ret

.__kill_send_cont:
; reset sigstop currently pending
	call	.mask_operation
	inc	hl
	inc	hl
	inc	hl
	or	a, (hl)
assert	SIGSTOP = 19
	and	a, not (1 shl 2)
	ld	(hl), a
	ld	a, (iy+KERNEL_THREAD_SIGNAL_CURRENT)
	cp	a, SIGSTOP
	jr	nz, .__kill_cont_no_current_reset
	ld	(iy+KERNEL_THREAD_SIGNAL_CURRENT), 0
.__kill_cont_no_current_reset:
; now wake the thread (state STOPPED OR INTERRUPTIBLE, lower bit is always set in this case)
	ld	a, (iy+KERNEL_THREAD_STATUS)
	rra
	call	c, task_switch_running
	call	.chkset
	rsti
	pop	iy
	ret

sysdef	_sigprocmask
.procmask:
; hl is a 3 bytes sigset structure, with signal set to be either reset or set
; do a XOR with signal mask
; there is no need for critical section as long as the thread is the only one to manipulate its mask
; ignore kill, cont and stop (can't be blocked)
	ld	iy, (kthread_current)
	lea	de, iy+KERNEL_THREAD_SIGNAL_MASK
	ld	a, (de)
	xor	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	ld	a, (de)
	xor	a, (hl)
assert	SIGKILL = 9
	or	a, 1 shl 0
	ld	(de), a
	inc	hl
	inc	de
	ld	a, (de)
	xor	a, (hl)
assert	SIGCONT = 18
assert	SIGSTOP = 19
	or	a, (1 shl 1) or (1 shl 2)
	ld	(de), a
	ret

.default_handler:
	jp	.core		; signal 0, undef
	jp	.exit
	jp	.exit
	jp	.core
	jp	.core
	jp	.core
	jp	.core
	jp	.core		; signal 7, undef
	jp	.core
	jp	.exit		; signal 9 kill
	jp	.exit
	jp	.core
	jp	.exit
	jp	.exit
	jp	.exit
	jp	.exit
	jp	.core		; signal 16, undef
	jp	.ignore		; sigchld
	jp	.ignore		; sigcont
	jp	.stop
	jp	.stop
	jp	.stop		; sigcont
	jp	.stop
	jp	.core

.exit:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_EXIT_FLAGS), SIGNALED
; we are in signal handler actually, we are able to grab the signal in the stack
; return adress (_sigreturn)
	pop	hl
; signal code	
	pop	hl
	ld	(iy+KERNEL_THREAD_EXIT_STATUS), l
	jp	kthread.do_exit

.core:
; write whole process image to a "core" file in reallocated mode
; leaf file format
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_EXIT_FLAGS), SIGNALED or COREDUMP
	pop	hl
	pop	hl
	ld	(iy+KERNEL_THREAD_EXIT_STATUS), l
	jp	kthread.do_exit
	
.stop:
	di
	call	task_switch_stopped
	jp	task_yield

; NOTE : special sysdef right here, sigreturn can be called from within signal handler
_sigreturn=$
; trash return adress and call actual routine
	pop	hl
	pop	hl
.return:
; NOTE : interrupt happen in the space where interrupt happened
; trash the argument
	pop	hl
; unwind the stack frame
; reset the signal mask
	di
	ld	a, l
	ld	iy, (kthread_current)
	call	.mask_operation
	ld	a, (iy+KERNEL_THREAD_SIGNAL_SAVE)
	or	a, (hl)
	ld	(hl), a
; the pop the stack
	pop	hl
	pop	af
user_return_signal:=$
	pop	bc
	pop	de
	di
	exx
	ex	af, af'
	ld	hl, i
	inc	hl
	ld	iy, (hl)
	call	.chkset
; and perform context restore to see if any more signal is *pending*
	jp	kinterrupt.irq_context_restore

; check for signal recalc for thread iy
.chkset:
	ld	a, (iy+KERNEL_THREAD_SIGNAL_CURRENT)
	or	a, a
	ret	nz
; from current thread iy, compute current signal
; and reset the current signal from the thread mask list
	lea	hl, iy+KERNEL_THREAD_SIGNAL_PENDING+2	; pending
	lea	de, iy+KERNEL_THREAD_SIGNAL_MASK+2	; blocked
	ld	c, 3
.__chkset_mask_outer:
	ld	a, (de)
	and	a, (hl)
	ld	b, 8
.__chkset_mask:
	rla
	jr	c, .__chkset_from_bit
	djnz	.__chkset_mask
	dec	hl
	dec	de
	dec	c
	jr	nz, .__chkset_mask_outer
; no more signal
	ld	(iy+KERNEL_THREAD_SIGNAL_CURRENT), 0
	ret
.__chkset_from_bit:
	dec	c
; we have the bit number (b) and the byte number (c)
; reset from mask, set current
	ld	a, c
	add	a, a
	add	a, a
	add	a, a
	add	a, b
	ld	(iy+KERNEL_THREAD_SIGNAL_CURRENT), a
; generate mask from b
	xor	a, a
	scf
	rla
	djnz	$-1
; reset the bit within pending
	xor	a, (hl)
	ld	(hl), a
.ignore:
	ret

.mask_operation:
; from signal a, for thread iy, output both signal mask in a and signal byte in hl
; 0 -> 7 byte 0
; 8 -> 15 byte 1
; 16 -> 23 byte 2
	lea	hl, iy+KERNEL_THREAD_SIGNAL_MASK
	dec	a
	cp	a, 8
	jr	c, $+3
	inc	hl
	cp	a, 16
	jr	c, $+3
	inc	hl
	and	a, 7
	ld	b, a
	inc	b
	xor	a, a
	scf
	rla
	djnz	$-1
	ret
