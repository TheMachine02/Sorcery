; memory management routine
; autor : TheMachine02
define	KERNEL_MM_PAGE_SIZE		1024
; mask
define	KERNEL_MM_PAGE_FREE_MASK	128
define	KERNEL_MM_PAGE_CACHE_MASK	64
define	KERNEL_MM_PAGE_SHARED_MASK	32
define	KERNEL_MM_PAGE_UNEVICTABLE_MASK	16
define	KERNEL_MM_PAGE_DIRTY_MASK	8
define	KERNEL_MM_PAGE_LOCK_MASK	7
define	KERNEL_MM_PAGE_MAX_READER	6	; 7 is reserved for write lock
; bit
define	KERNEL_MM_PAGE_FREE		7
define	KERNEL_MM_PAGE_CACHE		6
define	KERNEL_MM_PAGE_SHARED		5
define	KERNEL_MM_PAGE_UNEVICTABLE	4
define	KERNEL_MM_PAGE_DIRTY		3
define	KERNEL_MM_PAGE_LOCK		0	; bit 0 to bit 2
; physical device
define	KERNEL_MM_RAM			$D00000
define	KERNEL_MM_RAM_SIZE		$040000
define	KERNEL_MM_FLASH			$000000
define	KERNEL_MM_FLASH_SIZE		$400000
; reserved mask : locked, unevictable, to thread 0
define	KERNEL_MM_RESERVED_MASK		00101000b
define	KERNEL_MM_RESERVED_SIZE		4096
; the first 4096 bytes shouldn't be init by mm module
define	KERNEL_MM_PROTECTED_SIZE	4096
; null adress reading always zero, but faster
define	KERNEL_MM_NULL			$E40000
; poison for illegal jp / derefence
define	KERNEL_HW_POISON		$C7

macro	trap
	db $FD, $FF
end	macro

; link between cache page and inode (so inode can be updated when droping cache pages)
define	kcache_inode_map		$D00F00
; memory region for gestion (512 bytes table, first 256 bytes are flags, next either count or thread_id)
define	kmm_ptlb_map			$D00500

kmm:

.init:
; setup memory protection
	di
if CONFIG_USE_BOOT_PATCH=1
	xor	a, a
	out0	($20), a
	out0	($21), a
	dec	a
	out0	($23), a
	ld	a, $0F
	out0	($24), a
	ld	a, $D0
	out0	($22), a
	out0	($25), a
else
	ld	a, $00
	out0 ($20), a
	dec	a
	out0 ($23), a
	ld	a, $88
	out0 ($21), a
	out0 ($24), a
	ld	a, $D1
	out0 ($22), a
	out0 ($25), a
end if
	ld	hl, KERNEL_MM_RAM + KERNEL_MM_PROTECTED_SIZE
	ld	de, KERNEL_MM_RAM + KERNEL_MM_PROTECTED_SIZE + 1
	ld	bc, KERNEL_MM_RAM_SIZE - KERNEL_MM_PROTECTED_SIZE - 1
	ld	(hl), KERNEL_HW_POISON
	ldir
	ret

 .page_perm_rw:
; b = page
; return nc if permission is okay
; 	return nz if cache or shared page or anonymous
; 	return z if thread mapped page
; return c is segfaulted
; 	return nz
; return de ptlb, destroy a, return hl current_thread
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	rla
; KERNEL_MM_FREE
	jr	c, .segfault_permission
	ld	hl, (kthread_current)
	and	(KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_SHARED_MASK) shl 1
	ret	nz
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	ret	z
	jr	.segfault_permission
 
.page_perm_rwox:
; b = page
; return nc if permission is okay
; 	return z if thread mapped page
; return c is segfaulted
; 	return nz
; return de ptlb, destroy a, return hl current_thread
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	and	KERNEL_MM_PAGE_FREE_MASK or KERNEL_MM_PAGE_CACHE_MASK
	jr	nz, .segfault_permission
; are we the owner ?
	ld	hl, (kthread_current)
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	ret	z

.segfault_permission:
	pop	bc	; pop the routine adress
.segfault_critical:
	pop	af	; this is interrupt status
	jp	po, .segfault
	ei
.segfault:
	ld	hl, (kthread_current)
	ld	c, (hl)
	ld	a, SIGSEGV
	call	signal.kill
; well, clean up and try for better ?
; interrupts are enabled and wish for the best
	scf
	sbc	hl, hl
; Say, I WISH YOU THE BEST
	ret
 
; if lock for read, multiple thread can read it
; if lock for write, no one can lock for read or write
; unlock read, does unlock if every thread finished reading
 
