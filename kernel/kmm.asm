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
; reserved mask : locked, unevictable, to thread 0
define	KERNEL_MM_RESERVED_MASK		00101000b
define	KERNEL_MM_RESERVED_SIZE		4096
; the first 256 bytes shouldn't be init by mm module
define	KERNEL_MM_PROTECTED_INIT	256
define	KERNEL_MM_PROTECTED_SIZE	4096
; null adress reading always zero, but faster
define	KERNEL_MM_NULL			$E40000

define	KERNEL_MEMORY_BLOCK_DATA	0
define	KERNEL_MEMORY_BLOCK_FREE	2
define	KERNEL_MEMORY_BLOCK_PREV	3
define	KERNEL_MEMORY_BLOCK_NEXT	6
define	KERNEL_MEMORY_BLOCK_PTR		9
define	KERNEL_MEMORY_BLOCK_SIZE	12
define	KERNEL_MEMORY_MALLOC_THRESHOLD	64

; memory region for gestion (512 bytes table, first 256 bytes are flags, next either count or thread_id)
define	kmm_ptlb_map			$D00E00
; memory region for mapping cache page to virtual inode
; 2 bytes per inode
define	kmm_cache_map			$D00C00

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
	ld	a, $7D
	out0 (0x20), a
	dec	a
	out0 (0x23), a
	ld	a, $88
	out0 (0x21), a
	out0 (0x24), a
	ld	a, $D1
	out0 (0x22), a
	out0 (0x25), a
end if
; setup previleged executable code (end of the OS)
	ld	a, $06
	out0	($1F), a
	xor	a, a
	out0	($1D), a
	out0	($1E), a
	ld	hl, KERNEL_MM_NULL
	ld	de, KERNEL_MM_RAM + KERNEL_MM_PROTECTED_INIT
	ld	bc, KERNEL_MM_RAM_SIZE - KERNEL_MM_PROTECTED_INIT
	ldir
	ld	hl, .init_ptlb_map
	ld	de, kmm_ptlb_map
	inc	b
	inc	b
	ldir
	ret
	
.init_ptlb_map:
if CONFIG_USE_BOOT_PATCH
 db 4	dup KERNEL_MM_RESERVED_MASK
 db 252	dup KERNEL_MM_PAGE_FREE_MASK
else
 db 4	dup KERNEL_MM_RESERVED_MASK
 db 89	dup KERNEL_MM_PAGE_FREE_MASK
; $D177AE > stupid interrupt check (one day, with some boot patch ..)
 db KERNEL_MM_RESERVED_MASK
 db 162	dup KERNEL_MM_PAGE_FREE_MASK
end if
 db 256 dup NULL

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
	call	ksignal.kill
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
	cp	a, KERNEL_MM_PAGE_LOCK_MASK
; lock for write
	jp	z, .segfault_critical
	
; notify if = MAX_READER or if = zero
	or	a, a
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
	ld	a, (hl)
	or	a, a
	jr	z, .page_unlock_exit
	push	iy
	ld	b, a
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

.page_map:
; register b is page index wanted, return hl = adress or -1 if error
; register c is page count wanted
; register e is flags
; destroy bc, destroy a, destroy de
	ld	hl, (kthread_current)
	ld	a, (hl)
.thread_map:
	dec	c
	jr	z, .page_map_fast
; map c page from b page to thread a
	ld	e, c
	ld	hl, i
	push	af
	di
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
.page_map_parse:
; fast search for free page
	cpir
	jp	po, .page_map_no_free
; else check we have at least c page free
	ld	d, e
.map_page_lenght:
	cpi
	jp	po, .page_map_no_free
	jr	nz, .page_map_parse
	dec	d
	jr	nz, .map_page_lenght
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
.map_page_owner:
	ld	(hl), 0
	inc	h
	ld	(hl), a
	dec	h
	inc	hl
	djnz	.map_page_owner
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

.page_map_fast:
; register b is page index wanted, return hl = adress or -1 if error, e is flag (SHARED or not)
; destroy bc, destroy hl
; get kmm_ptlb_map adress
	ld	hl, i
	push	af
	di
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
	cpl
	ld	bc, 0
	ld	c, a
	inc	bc
	ld	a, KERNEL_MM_PAGE_FREE_MASK
; fast search for free page
	cpir
	jp	po, .page_map_no_free
	dec	hl
	ld	(hl), 0
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

mmap:
; map file page as anonymous shared data
; actually get it out of the cache and give a fixed adress for it
	ret
munmap:
; return file page to cache
	ret

