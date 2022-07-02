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



;define	SIGHUP		1           ; Hangup / death control ; TERM
;define	SIGINT		2           ; Interrupt keyboard     ; TERM
;define	SIGILL		3           ; Illegal instruction    ; CORE
;define	SIGTRAP		4           ; Trace/breakpoint trap  ; CORE
;define	SIGKILL		5           ; KILL                   ; TERM (unblockable)
;define	SIGCONT		6           ; continue               ; CONT (unblockable)
;define	SIGSTOP		7           ; Stop process           ; STOP (unblockable)
;define	SIGQUIT		8           ; Quit                   ; CORE
;define	SIGABRT		9           ; abort signal (abort)   ; CORE
;define	SIGFPE		10          ; Floatpoint exception   ; CORE
;define	SIGUSR1		11          ; User                   ; TERM
;define	SIGSEGV		12          ; Segmentation fault     ; CORE
;define	SIGUSR2		13          ; User                   ; TERM
;define	SIGPIPE		14          ; Broken pipe            ; TERM
;define	SIGALRM		15          ; timer signal (alarm)   ; TERM
;define	SIGTERM		16          ; Termination signal     ; TERM
;define	SIGCHLD		17          ; child stopped (unused) ; IGN
;define	SIGTSTP		18          ; Stop typed at term     ; STOP
;define	SIGTTIN		19          ; Terminal input         ; STOP
;define	SIGTTOU		20          ; Terminal output        ; STOP
;define	SIGSYS		21          ; Bad syscall            ; CORE
