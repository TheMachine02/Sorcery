; memory management routine
define	KERNEL_MM_PAGE_SIZE		1024
; mask
define	KERNEL_MM_PAGE_FREE_MASK	128	; memory page is free
define	KERNEL_MM_PAGE_CACHE_MASK	64	; this is a cache page
define	KERNEL_MM_PAGE_UNEVICTABLE_MASK	32	; set page as not moveable
define	KERNEL_MM_PAGE_DIRTY_MASK	16	; only used if unevictable is z
define	KERNEL_MM_PAGE_USER_MASK	15	; owner mask in first byte of ptlb
define	KERNEL_MM_PAGE_USER_DATA	1	; user data
define	KERNEL_MM_PAGE_INODE		0	; the inode number for cache page is stored in 2 bytes overlapping flag byte
define	KERNEL_MM_PAGE_LRU		2	; the decay value is stored in the third bytes of ptlb
; bit
define	KERNEL_MM_PAGE_FREE		7
define	KERNEL_MM_PAGE_CACHE		6
define	KERNEL_MM_PAGE_UNEVICTABLE	5
define	KERNEL_MM_PAGE_DIRTY		4
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
define	KERNEL_MM_GFP_RAM_SIZE		KERNEL_MM_PHY_RAM_SIZE - (KERNEL_MM_GFP_KERNEL * KERNEL_MM_PAGE_SIZE)
define	KERNEL_MM_GFP_KERNEL		32	; $D08000 : total kernel size
define	KERNEL_MM_GFP_USER		64	; $D10000 : start of user memory
define	KERNEL_MM_GFP_CRITICAL		28	; 4K of critical RAM area ? (TODO : to be defined)
define	KERNEL_MM_GFP_USER_COMPAT	106	; $D1A800 : compat
define	KERNEL_MM_PAGE_MAX		256

; $D0 ... $D1 should be reserved to kernel / cache
; $D1 and after is thread and program memory
; this partition reduce fragmentation in the cache area (always map 1K at the time) and general memory fragmentation

macro	trap
	db $FD, $FF
end	macro

mm:
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

.map_user_pages:
; map pages to a thread with pid = a
	ld	d, a
	ld	e, 0
	
.map_pages:
; register b is page index wanted, return hl = adress or -1 if error
; register c is page count wanted
; de is tlb flags
; destroy bc, destroy a, destroy de, destroy ix
	dec	c
	jr	z, .map_page
; map c page from b page
	ld	a, i
	push	af
	push	de
	ld	e, c
	ld	a, b
	add	a, c
	jp	c, .__segfault_permission
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
	cpl
	ld	b, 0
	ld	c, a
	inc.s	bc
	ld	a, KERNEL_MM_PAGE_FREE_MASK
	di
.__map_pages_parse:
; fast search for free page
	cpir
	jp	po, .__map_page_full
; else check we have at least c page free
	ld	d, e
.__map_pages_length:
	cpi
	jp	po, .__map_pages_except
	jr	nz, .__map_pages_parse
	dec	d
	jr	nz, .__map_pages_length
.__map_pages_write_tlb:
; e is lenght, hl is last adress + 1
	dec	hl
	ld	a, l
	sub	a, e
	ld	l, a
; hl = start of the map, for e+1
	inc	e
	ld	b, e
	ld	c, l	; save l for latter
	pop	de
.__map_pages_write_flags:
	ld	(hl), e
	inc	h
	ld	(hl), d
	dec	h
	inc	hl
	djnz	.__map_pages_write_flags
	pop	af
	jp	po, $+5
	ei
	ld	hl, KERNEL_MM_PHY_RAM shr 2
	ld	h, c
	add	hl, hl
	add	hl, hl
	ret
.__map_pages_except:
	jp	nz, .__map_page_full
	dec	d
	jr	z, .__map_pages_write_tlb
	jp	.__map_page_full

.map_user_page:
; map a single page to an user thread
; a = pid
	ld	d, a
	ld	e, 0

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

.drop_user_pages:
; unmap all the pages belonging to an thread
; a = pid
; sanity check guard, call by kernel
; of course, it is easy to bypass, but at least it is here
; mainly, what happen if you unmap yourself ? > CRASH
	pop	hl
	push	hl
	ld	bc, KERNEL_MM_PHY_RAM + KERNEL_MM_PROTECTED_SIZE
	or	a, a
	sbc	hl, bc
	jp	nc, .segfault
	ld	hl, kmm_ptlb_map + KERNEL_MM_GFP_KERNEL + KERNEL_MM_PAGE_MAX
	ld	bc, KERNEL_MM_PAGE_MAX - KERNEL_MM_GFP_KERNEL
	jr	.__drop_user_pages_parse
.__drop_user_pages_flush:
	dec	hl
	dec	h
	bit	KERNEL_MM_PAGE_CACHE, (hl)
	call	z, .flush_page
	inc	h
	inc	hl
.__drop_user_pages_parse:
	cpir
	jp	pe, .__drop_user_pages_flush
	ret

.unmap_user_pages:
; ; register b is page index wanted
; ; register c is page count wanted to clean
; ; destroy hl, bc, a
; a is pid
	ld	d, a
	ld	e, 0
.unmap_pages:
; de is full tlb flag
	dec	c
	jr	z, .unmap_page
	ld	a, b
; sanity check ;
; b > base kernel memory
	cp	a, KERNEL_MM_GFP_KERNEL
	jp	c, .segfault
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, b
	add	a, c
	jp	c, .segfault
; okay nice. Now, we will unmap page and check full tlb bytes
; hl = first page
; check permission first
	inc	c
	ld	b, c
.__unmap_pages_loop:
; page_perm_rwox
	ld	a, (hl)
	cp	a, e
	jp	nz, .segfault
	inc	h
	ld	a, (hl)
	cp	a, d
	jp	nz, .segfault
	dec	h
	call	.flush_page
	djnz	.__unmap_pages_loop
	ret

.unmap_user_page:
; register b is page index wanted
; destroy a, destroy hl, destroy bc, destroy de
; page_perm_rwox
; a = pid
	ld	d, a
	ld	e, 0

.unmap_page:
; de is full flags
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, (hl)
	cp	a, e
	jp	nz, .segfault
	ld	a, b
; sanity check ;
; b > base kernel memory
	cp	a, KERNEL_MM_GFP_KERNEL
	jp	c, .segfault
; are we the owner ?
	inc	h
	ld	a, (hl)
	cp	a, d
	dec	l
	jp	nz, .segfault
	
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
	inc	sp
	pop	hl
	dec	sp
	ld	a, l
	srl	h
	rra
	srl	h
	rra
	ld	hl, kmm_ptlb_map
	ld	l, a
	ret

.is_anonymous:
; a is page id
; z flag set if true / nz if not
	ld	hl, kmm_ptlb_map
	ld	l, a
	ld	a, (hl)
	or	a, a
	ret