kmalloc:
; Memory allocation routine
; REGSAFE and ERRNO compliant
; void* malloc(size_t size)
; register HL is size
; return NULL if failed and errno set or void* otherwise
; also set carry if failed
	push	af
	push	de
	ex	de, hl
	push	ix
	push	bc
	ld	ix, (kthread_current)
	ld	ix, (ix+KERNEL_THREAD_HEAP)
; reset carry flag for loop sbc
	or	a, a
.malloc_loop:
	bit	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	jr	z, .malloc_test_block
.malloc_next_block:
	ld	a, (ix+KERNEL_MEMORY_BLOCK_NEXT+2)
	or	a, a
	jr	z, .malloc_errno
	ld	ix, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	jr	.malloc_loop
; so, we didn't find any memory block large enough for us
; let's try to map more memory to the thread
; first, get size+BLOCK_HEADER / block size 
; ix is the last block, it's important !
; .malloc_break:
; 	ld	hl, KERNEL_MEMORY_BLOCK_SIZE
; 	add	hl, de
; 	dec	sp
; 	push	hl
; 	ld	a, l
; 	inc	sp
; 	ex	(sp), hl
; ; we need to round UP here	
; 	or	a, a
; 	jr	z, $+3
; 	inc	hl
; 	srl	h
; 	rr	l
; 	jr	nc, $+3
; 	inc	hl
; 	srl	h
; 	rr	l
; 	jr	nc, $+3
; 	inc	hl
; 	ld	b, l
; 	pop	hl
; 	ld	hl, KERNEL_MMU_RAM
; 	call	kmmu.map_block
; ; block a certain number of block
; ; return hl as the adress
; ; de is still size
; 	jp	c, .malloc_errno
; 	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), hl
; ; there is a *new block*
; ; create the block, point it to ix, and then jump to test block
; 	push	hl
; ; b * KERNEL_MMU_PAGE_SIZE/256 > bc
; 	or	a, a
; 	sbc	hl, hl
; 	ld	h, b
; 	add	hl, hl
; 	add	hl, hl
; 	ld	bc, -KERNEL_MEMORY_BLOCK_SIZE
; 	add	hl, bc
; ; this is the size of the block
; 	lea	bc, ix+0
; 	pop	ix
; 	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), hl
; 	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), bc
; 	ld	hl, NULL
; 	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), hl
; 	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
; 	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), hl
.malloc_test_block:
	ld	hl, (ix+KERNEL_MEMORY_BLOCK_DATA)
	sbc	hl, de
	jr	c, .malloc_next_block    
.malloc_mark_block:
; thresold to slipt the block. If the size left is >= 64 bytes, then slipt
	ld	bc, KERNEL_MEMORY_MALLOC_THRESHOLD
	sbc	hl, bc
	jr	nc, .malloc_split_block
; no split, so just return current block \o/ mark it used
	set	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), hl
	pop	bc
	pop	ix
	pop	de
	pop	af
	or	a, a
	ret
.malloc_split_block:
	push	iy
	ld	bc, KERNEL_MEMORY_MALLOC_THRESHOLD - KERNEL_MEMORY_BLOCK_SIZE
	add	hl, bc
	lea	iy, ix+KERNEL_MEMORY_BLOCK_SIZE
	add	iy, de	; this is the new block adress
	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), de
	set	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	ld	(iy+KERNEL_MEMORY_BLOCK_DATA), hl
	ld	hl, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), iy
	ld	(iy+KERNEL_MEMORY_BLOCK_PREV), ix
	ld	(iy+KERNEL_MEMORY_BLOCK_NEXT), hl
	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), hl
	ld	ix, (iy+KERNEL_MEMORY_BLOCK_NEXT)
	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), iy
	lea	bc, iy+KERNEL_MEMORY_BLOCK_SIZE
	ld	(iy+KERNEL_MEMORY_BLOCK_PTR), bc
	pop	iy
	pop	bc
	pop	ix
	pop	de
	pop	af
	or	a, a
	ret
.malloc_errno:
	ld	ix, (kthread_current)
	ld	(ix+KERNEL_THREAD_ERRNO), ENOMEM
	pop	bc
	pop	ix
	pop	de
	pop	af
	scf
	sbc	hl, hl
	ret

