define	SIGHUP		1           ; Hangup / death control ; TERM
define	SIGINT		2           ; Interrupt keyboard     ; TERM
define	SIGQUIT		3           ; Quit                   ; CORE
define	SIGILL		4           ; Illegal instruction    ; CORE
define	SIGTRAP		5           ; Trace/breakpoint trap  ; CORE
define	SIGABRT		6           ; abort signal (abort)   ; CORE
define	SIGFPE		8           ; Floatpoint exception   ; CORE
define	SIGKILL		9           ; KILL                   ; TERM (unblockable)
define	SIGUSR1		10          ; User                   ; TERM
define	SIGSEGV		11          ; Segmentation fault     ; CORE
define	SIGUSR2		12          ; User                   ; TERM
define	SIGPIPE		13          ; Broken pipe            ; TERM
define	SIGALRM		14          ; timer signal (alarm)   ; TERM
define	SIGTERM		15          ; Termination signal     ; TERM
define	SIGCHLD		17          ; child stopped (unused) ; IGN
define	SIGCONT		18          ; continue               ; CONT
define	SIGSTOP		19          ; Stop process           ; STOP (unblockable)
define	SIGTSTP		20          ; Stop typed at term     ; STOP
define	SIGTTIN		21          ; Terminal input         ; STOP
define	SIGTTOU		22          ; Terminal output        ; STOP
define	SIGSYS		23          ; Bad syscall            ; CORE

ksignal:
; void	handler(int sig, void *ucontext)
; sp+6 *ucontext
; sp+3 sig 
; sp is return
.handler:
; this is called by the thread
; hl = data, a = signal code, iy is thread
; stack is context to restore
; note that signal can be masked in the KERNEL_THREAD_SIGNAL 8 bytes mask
	ld	(iy+KERNEL_THREAD_SIGNAL_CODE), a
	ld	(iy+KERNEL_THREAD_SIGNAL_MESSAGE), hl
	dec	a
	ld	c, a
	ld	b, 3
	mlt	bc
	ld	hl, .HANDLER_JUMP
	add	hl, bc
	ld	hl, (hl)
	jp	(hl)

.handler_stop:
	di
; thread is in active queue, TASK_READY state
; stop it anyway
	jp	task_switch_stopped
	
.handler_continue:
; we currently have a running thread. Just check if it was waiting for IRQ request too, if so, we will yield
; else wake it up completely
	di
	ld	a, (iy+KERNEL_THREAD_IRQ)	; this read need to be atomic
	or	a, a
	ret	z
	jp	task_switch_interruptible
	
.handler_return:
	ret

.HANDLER_JUMP:
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.core
 dl	kthread.core
 dl	kthread.core
 dl	kthread.core
 dl	.handler_return
 dl	kthread.core
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.core
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.exit
 dl	.handler_return
 dl	.handler_return
 dl	.handler_continue
 dl	.handler_stop
 dl	.handler_stop
 dl	.handler_stop
 dl	.handler_stop
 dl	kthread.core
	
.wait:
; wait for a signal, return hl = signal
	call	kthread.suspend
	or	a, a
	sbc	hl, hl
	push	iy
	ld	iy, (kthread_current)
	ld	l, (iy+KERNEL_THREAD_SIGNAL_CODE)
	pop	iy
	ret
	
.timedwait:
; sleep for a duration, can be waked by signal
; todo : clean signal after read
	call	kthread.sleep
	or	a, a
	sbc	hl, hl
	push	iy
	ld	iy, (kthread_current)
	ld	l, (iy+KERNEL_THREAD_SIGNAL_CODE)
	pop	iy
	ret
	
; change thread signal list ; 
.procmask: 
    ret	
	
abort:
	ld	a, SIGABRT
	
raise:
; Raise signal to current thread
; REGSAFE and ERRNO compliant
; int raise(int sig)
; register A is signal
; Also silently pass register HL to signal handler as a void*
; return -1 on error, 0 on success with errno correctly set
	push	hl
	ld	hl, (kthread_current)
	ld	c, (hl)
	pop	hl
	
