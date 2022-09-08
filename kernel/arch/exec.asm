define	EXEC_MICROCODE_SIZE	192


sysdef _execve
execve:
; .BINARY_PATH:	hl
; .BIN_ENVP:	de
; .BIN_ARGV:	bc
; TODO : correct error path
	call	kvfs.inode_get_lock
	ret	c
; check if the inode is executable
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	l, a
	and	a, KERNEL_VFS_TYPE_MASK
	ld	a, ENOEXEC
	jp	nz, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_PERMISSION_X_BIT, l
	jp	z, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_CAPABILITY_DMA_BIT, l
	jp	z, kvfs.inode_atomic_write_error
	inc	(iy+KERNEL_VFS_INODE_REFERENCE)
; we have an DMA inode
; save the vmmu context of the current thread
	ld	hl, kmem_cache_s32
	call	kmem.cache_alloc
	jp	c, kvfs.inode_atomic_write_error
	push	hl
	ld	ix, (kthread_current)
	lea	de, ix+KERNEL_THREAD_VMMU_CONTEXT
	ex	de, hl
	ld	bc, 28
	ldir
; nullify the context
	lea	de, ix+KERNEL_THREAD_VMMU_CONTEXT
	ld	hl, KERNEL_MM_NULL
	ld	c, 28
	ldir
; allocate a new stack
	ld	bc, (KERNEL_THREAD_STACK_SIZE/KERNEL_MM_PAGE_SIZE) or (KERNEL_MM_GFP_USER shl 8)
	call	vmmu.map_pages
	push	hl
	ld	iy, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	iy, (iy+KERNEL_VFS_INODE_DMA_POINTER)
	call	leaf.exec_dma
; hl is the adress we need to jump to
; * cleanup *
	ex	(sp), hl
	di
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_STACK_LIMIT), hl
	ld	(iy+KERNEL_THREAD_HEAP), hl
	ld	de, KERNEL_THREAD_STACK_SIZE - 3
	add	hl, de
	ld	de, kthread.exit
	ld	(hl), de
	ld	(iy+KERNEL_THREAD_STACK), hl
	lea	hl, iy+KERNEL_THREAD_STACK_LIMIT
	ld	bc, $00033A
	otimr
; check if the parent thread have vforked, is so, resume it
	ld	a, (iy+KERNEL_THREAD_PPID)
	add	a, a
	add	a, a
	jr	z, .__execve_invalid_ppid
	ld	hl, kthread_pid_map
	ld	l, a
	inc	hl
	ld	ix, (hl)
; check if parent thread have forked
; if so, we are within a valid kernel frame, and we can switch off the child thread without issue
; scheduler will get us to the correct location in the parent
	push	iy
	lea	iy, ix+0
	bit	THREAD_VFORK_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	call	nz, task_switch_running
	res	THREAD_VFORK_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	pop	iy
.__execve_invalid_ppid:
; various close on exec etc
; TODO
; directly return to new program
	pop	hl
	ex	(sp), hl
; hl = context to drop
	ex	de, hl
	pop	bc
; bc = return adress
	ld	hl, (iy+KERNEL_THREAD_STACK)
	ld	sp, hl
	push	bc
	ei
	push	de
	call	vmmu.drop_context_de
	pop	hl
	jp	kmem.cache_free
	
; execute kernel in place, provide hl = file path
; as reboot, we expect filesystem to be sync and ready to reboot
sysdef	_kexec
kexec:
	call	kvfs.inode_get_lock
	ret	c
 ; check if the inode is executable
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	l, a
	and	a, KERNEL_VFS_TYPE_MASK
	ld	a, ENOEXEC
	jp	nz, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_PERMISSION_X_BIT, l
	jp	z, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_CAPABILITY_DMA_BIT, l
	jp	z, kvfs.inode_atomic_write_error
; we have an DMA inode, so we may check both compat and XIP
	ld	ix, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	ix, (ix+KERNEL_VFS_INODE_DMA_POINTER)
