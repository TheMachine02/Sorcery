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

.handler:
; this is called by the thread
; hl = data, a = signal code, iy is thread
; stack is context to restore
; note that signal can be masked in the KERNEL_THREAD_SIGNAL 8 bytes mask
	ex	de, hl
	ld	c, a
	ld	b, 3
	mlt	bc
	ld	hl, .HANDLER_JUMP
	add	hl, bc
	ld	hl, (hl)
	jp	(hl)
.handler_context_restore:
; semi context_restore
	pop	af
	pop	de
	pop	bc
	pop	hl
	pop	iy
	pop	ix
	ei
	ret
	
.handler_stop:
	di
; thread is in active queue, TASK_READY state
; stop it anyway
	call	task_switch_stopped
	jr	.handler_context_yield
	
.handler_continue:
; we currently have a running thread. Just check if it was waiting for IRQ request too, if so, we will yield
; else wake it up completely
	di
	ld	a, (iy+KERNEL_THREAD_IRQ)	; this read need to be atomic
	or	a, a
	jr	z, .handler_context_restore
	call	task_switch_interruptible
	
.handler_context_yield:
; context restore and yield
	pop	af
	pop	de
	pop	bc
	pop	hl
	pop	iy
	pop	ix
	jp	kthread.yield
	
.HANDLER_JUMP:
 dl	.handler_context_restore
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.core
 dl	kthread.core
 dl	kthread.core
 dl	kthread.core
 dl	.handler_context_restore
 dl	kthread.core
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.core
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.exit
 dl	kthread.exit
 dl	.handler_context_restore
 dl	.handler_context_restore
 dl	.handler_continue
 dl	.handler_stop
 dl	.handler_stop
 dl	.handler_stop
 dl	.handler_stop
 dl	kthread.core
	
.raise:
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

.kill:
; Send signal to thread
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
	jr	z, .kill_no_thread
	inc	hl
	ld	iy, (hl)
	dec	hl
; b = signal, iy = thread adress
; push on the thread stack all the context
; todo check permission here (first byte of bitmap is permission level)    
	ld	a, c
; permission of the (current thread-1) < signaled thread (if equal)
	cp	a, (hl)
	jr	nc, .kill_no_permission
; check the signal to send
	ld	a, b
	or	a, a
	jr	z, .kill_no_signal
; so now, I have iy = thread to signal, still the signal in a, data in de
; push the context on the thread stack
	push	ix
	ld 	ix, (iy+KERNEL_THREAD_STACK)
	ld	hl, .handler
	ld	(ix-3), hl
	sbc	hl, hl
	ld	(ix-6), hl
	ld	(ix-9), iy
	ld	(ix-12), de
	ld	(ix-15), hl
	ld	(ix-18), hl
	ld	h, a
	ld	(ix-21), hl
; adjust stack position
	lea	hl, ix-21
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
	tstei
	ld	a, b
	scf
	sbc	hl, hl
	pop	de
	pop	bc
	pop	iy
	ret

.wait:
; wait for a signal
	jp	kthread.suspend

.timedwait:
; sleep for a duration, can be waked by signal
    ret
    
; change thread signal list ; 
.procmask: 
    ret
