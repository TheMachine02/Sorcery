define	KERNEL_SPIN_LOCK         0
define	KERNEL_SPIN_LOCK_SIZE    1
define	KERNEL_SPIN_LOCK_BIT     0
define	KERNEL_SPIN_LOCK_MAGIC   0xFE

define	KERNEL_MUTEX             0
define	KERNEL_MUTEX_SIZE        2
define	KERNEL_MUTEX_LOCK        0
define	KERNEL_MUTEX_LOCK_BIT    0
define	KERNEL_MUTEX_OWNER       1
define	KERNEL_MUTEX_MAGIC       0xFE

macro tstdi
	ld	a, i
	di
	push	af
end macro

macro tstei
	pop	af
	jp	po, $+5
	ei
end macro

macro retei
	pop	af
	ret	po
	ei
	ret
end macro

kspin_lock:

.acquire:
	sra	(hl)
	jr	c, .acquire
	ret
    
.release:
.init:
	ld	(hl), KERNEL_SPIN_LOCK_MAGIC
	ret
    
kmutex:
; same method
; hl = mutex byte

.lock:
	sra	(hl)
	jr	nc, .lock_acquire
	call	kthread.yield
	jr	.lock
.lock_acquire:
	push	de
	ex	de, hl
	ld	hl, (kthread_current)
	ld	l, (hl)
	ex	de, hl
	inc	hl
	ld	(hl), e
	dec	hl
	pop	de
	ret

.unlock:
	push	de
	ld	de, (kthread_current)
	ld	a, (de)
	inc	hl
	cp	a, (hl)
	dec	hl
	pop	de
	ret	nz  ; not current owning thread, you can't unlock !
        
.init:
	inc	hl
	ld	(hl), NULL
	dec	hl
	ld	(hl), KERNEL_MUTEX_MAGIC
	ret
