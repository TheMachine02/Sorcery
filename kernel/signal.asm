define		KERNEL_SIGNAL_MAX	32

signal:

.wait:
; wait for a signal, return hl = signal
	call	kthread.suspend
	jr	.timed_wait_ret

.wait_timeout:
; sleep for a duration, can be waked by signal
; todo : clean signal after read
	call	kthread.sleep
.timed_wait_ret:
	or	a, a
	sbc	hl, hl
	push	iy
	ld	iy, (kthread_current)
	ld	l, (iy+KERNEL_THREAD_EV_SIG)
	pop	iy
	ret
	
; change thread signal list ;
; mark signal (reg A) to be blocked
.procmask_single:
	ld	iy, (kthread_current)
	lea	hl, iy+KERNEL_THREAD_SIGNAL_MASK
	tst	a, 11111000b	; > 8
	jr	z, $+3
	inc	hl
	tst	a, 11110000b	; > 16
	jr	z, $+3
	inc	hl
	tst	a, 11100000b
	jr	z, $+3
	inc	hl
	and	00000111b
	inc	a
	ld	b, a
	xor	a, a
	scf
	rla
	djnz	$-1
	xor	a, (hl)
	ld	(hl), a
	ret

.procmask:
; hl is a 4 bytes sigset structure, with signal set to be either reset or set
; do a XOR with signal mask
; there is no need for critical section as long as the thread is the only one to manipulate its mask
	ld	iy, (kthread_current)
	lea	de, iy+KERNEL_THREAD_SIGNAL_MASK
	ld	a, (de)
	xor	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	ld	a, (de)
	xor	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	ld	a, (de)
	xor	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	ld	a, (de)
	xor	a, (hl)
	ld	(de), a
	ret

.abort:
	ld	a, SIGABRT
	
.raise:
; Raise signal to current thread
; REGSAFE and ERRNO compliant
; int raise(int sig)
; register A is signal
; Also silently pass register HL to signal handler as a void*
; return -1 on error, 0 on success with errno correctly set
; note that raising a signal in a signal handler may not be a good idea without doing what we want first
	push	hl
	ld	hl, (kthread_current)
	ld	c, (hl)
	pop	hl

sysdef _kill
.kill:
; Send signal to an other thread
; REGSAFE and ERRNO compliant
; int kill(pid_t pid, int sig)
; register A is signal
; register C is pid
; Also silently pass register HL to signal handler as a void*
; return -1 on error, 0 on success with errno correctly set
	push	iy
	push	bc
	push	de
	ld	b, a
	ex	de, hl
	ld	hl, (kthread_current)
	ld	a, (hl)
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
; let's start the critical section right now
	tsti
	ld	a, c
	ld	c, (hl)
	dec	c
; c is thread priority -1, a is pid, b is signal
	add	a, a
	add	a, a
	ld	l, a
	ld	a, (hl)
	or	a, a
	jp	z, .kill_no_thread
	inc	hl
	ld	iy, (hl)
	dec	hl
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_ZOMBIE
	jp	z, .kill_no_thread
; b = signal, iy = thread adress
; push on the thread stack all the context
; todo check permission here (first byte of bitmap is permission level)    
	ld	a, c
; permission of the (current thread-1) < signaled thread (if equal)
	cp	a, (hl)
	jp	nc, .kill_no_permission
; check the signal to send
	ld	a, b
	ld	c, a
	or	a, a
	jp	z, .kill_no_signal
; iy is still thread to signal, a is signal
	cp	a, SIGSTOP
	jp	z, .kill_signal_stop
	cp	a, SIGKILL
	jp	z, .kill_signal_kill
; is the signal blocked ?
; y/n
; else jump to default function
	lea	hl, iy+KERNEL_THREAD_SIGNAL_MASK
	tst	a, 11111000b	; > 8
	jr	z, $+3
	inc	hl
	tst	a, 11110000b	; > 16
	jr	z, $+3
	inc	hl
	tst	a, 11100000b
	jr	z, $+3
	inc	hl
	and	00000111b
	inc	a
	ld	b, a
	xor	a, a
	scf
	rla
	djnz	$-1
; tst (hl) and a bitmask
	and	a, (hl)
; this mean it is set in (hl)
	jr	nz, .kill_clean
	ld	a, c
	cp	a, SIGCONT
	jr	nz, .kill_generic
.kill_signal_cont:
	push	af
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_STOPPED
	call	z, task_switch_running
	pop	af