.page_lock_read:
; lock the page for read. Support concurrent read
; b = page
; everyone can lock cache page as it is mandatory for read / write
; you can only lock your own page or shared page or cache page
; can't lock free page
; please note that this routine will use interrupt to wait
; destroy bc, hl, de
	ld	hl, i
	push	af
	di
; page_perm_rw
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	rla
	jp	c, .segfault_critical
	ld	hl, (kthread_current)
	and	(KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_SHARED_MASK) shl 1
	jr	nz, .page_lock_r
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	jp	nz, .segfault_critical
.page_lock_r:
; check for lock
	ex	de, hl
	ld	a, (hl)
	and	KERNEL_MM_PAGE_LOCK_MASK
; are we locked for write ?
	cp	a, KERNEL_MM_PAGE_LOCK_MASK
	jr	z, .page_lock_r_entry
	cp	a, KERNEL_MM_PAGE_MAX_READER
	jr	nz, .page_lock_set_r
; let's wait for the page to relinquish the lock
.page_lock_r_entry:
	ex	de, hl
	ld	bc, KERNEL_THREAD_IO
	add	hl, bc
	ld	(hl), e
	or	a, a
	sbc	hl, bc
; hl = thread > iy
	push	hl
	ex	(sp), iy
	ex	de, hl
.page_lock_wait_r:
	push	hl
	call	task_switch_uninterruptible
	call	task_yield
	pop	hl
	di
	ld	a, (hl)
	and	KERNEL_MM_PAGE_LOCK_MASK
	cp	a, KERNEL_MM_PAGE_MAX_READER
	jr	z, .page_lock_wait_r
	pop	iy
.page_lock_set_r:
; sanity check again
	bit	KERNEL_MM_PAGE_FREE, (hl)
	jr	nz, .segfault_critical
	inc	(hl)
; we have locked the page, increase reference count if cache page
	ld	a, (hl)
	and	KERNEL_MM_PAGE_CACHE_MASK
	jr	z, .page_lock_r_exit
	inc	h
	inc	(hl)
	jr	nz, $+3
; case = overflow
	dec	(hl)
	dec	h
.page_lock_r_exit:
	pop	af
	ret	po
	ei
	ret
 
.page_lock_write:
; lock the page for write, all read must be finished to be locked for write. No one can read while locked for write.
; b = page
; everyone can lock cache page as it is mandatory for read / write
; you can only lock your own page or shared page or cache page
; can't lock free page
; please note that this routine will use interrupt to wait
; destroy bc, hl, de
	ld	hl, i
	push	af
	di
; page_perm_rw
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	rla
	jp	c, .segfault_critical
	ld	hl, (kthread_current)
	and	(KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_SHARED_MASK) shl 1
	jr	nz, .page_lock_w
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	jp	nz, .segfault_critical
.page_lock_w:
; check for lock
	ex	de, hl
	ld	a, (hl)
	and	KERNEL_MM_PAGE_LOCK_MASK
	jr	z, .page_lock_set_w
; let's wait for the page to relinquish the lock
	ex	de, hl
	ld	bc, KERNEL_THREAD_IO
	add	hl, bc
	ld	(hl), e
	or	a, a
	sbc	hl, bc
; hl = thread
	push	hl
	ex	(sp), iy
	ex	de, hl
.page_lock_wait_w:
	push	hl
	call	task_switch_uninterruptible
	call	task_yield
	pop	hl
	di
	ld	a, (hl)
	and	KERNEL_MM_PAGE_LOCK_MASK
	jr	nz, .page_lock_wait_w
	pop	iy
.page_lock_set_w:
; sanity check again
	bit	KERNEL_MM_PAGE_FREE, (hl)
	jp	nz, .segfault_critical
	ld	a, KERNEL_MM_PAGE_LOCK_MASK
	or	a, (hl)
	ld	(hl), a
; we have locked the page, increase reference count if cache page
	and	KERNEL_MM_PAGE_CACHE_MASK
	jr	z, .page_lock_w_exit
	inc	h
	inc	(hl)
	jr	nz, $+3
; case = overflow
	dec	(hl)
	dec	h
.page_lock_w_exit:
	pop	af
	ret	po
	ei
	ret

.page_unlock_read:
; unlock the page and notify waiting thread if necessary
; b = page
; destroy bc, hl, de
	ld	hl, i
	push	af
	di
