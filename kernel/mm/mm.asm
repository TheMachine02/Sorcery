; memory management routine
define	KERNEL_MM_PAGE_SIZE		1024
; mask
define	KERNEL_MM_PAGE_FREE_MASK	128	; memory page is free
define	KERNEL_MM_PAGE_CACHE_MASK	64	; this is a cache page
define	KERNEL_MM_PAGE_UNEVICTABLE_MASK	32	; set page as not moveable
define	KERNEL_MM_PAGE_DIRTY_MASK	16	; only used if unevictable is z
define	KERNEL_MM_PAGE_USER_MASK	31	; owner mask in first byte of ptlb
; bit
define	KERNEL_MM_PAGE_FREE		7
define	KERNEL_MM_PAGE_CACHE		6
define	KERNEL_MM_PAGE_UNEVICTABLE	5
define	KERNEL_MM_PAGE_DIRTY		4
define	KERNEL_MM_PAGE_COUNTER		0	; the counter is the second byte of ptlb
; reserved mask : no-free, bound to thread 0
define	KERNEL_MM_RESERVED_MASK		0
; the first 32768 bytes shouldn't be init by mm module
define	KERNEL_MM_PROTECTED_SIZE	32768
; null adress reading always zero, but faster
define	KERNEL_MM_NULL			$E40000
; poison for illegal jp / derefence
define	KERNEL_HW_POISON		$C7
; physical device
define	KERNEL_MM_PHY_RAM		$D00000
define	KERNEL_MM_PHY_RAM_SIZE		$040000
define	KERNEL_MM_PHY_FLASH		$000000
define	KERNEL_MM_PHY_FLASH_SIZE	$400000
; the memory device as seen by the kernel
define	KERNEL_MM_GFP_RAM		KERNEL_MM_GFP_KERNEL * KERNEL_MM_PAGE_SIZE + KERNEL_MM_PHY_RAM
define	KERNEL_MM_GFP_RAM_SIZE		KERNEL_MM_PHY_RAM_SIZE - KERNEL_MM_GFP_KERNEL * KERNEL_MM_PAGE_SIZE
define	KERNEL_MM_GFP_KERNEL		32	; $D08000 : total kernel size
define	KERNEL_MM_GFP_USER		64	; $D10000 : start of user memory
define	KERNEL_MM_GFP_CRITICAL		28	; 4K of critical RAM area ? (TODO : to be defined)
; $D0 ... $D1 should be reserved to kernel / cache
; $D1 and after is thread and program memory
; this partition reduce fragmentation in the cache area (always map 1K at the time) and general memory fragmentation

macro	trap
	db $FD, $FF
end	macro

kmm:
; memory adress sanitizer in memory allocation ;
; read and write permission : every thread can write to an allocated page
; detect non allocated page write
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
	jr	c, .__segfault_permission
	ld	hl, (kthread_current)
	and	a, KERNEL_MM_PAGE_CACHE_MASK shl 1
	ret	nz
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	ret	z
	jr	.__segfault_permission

 ; read, write, execute permission
 ; detect if the page is a user page ; anything else segfault
.page_perm_rwox:
; b = page
; return nc if permission is okay
; 	return z if user mapped page
; return c is segfaulted
; 	return nz
; return de ptlb, destroy a, return hl current_thread
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	and	KERNEL_MM_PAGE_FREE_MASK or KERNEL_MM_PAGE_CACHE_MASK
	jr	nz, .__segfault_permission
; are we the owner ?
	ld	hl, (kthread_current)
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	ret	z
; segfault cleanup
.__segfault_permission:
	pop	bc	; pop the routine adress
.__segfault_critical:
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
	
;.page_map:
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
	ld	a, i
	push	af
	ld	a, b
	add	a, c
	jp	c, .__segfault_critical
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
	cpl
	ld	b, 0
	ld	c, a
	inc.s	bc
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
	ld	hl, KERNEL_MM_PHY_RAM shr 2
	ld	h, c
	add	hl, hl
	add	hl, hl
	ret
.page_map_except:
	jp	nz, .page_map_no_free
	dec	d
	jr	z, .page_map_found
	jp	.page_map_no_free

.page_map_single:
; register b is page index wanted, return hl = adress or -1 if error, e is flag (SHARED or not)
; destroy bc, destroy hl
; get kmm_ptlb_map adress
	ld	a, i
	push	af
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
	cpl
	ld	b, 0
	ld	c, a
	inc.s	bc
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
	ld	b, l
	ld	hl, KERNEL_MM_PHY_RAM shr 2
	ld	h, b
	add	hl, hl
	add	hl, hl
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
	ld	bc, KERNEL_MM_PHY_RAM + KERNEL_MM_PROTECTED_SIZE
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
	call	z, .flush_page
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
	jr	z, .unmap_page
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
	call	.flush_page
	djnz	.page_unmap_cloop
	ret
	
.unmap_page:
; register b is page index wanted
; destroy a, destroy hl, destroy bc, destroy de
; page_perm_rwox
	ld	de, kmm_ptlb_map
	ld	e, b
	ld	a, (de)
	and	a, KERNEL_MM_PAGE_FREE_MASK or KERNEL_MM_PAGE_CACHE_MASK
	jp	nz, .segfault
; are we the owner ?
	ld	hl, (kthread_current)
	inc	d
	ld	a, (de)
	dec	d
	cp	a, (hl)
	jp	nz, .segfault
	ex	de, hl
	
; rst $0 : trap execute, illegal instruction
.flush_page:
; hl as the ptlb adress
	push	bc
	push	hl
	ld	c, l
 	ld	hl, KERNEL_MM_PHY_RAM shr 2
	ld	h, c
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MM_PAGE_SIZE - 1
	ex	de, hl
	sbc	hl, hl
	adc	hl, de
	ld	(hl), KERNEL_HW_POISON
	inc	de
	ldir
	pop	hl
; write first free_mask, so the page will be considered as free even if hell break loose and the thread is killed between the two following write
	ld	(hl), KERNEL_MM_PAGE_FREE_MASK
	inc	h
	ld	(hl), c
	dec	h
	pop	bc
	ret

.physical_to_ptlb:
; adress divided by page KERNEL_MM_PAGE_SIZE = 1024
assert KERNEL_MM_PAGE_SIZE = 1024
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

.map_page:
; register b is page index wanted, return hl = adress and a = page or -1 if error with a=error and c set
; de is full tlb flag
; destroy bc, destroy hl
; get kmm_ptlb_map adress
	ld	a, i
	push	af
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
; sanity check ;
; b > base kernel memory
	cp	a, KERNEL_MM_GFP_KERNEL
	jp	c, .__segfault_critical
	cpl
	ld	b, 0
	ld	c, a
	inc.s	bc
	ld	a, KERNEL_MM_PAGE_FREE_MASK
	di
; fast search for free page
	cpir
	jp	po, .__map_page_full
	dec	hl
	ld	(hl), e
	inc	h
	ld	(hl), d
	pop	af
	jp	po, $+5
	ei
	ld	a, l
	ld	hl, KERNEL_MM_PHY_RAM shr 2
	ld	h, a
	add	hl, hl
	add	hl, hl
	ret
.__map_page_full:
; will need to reclaim memory page here
	scf
	sbc	hl, hl
	pop	af
	scf
	ld	a, ENOMEM
	ret	po
	ei
	ret