; krealloc:
; ; Memory realloc routine
; ; REGSAFE and ERRNO compliant
; ; void* realloc(void* ptr, size_t newsize)
; ; if ptr is NULL, return silently
; 	push	ix
; 	push	de
; 	push	hl
; 	pop	ix
; ; try to mask the adress, ie >= D00000
; 	ex	de, hl
; 	ld	hl, $300000
; 	add	hl, de
; 	jr	nc, .realloc_error
; ; check if adress is valid
; 	ld	hl, (ix-3)
; 	or	a, a
; 	sbc	hl, de
; 	jr	nz, .realloc_error
; ; invalid adress, return quietly
; ; TODO try to merge with the next block, if free, to avoid copy
; ; TODO if resize to smaller size, shrink the current block instead allocating new one
; ; read the next block size and if it is free
; ; else, malloc and copy and free
; ; 	lea	ix, ix-KERNEL_MEMORY_BLOCK_SIZE
; ; 	ld	a, (ix+KERNEL_MEMORY_BLOCK_NEXT+2)
; ; 	or	a, a
; ; 	jr	z, .realloc_malloc_cpy
; ; 	ld	iy, (iy+KERNEL_MEMORY_BLOCK_NEXT)
; ; 	bit	7, (iy+KERNEL_MEMORY_BLOCK_FREE)
; ; 	jr	nz, .realloc_malloc_cpy
; ; is size enough ?
; ; 	ld	hl, (ix+KERNEL_MEMORY_BLOCK_DATA)
; ; 	ld	de, (iy+KERNEL_MEMORY_BLOCK_DATA)
; ; 	add	hl, de
; ; clean out the *used* mask
; ; 	ld	de, $800000
; ; 	add	hl, de
; ; 	or	a, a
; ; 	sbc	hl, bc	; if nc, we are good ! merge ix and iy, return ix+12
; ; 	jr	c, .realloc_malloc_cpy
; .realloc_malloc_cpy:
; 	or	a, a
; 	sbc	hl, hl
; 	adc	hl, bc
; 	jr	z, .realloc_free
; 	call	kmalloc
; 	jr	c, .realloc_error
; 	push	hl
; 	ex	de, hl
; 	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
; ; copy for the new size only
; 	ldir
; 	pop	de
; .realloc_free:
; 	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
; 	call	kfree
; 	ex	de, hl
; 	pop	de
; 	pop	ix
; 	or	a, a
; 	ret
; .realloc_error:
; ; set hl = NULL, ERRNO set appropriately
; 	or	a, a
; 	sbc	hl, hl
; 	pop	de
; 	pop	ix
; 	scf
; 	ret
	
kfree:
; Memory free routine
; REGSAFE and ERRNO compliant
; void free(void* ptr)
; if ptr is NULL, return silently
; behaviour is undetermined if ptr wasn't malloc'ed before
	push	af
	push	ix
	push	iy
	push	de
	push	hl
; try to mask the adress, ie >= D00000
	ex	de, hl
	ld	hl, $300000
	add	hl, de
	jr	nc, .free_exit
; check if adress is valid
	ld	hl, (ix-3)
	xor	a, a
	sbc	hl, de
	jr	nz, .free_exit	; invalid adress, return quietly
; else, free the block and try to merge with prev & next
	push	de
	pop	ix
	lea	ix, ix-KERNEL_MEMORY_BLOCK_SIZE
	res	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	ld	iy, (ix+KERNEL_MEMORY_BLOCK_PREV)
	or	a, (ix+KERNEL_MEMORY_BLOCK_PREV+2)
	jr	z, .free_merge_pblock
	bit	7, (iy+KERNEL_MEMORY_BLOCK_FREE)
	jr	nz, .free_merge_pblock	
	ld	hl, (iy+KERNEL_MEMORY_BLOCK_DATA)
	ld	de, (ix+KERNEL_MEMORY_BLOCK_DATA)
	add	hl, de
	ld	de, KERNEL_MEMORY_BLOCK_SIZE
	add	hl, de
	ld	(iy+KERNEL_MEMORY_BLOCK_DATA), hl
	ld	ix, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	ld	(iy+KERNEL_MEMORY_BLOCK_NEXT), ix
; changed the prev of the next block
	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), iy
	lea	ix, iy+0
.free_merge_pblock:
	ld	iy, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	ld	a, (ix+KERNEL_MEMORY_BLOCK_NEXT+2)
	or	a, a
	jr	z, .free_exit
	bit	7, (iy+KERNEL_MEMORY_BLOCK_FREE)
	jr	nz, .free_exit
	ld	hl, (iy+KERNEL_MEMORY_BLOCK_DATA)
	ld	de, (ix+KERNEL_MEMORY_BLOCK_DATA)
	add	hl, de
	ld	de, KERNEL_MEMORY_BLOCK_SIZE
	add	hl, de
	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), hl
	ld	iy, (iy+KERNEL_MEMORY_BLOCK_NEXT)
	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), iy
; changed the prev of the next block
	ld	(iy+KERNEL_MEMORY_BLOCK_PREV), ix
.free_exit:
	pop	hl
	pop	de
	pop	iy
	pop	ix
	pop	af
	ret