; page_perm_rw
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	rla
	jp	c, .segfault_critical
	ld	hl, (kthread_current)
	and	(KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_SHARED_MASK) shl 1
	jr	nz, .page_unlock_r
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	jp	nz, .segfault_critical
.page_unlock_r:
	ex	de, hl
; lock lifted
	ld	a, KERNEL_MM_PAGE_LOCK_MASK
	and	a, (hl)
; notify if = MAX_READER or if = zero	
	jp	z, .segfault_critical
	cp	a, KERNEL_MM_PAGE_LOCK_MASK
; lock for write
	jp	z, .segfault_critical
	dec	(hl)
	jr	z, .page_unlock_shared
	cp	a, KERNEL_MM_PAGE_MAX_READER
	jr	z, .page_unlock_shared
	pop	af
	ret	po
	ei
	ret
	
.page_unlock_write:
; unlock the page and notify waiting thread if necessary
; b = page
; destroy bc, hl, de
	ld	hl, i
	push	af
	di
; page_perm_rw
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	rla
	jp	c, .segfault_critical
	ld	hl, (kthread_current)
	and	(KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_SHARED_MASK) shl 1
	jr	nz, .page_unlock_w
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	jp	nz, .segfault_critical
.page_unlock_w:
	ex	de, hl
; lock lifted
	ld	a, (hl)
	ld	d, KERNEL_MM_PAGE_LOCK_MASK
	and	a, d
	cp	a, d
; it wasn't locked for write ? WAIT WHAT
	jp	nz, .segfault_critical
; lift the lock
	ld	a, (hl)
	xor	a, d
	ld	(hl), a

.page_unlock_shared:
; notify waiting thread, assume lock was lifted
	ld	hl, kthread_queue_retire
	ld	b, (hl)
	inc	b
; 	or	a, a
	jr	z, .page_unlock_exit
	push	iy
	inc	hl
	ld	iy, (hl)
	ld	a, c
.page_unlock_notify:
	ld	a, (iy+KERNEL_THREAD_IO)
	ld	ix, (iy+QUEUE_NEXT)
	cp	a, c
	jr	nz, .page_unlock_next
	ld	(iy+KERNEL_THREAD_IO), 0
	call	kthread.resume
.page_unlock_next:
	lea	iy, ix+0
	djnz	.page_unlock_notify
	pop	iy
.page_unlock_exit:
	pop	af
	ret	po
	ei
	ret

.page_relock:
; change a write lock page to a read lock page
; b = page
; destroy bc, hl, de
	ld	hl, i
	push	af
	di
; page_perm_rw
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	rla
	jp	c, .segfault_critical
	ld	hl, (kthread_current)
	and	(KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_SHARED_MASK) shl 1
	jr	nz, .page_unlock_rw
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	jp	nz, .segfault_critical
.page_unlock_rw:
; lift lock and relock
	ld	a, (de)
	ld	h, KERNEL_MM_PAGE_LOCK_MASK
	and	a, h
	cp	a, h
; it wasn't locked for write ? WAIT WHAT
	jp	nz, .segfault_critical
; lift the lock
	ld	a, (de)
	xor	a, h
	inc	a
	ld	(de), a
	jr	.page_unlock_shared
	
.page_map:
; register b is page index wanted, return hl = adress or -1 if error
; register c is page count wanted
; destroy bc, destroy a, destroy de
	ld	hl, (kthread_current)
	or	a, a
	ld	a, (hl)
.thread_map:
	dec	c
	ld	e, c
	jr	z, .page_map_single
; map c page from b page to thread a
	ld	hl, i
	push	af
	ld	a, b
	add	a, c
	jp	c, .segfault_critical
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
	cpl
	ld	bc, 0
	ld	c, a
	inc	bc
	ld	a, KERNEL_MM_PAGE_FREE_MASK
	di
.page_map_parse:
; fast search for free page
	cpir
	jp	po, .page_map_no_free
; else check we have at least c page free
	ld	d, e
.page_map_length:
	cpi
	jp	po, .page_map_except
	jr	nz, .page_map_parse
	dec	d
	jr	nz, .page_map_length
.page_map_found:
; e is lenght, hl is last adress + 1
	dec	hl
	ld	a, l
	sub	a, e
	ld	l, a
; hl = start of the map, for e+1
	inc	e
	ld	b, e
	ld	c, l	; save l for latter
	pop	af
	push	af
.page_map_owner:
	ld	(hl), 0
	inc	h
	ld	(hl), a
	dec	h
	inc	hl
	djnz	.page_map_owner
	pop	af
	jp	po, $+5
	ei
	or	a, a
	sbc	hl, hl
	ld	h, c
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MM_RAM
	add	hl, bc
	ret
