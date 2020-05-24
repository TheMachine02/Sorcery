; C wrapper to call ;
; please note, C send parameters within stack as last pushed the first, first argument is pushed last = closest on stack
; return value in HL (or none)


	ld	hl, (ix + 6)		; int a
	ld	iy, (ix + 9)		; void* ucontext