.kill_generic:
; so now, I have iy = thread to signal, still the signal in c, data in de
; push the context on the thread stack
; restore signal in a
	ld	hl, (kthread_current)
	lea	bc, iy+0
	or	a, a
	sbc	hl, bc
	jr	z, .kill_raise_frame
	push	ix
	lea	hl, iy+KERNEL_THREAD_STACK_LIMIT
	ld	bc, $00033A
	otimr
	ld	ix, 0
	add	ix, sp
	ld	hl, (hl)
	ld	sp, hl
	push	de
	ld	c, a
	push	bc
	ld	hl, _sigreturn
	push	hl
	ld	hl, _sighandler
	push	hl
	ld	c, b
	push	bc
	push	iy
	push	de
	push	bc
	push	bc
	ld	b, a
	push	bc
	sbc	hl, hl
	add	hl, sp
	ld	(iy+KERNEL_THREAD_STACK), hl
	ld	sp, ix
	ld	ix, (kthread_current)
	lea	hl, ix+KERNEL_THREAD_STACK_LIMIT
	ld	bc, $00033A
	otimr
	ld	b, a
	pop	ix
; change state of the thread based on the context
; if state is not RUNNING, make it running
; note : if signal is SIGCONT, we have already wake the thread
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_INTERRUPTIBLE
	call	z, task_switch_running
.kill_clean:
	rsti
	ld	a, b
	or	a, a
	sbc	hl, hl
	pop	de
	pop	bc
	pop	iy
	ret
.kill_raise_frame:
; so now, I have iy = thread to signal, still the signal in a, data in de
; push the context on the thread stack
	pop	hl	; this is the raise() interrupt status
	pop	de
	pop	bc
	ex	(sp), ix
; all stack clean
	push	ix
	ld	ix, 0
	push	ix
	push	bc
	push	de
	push	af
; stack is now clean
	push	hl	; data = NULL
	ld	l, a
	push	hl	; signal
	ld	ix, _sighandler
	pea	ix-15	; = "ld	ix, _sigreturn \ push	ix"
	jp	(ix)
.kill_signal_stop:
	ld	a, (iy+KERNEL_THREAD_STATUS)
; if running or interruptible > switch to stopped
; if stopped, idle or zombie : don't touch
	tst	a, 11111110b
	jr	nz, .kill_clean
	dec	a	; interruptible
	call	z, task_switch_stopped
	ld	(iy+KERNEL_THREAD_STATUS), TASK_STOPPED
	jr	.kill_clean
.kill_signal_kill:
; kill anything
	ld	a, (iy+KERNEL_THREAD_STATUS)
	cp	a, TASK_ZOMBIE
	jr	z, .kill_clean
	or	a, a
	call	nz, task_switch_running
	ld	iy, (iy+KERNEL_THREAD_STACK)
; insert shamelessly thread exit routine
	ld	hl, kthread.exit
	ld	(iy+18), hl
	jr	.kill_clean
.kill_no_thread:
	ld	a, ESRCH
	jr	.kill_errno
.kill_no_permission:
	ld	a, EPERM
	jr	.kill_errno
.kill_no_signal:
	ld	a, EINVAL
.kill_errno:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), a
	rsti
	ld	a, b
	scf
	sbc	hl, hl
	pop	de
	pop	bc
	pop	iy
	ret

; sig return will need to cleanup stack, and there is a lot to do, it should NEVER be called
_sigreturn:
; return adress
; sp+6 stackframe
; sp+3 *ucontext
; sp+sig
	ld	hl, 6
	add	hl, sp
	ld	sp, hl
	pop	af
	pop	de
	pop	bc
	pop	hl
	pop	iy
	pop	ix
_sighandler_return:
	ret

; void	handler(int sig, void *ucontext)
; sp+6 *ucontext
; sp+3 sig 
; sp is return
_sighandler:
; this is called by the thread
; hl = data, a = signal code, iy is thread
; stack is context to restore
; note that signal can be masked in the KERNEL_THREAD_SIGNAL 4 bytes mask
	ld	(iy+KERNEL_THREAD_EV_SIG), a
	ld	(iy+KERNEL_THREAD_EV_SIG_POINTER), hl
	ld	c, a
	ld	b, 3
	mlt	bc
	ld	hl, _sighandler_jump-3
	add	hl, bc
	ld	ix, (hl)
	or	a, a
	sbc	hl, hl
	ld	l, a
	jp	(ix)

_sighandler_stop:
	di
	call	task_switch_stopped
	ld	hl, 6
	add	hl, sp
	ld	sp, hl
	pop	af
	pop	de
	pop	bc
	pop	hl
	pop	iy
	pop	ix
	jp	task_yield

_sighandler_jump:
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.core
 dl	kthread.core
 dl	kthread.core
 dl	kthread.core
 dl	_sighandler_return
 dl	kthread.core
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.core
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.exit
 dl	_sighandler_return
 dl	_sighandler_return
 dl	_sighandler_return		; sigcont
 dl	_sighandler_stop
 dl	_sighandler_stop
 dl	_sighandler_stop
 dl	_sighandler_stop
 dl	kthread.core
