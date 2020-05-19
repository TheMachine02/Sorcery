define SIGHUP       1           ; Hangup / death control ; TERM
define SIGINT       2           ; Interrupt keyboard     ; TERM
define SIGQUIT      3           ; Quit                   ; CORE
define SIGILL       4           ; Illegal instruction    ; CORE
define SIGTRAP      5           ; Trace/breakpoint trap  ; CORE
define SIGABRT      6           ; abort signal (abort)   ; CORE
define SIGFPE       8           ; Floatpoint exception   ; CORE
define SIGKILL      9           ; KILL                   ; TERM (unblockable)
define SIGUSR1      10          ; User                   ; TERM
define SIGSEGV      11          ; Segmentation fault     ; CORE
define SIGUSR2      12          ; User                   ; TERM
define SIGPIPE      13          ; Broken pipe            ; TERM
define SIGALRM      14          ; timer signal (alarm)   ; TERM
define SIGTERM      15          ; Termination signal     ; TERM
define SIGCHLD      17          ; child stopped (unused) ; IGN
define SIGCONT      18          ; continue               ; CONT
define SIGSTOP      19          ; Stop process           ; STOP (unblockable)
define SIGTSTP      20          ; Stop typed at term     ; STOP
define SIGTTIN      21          ; Terminal input         ; STOP
define SIGTTOU      22          ; Terminal output        ; STOP
define SIGSYS       23          ; Bad syscall            ; CORE

ksignal:

.handler:
; this is called by the thread
; hl = data, a = signal code, iy is thread
; stack is context to restore
; note that signal can be masked in the KERNEL_THREAD_SIGNAL 8 bytes mask
    ex  de, hl
    ld  c, a
    ld  b, 3
    mlt bc
    ld  hl, .JUMP_TABLE
    add hl, bc
    ld  hl, (hl)
    jp  (hl)
.return_atomic:
    tstei
.return:
    pop	af
    pop de
    pop bc
    pop hl
    pop	iy
    pop ix
    ret
    
.sttin:
.sttou:
.ststp:
.sstop:
    tstdi
; thread is in active queue
; stop it anyway
	ld (iy+KERNEL_THREAD_STATUS), TASK_STOPPED
	ld	hl, kqueue_active
	call	kqueue.remove
	ld	hl, kqueue_retire
	call	kqueue.insert
	tstei
    pop	af
    pop de
    pop bc
    pop hl
    pop	iy
    pop ix
; it is stopped, so no thread run
    jp kthread.yield
    
.scont:
    tstdi
; check if status is stopped
    ld  a, (iy+KERNEL_THREAD_STATUS)
    cp  a, TASK_RUNNING
    jp  z, .return_atomic
    ld  (iy+KERNEL_THREAD_STATUS), TASK_RUNNING
    cp  a, TASK_STOPPED
    jp  z, .return_atomic
; task_interruptible
    ld  a, (iy+KERNEL_THREAD_IRQ)
    or  a, a
    jp  z, .return_atomic
    tstei
    pop	af
    pop de
    pop bc
    pop hl
    pop	iy
    pop ix
    jp  kthread.suspend
    
.shup:
.sint:
.sterm:    
.skill:
.susr1:
.susr2:
.spipe:
.salarm:
    jp  kthread.exit
    
.squit:
.sill:
.strap:
.sabort:
.sfpe:
.ssegv:
.ssys:
    jp  kthread.core
    
.schld:
    jp  .return

.raise:
    push hl
    ld  hl, (kthread_current)
    ld  c, (hl)
    pop  hl

.queue:
; pid, signal, data*
.kill:
; pid, signal
; a = signal, c = pid, hl = data (optionnal)
    push iy
    ld  b, a
    tstdi
    push hl
    ld  hl, kthread_pid_bitmap
    sla c
    sla c
    ld  l, c
    ld  c, (hl)
    inc hl
    ld  iy, (hl)
; b = signal, iy = thread adress
; push on the thread stack all the context
; todo check permission here (first byte of bitmap is permission level)    
    ld  de, (kthread_current)
    ld  a, (de)
    add a, a
    add a, a
    ld  l, a
    ld  a, c
    or  a, a
    jr  z, .kill_error_no_thread
    cp  a, (hl)
; if c < (hl) : carry
    pop hl
    jr  c, .kill_error_permission
; so now, I have iy = thread to signal, still the signal in b
; push the context on the thread stack
    push ix
    ld  ix, (iy+KERNEL_THREAD_STACK)
    ex  de, hl
    ld  hl, .handler
    ld  (ix-3), hl
;    ld  hl, NULL
    sbc hl, hl
    ld  (ix-6), hl
    ld  (ix-9), iy
    ld  (ix-12), de
    ld  (ix-15), hl
    ld  (ix-18), hl
    ld  h, b
; af
    ld  (ix-21), hl
; adjust stack position
    lea hl, ix-21
    ld  (iy+KERNEL_THREAD_STACK), hl
    pop ix
; change state of the thread based on the context
; if state is RUNNING or INTERRUPTIBLE or STOPPED, 
; state UNINTERRUPTIBLE : can't change the queue, signal will be processed once the thread resume
    ld  a, (iy+KERNEL_THREAD_STATUS)
    cp  a, TASK_UNINTERRUPTIBLE
    jr  z, .kill_skip_resume
    or  a, a
    jr  z, .kill_skip_queue
	ld	hl, kqueue_retire
	call	kqueue.remove
	ld	hl, kqueue_active
	call	kqueue.insert
.kill_skip_queue:
	pop af
	pop iy
	ret po ; if interrupt disable, we can't yield
	ei
    jp  kthread.yield
.kill_error_no_thread:
    pop hl
.kill_error_permission:
    tstei
    pop iy
    scf
    ret
.kill_skip_resume:
    tstei
    pop iy
    or  a, a
    ret
    
.wait:
    jp    kthread.suspend

.timedwait:
    ret
    
; change thread signal list ; 
.procmask: 
    ret
    
.JUMP_TABLE:
dl NULL
dl .shup
dl .sint
dl .squit
dl .sill
dl .strap
dl .sabort
dl NULL
dl .sfpe
dl .skill
dl .susr1
dl .ssegv
dl .susr2
dl .spipe
dl .salarm
dl .sterm
dl NULL
dl .schld
dl .scont
dl .sstop
dl .ststp
dl .sttin
dl .sttou
dl .ssys
