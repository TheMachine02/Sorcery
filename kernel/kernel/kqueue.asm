
define	KERNEL_QUEUE_ID                        0x00
define	KERNEL_QUEUE_NEXT                      0x01
define	KERNEL_QUEUE_PREVIOUS                  0x04

kqueue:

; those routine destroy a
; all other register are preserved

.insert:
; iy is node to insert
; hl is queue pointer (count, queue_current)
; update queue_current to inserted node
; inplace insert of the node
; return 
	ld	a, (hl)
	inc	(hl)
	or	a, a
	jr	z, .create_queue
	push	ix
; prev_node.next = new_node
; next_node.prev = new_node
; new_node.prev = prev_node
; new_node.next = next_node
; queue_current = iy
	inc	hl
	ld	ix, (hl)
	ld	(hl), iy
	dec	hl
; ix = prev_node
	push	hl
	ld	hl, (ix+KERNEL_QUEUE_NEXT)
; de = next_node
	ld	(iy+KERNEL_QUEUE_PREVIOUS), ix
	ld	(iy+KERNEL_QUEUE_NEXT), hl
	ld	(ix+KERNEL_QUEUE_NEXT), iy
; (de+KERNEL_QUEUE_PREVIOUS)=iy
	ex	(sp), hl
	pop	ix
	ld	(ix+KERNEL_QUEUE_PREVIOUS), iy
	pop	ix
	ret
.create_queue:
	inc	hl
	ld	(hl), iy
	dec	hl
	ld	(iy+KERNEL_QUEUE_PREVIOUS), iy
	ld	(iy+KERNEL_QUEUE_NEXT), iy
	ret

.remove:
; iy is node to remove
; update queue_current to NULL if count=0 or previous node of the removed node
; hl is queue pointer (count, queue_current)
	ld	a, (hl)
	or	a, a
	jr	z, .null_queue
	dec	(hl)
	push	iy
	push	ix
	ld	ix, (iy+KERNEL_QUEUE_NEXT)
	ld	iy, (iy+KERNEL_QUEUE_PREVIOUS)
; next_node.prev=prev_node
; prev_node.next=next_node
	ld	(ix+KERNEL_QUEUE_PREVIOUS), iy
	ld	(iy+KERNEL_QUEUE_NEXT), ix
	inc	hl
	ld	(hl), iy
	dec	hl
	pop	ix
	pop	iy
	ret
.null_queue:
	push	de
	inc	hl
	ld	de, NULL
	ld	(hl), de
	dec	hl
	pop	de
	ret
 