; ix is the file
	call	leaf_k.check_file
	ld	a, ENOEXEC
	jp	nz, kvfs.inode_atomic_write_error
	bit	LF_STATIC_BIT, (ix+LEAF_HEADER_FLAGS)
	jp	z, kvfs.inode_atomic_write_error
	lea	iy, ix+0
; do we truly have a kernel ? ENTRY POINT must be equal to $D01000
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	ld	de, $D01000
	or	a, a
	sbc	hl, de
	jp	nz, kvfs.inode_atomic_write_error
; then trigger exec
	ld	hl, leaf_k.microcode
	ld	de, exec_microcode
	ld	bc, EXEC_MICROCODE_SIZE
	ldir	
	jp	leaf_k.exec_static

leaf_k:
 
.check_file:
; iy = file adress
	ld	a, (ix+LEAF_IDENT_MAG0)
	cp	a, $7F
	ret	nz
	ld	hl, (ix+LEAF_IDENT_MAG1)
	ld	de, ('A'*65536)+('E'*256)+'L'
	sbc	hl, de
	ret	nz
	ld	a, (ix+LEAF_IDENT_MAG4)
	cp	a, 'F'
.check_supported:
	ld	a, (ix+LEAF_HEADER_MACHINE)
	or	a, a
	ret	nz
	ld	a, (ix+LEAF_HEADER_TYPE)
	cp	a, LT_EXEC
	ret

.microcode:
 org	exec_microcode
; for boundary
 rb	6 
 
.exec_static:
; only for static program (kernel)
; read section table and copy at correct location (for those needed)
; NOTE : this is for kernel execution
; TODO : also support non kernel program (we must allocate when copying at exact location)
	lea	bc, iy+0
	ld	ix, (iy+LEAF_HEADER_SHOFF)
	add	ix, bc
; read section now
	ld	b, (iy+LEAF_HEADER_SHNUM)
.alloc_prog_section:
	bit	1, (ix+LEAF_SECTION_FLAGS)
	jr	z, .alloc_next_section
	push	bc
	ld	hl, $E40000+SHT_NOBITS
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, l
	jr	z, .alloc_nobits
	ld	hl, (ix+LEAF_SECTION_OFFSET)
	lea	bc, iy+0
	add	hl, bc
.alloc_nobits:
	ld	bc, (ix+LEAF_SECTION_SIZE)
; we are a static file, the addr is RAM adress
	ld	de, (ix+LEAF_SECTION_ADDR)
	ldir
	pop	bc
.alloc_next_section:
	lea	ix, ix+16
	djnz    .alloc_prog_section
	bit	LF_PROTECTED_BIT, (iy+LEAF_HEADER_FLAGS)
	call	nz, .protected_static
; load up entry
; and jump !
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	jp	(hl)

.protected_static:
; find execution bound for a static program
	ld	hl, $D00000
	ld	(leaf_boundary_lower), hl
	ld	(leaf_boundary_upper), hl
	lea	bc, iy+0
	ld	ix, (iy+LEAF_HEADER_SHOFF)
	add	ix, bc
; read section now
	ld	b, (iy+LEAF_HEADER_SHNUM)
.protected_boundary:
	bit	1, (ix+LEAF_SECTION_FLAGS)
	jr	z, .protected_next_section
	ld	de, (ix+LEAF_SECTION_ADDR)
	ld	hl, (leaf_boundary_lower)
	or	a, a
	sbc	hl, de
	jr	c, .protected_bound_upper
	ld	(leaf_boundary_lower), de
.protected_bound_upper:
	ld	hl, (ix+LEAF_SECTION_SIZE)
	add	hl, de
	ex	de, hl
	ld	hl, (leaf_boundary_upper)
	or	a, a
	sbc	hl, de
	jr	nc, .protected_bound_lower
	ld	(leaf_boundary_upper), de
.protected_bound_lower:
.protected_next_section:
	lea	ix, ix+16
	djnz	.protected_boundary
	ld	hl, leaf_boundary_lower
	ld	bc, $620
	otimr
	ret

 align	256
 org	.microcode + EXEC_MICROCODE_SIZE