kill:
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
	ld	hl, kthread_pid_bitmap
	ld	l, a
; let's start the critical section right now
	tstdi
	ld	a, c
	ld	c, (hl)
	dec	c
; c is thread priority -1, a is pid, b is signal
	add	a, a
	add	a, a
	ld	l, a
	ld	a, (hl)
	or	a, a
	jr	z, .no_thread
	inc	hl
	ld	iy, (hl)
	dec	hl
; b = signal, iy = thread adress
; push on the thread stack all the context
; todo check permission here (first byte of bitmap is permission level)    
	ld	a, c
; permission of the (current thread-1) < signaled thread (if equal)
	cp	a, (hl)
	jr	nc, .no_permission
; check the signal to send
	ld	a, b
	or	a, a
	jr	z, .no_signal
; so now, I have iy = thread to signal, still the signal in a, data in de
; push the context on the thread stack
	ld	a, b
	ld	hl, (kthread_current)
	lea	bc, iy+0
	sbc	hl, bc
	ld	b, a	; save a pls
	jr	z, .raise_frame
	push	ix
	ld 	ix, (iy+KERNEL_THREAD_STACK)
	or	a, a
	sbc	hl, hl
	ld	(ix-15), hl
	ld	(ix-18), iy
	ld	(ix-21), de
	ld	(ix-24), hl
	ld	(ix-27), hl
	ld	(ix-30), bc
	ld	(ix-3), de
	ld	l, a
	ld	(ix-6), hl
	ld	hl, _sigreturn
	ld	(ix-9), hl
	ld	hl, ksignal.handler
	ld	(ix-12), hl
; adjust stack position
	lea	hl, ix-30
	ld	(iy+KERNEL_THREAD_STACK), hl
	pop	ix
; change state of the thread based on the context
; if state is RUNNING, make it running 
	ld	a, (iy+KERNEL_THREAD_STATUS)
	or	a, a
	call	nz, task_switch_running
	tstei
	ld	a, b
	or	a, a
	sbc	hl, hl
	pop	de
	pop	bc
	pop	iy
	ret
.no_thread:
	ld	a, ESRCH
	jr	.errno
.no_permission:
	ld	a, EPERM
	jr	.errno
.no_signal:
	ld	a, EINVAL
.errno:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), a
	tstei
	ld	a, b
	scf
	sbc	hl, hl
	pop	de
	pop	bc
	pop	iy
	ret
.raise_frame:
; so now, I have iy = thread to signal, still the signal in a, data in de
; push the context on the thread stack
	tstei
	ld	a, b
	or	a, a
	pop	de
	pop	bc
	ex	(sp), ix
; all stack clean
	push	ix
	or	a, a
	sbc	hl, hl
	push	hl
	push	bc
	push	de
	push	af
; stack is now clean
	push	hl	; data = NULL
	ld	l, a
	push	hl	; signal
	ld	ix, _sigreturn
	push	ix
	ld	ix, ksignal.handler
	jp	(ix)
	
; sig return will need to cleanup stack, and there is a lot to do, it should NEVER be called
_sigreturn:
; return adress
; sp+6 stackframe
; sp+3 *ucontext
; sp+sig
	ld	hl, 6
	add	hl, sp
	ld	sp, hl
; if this result is non zero, we already have interrupt disabled, plus, it will be scheduled away if an interrupt fire
; If it is zero, well we continue anyway
	ld	a, (iy+KERNEL_THREAD_STATUS)
	or	a, a
	jr	nz, .yield
	pop	af
	pop	de
	pop	bc
	pop	hl
	pop	iy
	pop	ix
	ret
.yield:
	pop	af
	pop	de
	pop	bc
	pop	hl
	pop	iy
	pop	ix
	jp	task_yield