.page_map_except:
	jp	nz, .page_map_no_free
	dec	d
	jr	z, .page_map_found
	jp	.page_map_no_free

.page_map_flags:
	ld	e, KERNEL_MM_PAGE_SHARED_MASK or KERNEL_MM_PAGE_CACHE_MASK
	xor	a, a
.page_map_single:
; register b is page index wanted, return hl = adress or -1 if error, e is flag (SHARED or not)
; destroy bc, destroy hl
; get kmm_ptlb_map adress
	ld	hl, i
	push	af
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
	cpl
	ld	bc, 0
	ld	c, a
	inc	bc
	ld	a, KERNEL_MM_PAGE_FREE_MASK
	di
; fast search for free page
	cpir
	jp	po, .page_map_no_free
	dec	hl
	ld	(hl), e
	inc	h
	pop	af
	ld	(hl), a
	jp	po, $+5
	ei
	dec	h
	ld	b, l
	or	a, a
	sbc	hl, hl
	ld	h, b
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MM_RAM
	add	hl, bc
	ret
.page_map_no_free:
; will need to reclaim cache memory page
	scf
	sbc	hl, hl
	pop	af
	scf
	ret	po
	ei
	ret

.thread_unmap:
; unmap all memory of a given thread
; sanity check guard, call by kernel
; of course, it is easy to bypass, but at least it is here
; mainly, what happen if you unmap yourself ? > CRASH
	pop	hl
	push	hl
	ld	bc, KERNEL_MM_RAM + KERNEL_MM_PROTECTED_SIZE
	or	a, a
	sbc	hl, bc
	jp	nc, .segfault
	ld	hl, kmm_ptlb_map + 256
	ld	bc, 256
	jr	.thread_unmap_find
.thread_unmap_loop:
	dec	hl
	dec	h
	bit	KERNEL_MM_PAGE_CACHE, (hl)
	call	z, .page_flush
	inc	h
	inc	hl
.thread_unmap_find:
	cpir
	jp	pe, .thread_unmap_loop
	ret

.page_unmap:
; register b is page index wanted
; register c is page count wanted to clean
; destroy hl, bc, a
	dec	c
	jr	z, .page_unmap_fast
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
	add	a, c
	jp	c, .segfault
; okay nice. Now, we will unmap page
; hl = first page
; check permission first
	inc	c
	ld	b, c
	ld	de, (kthread_current)
	ld	a, (de)
	ld	e, a	; thread pid
.page_unmap_cloop:
; page_perm_rwox
	ld	a, (hl)
	and	KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_FREE_MASK
	jp	nz, .segfault
	inc	h
	ld	a, e
	cp	a, (hl)
	jp	nz, .segfault
	dec	h
	call	.page_flush
	djnz	.page_unmap_cloop
	ret
	
.page_unmap_fast:
; register b is page index wanted
; destroy a, destroy hl, destroy bc, destroy de
; page_perm_rwox
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	and	KERNEL_MM_PAGE_FREE_MASK or KERNEL_MM_PAGE_CACHE_MASK
	jp	nz, .segfault
; are we the owner ?
	ld	hl, (kthread_current)
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	jp	nz, .segfault
	ex	de, hl
	
.page_flush:
; hl as the ptlb adress
	push	bc
	push	hl
	ld	c, l
	or	a, a
	sbc	hl, hl
	ld	h, c
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MM_RAM
	add	hl, bc
	ex	de, hl
	ld	hl, KERNEL_MM_NULL
	ld	bc, KERNEL_MM_PAGE_SIZE
	ldir
	pop	hl
; write first free_mask, so the page will be considered as free even if hell break loose and the thread is killed between the two following write
	ld	(hl), KERNEL_MM_PAGE_FREE_MASK
	inc	h
	ld	(hl), c
	dec	h
	pop	bc
	ret

; rst $0 : trap execute, illegal instruction
.page_flush_poison:
	ld	bc, KERNEL_MM_PAGE_SIZE - 1
; hl is address to poison
	ex	de, hl
	sbc	hl, hl
	adc	hl, de
	ld	(hl), KERNEL_HW_POISON
	inc	de
	ldir
	ret

.physical_to_ptlb:
; adress divided by page KERNEL_MM_PAGE_SIZE = 1024
	push	hl
	dec	sp
	pop	hl
	inc	sp
	ld	a, l
	srl	h
	rra
	srl	h
	rra
	ld	hl, kmm_ptlb_map
	ld	l, a
	ret
