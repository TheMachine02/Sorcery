
define	KERNEL_QUEUE_ID                        $00
define	KERNEL_QUEUE_NEXT                      $01
define	KERNEL_QUEUE_PREVIOUS                  $04

kqueue:

; those routine destroy a
; all other register are preserved

.insert_current:
; iy is node to insert
; hl is queue pointer (count, queue_current)
; insert after current pointer is queue is non null, update current to node else
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
	push	hl
	inc	hl
	ld	ix, (hl)
; ix = prev_node
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

.insert_end:
; iy is node to insert
; hl is queue pointer (count, queue_current)
; insert after current pointer is queue is non null, update current to node else
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
	push	hl
	inc	hl
	ld	ix, (hl)
	ld	ix, (ix+KERNEL_QUEUE_PREVIOUS)
	ld	hl, (hl)
	ld	(iy+KERNEL_QUEUE_PREVIOUS), ix
	ld	(iy+KERNEL_QUEUE_NEXT), hl
	ld	(ix+KERNEL_QUEUE_NEXT), iy
; (de+KERNEL_QUEUE_PREVIOUS)=iy
	ex	(sp), hl
	pop	ix
	ld	(ix+KERNEL_QUEUE_PREVIOUS), iy
	pop	ix
	ret
	
.remove:
; iy is node to remove
; update queue_current to NULL if count=0 or if the node removed is current, to the next node
; hl is queue pointer (count, queue_current)
	ld	a, (hl)
	or	a, a
	jr	z, .null_queue
	dec	(hl)
	push	iy
	push	ix
	push	de
	inc	hl
	push	hl
	ld	ix, (iy+KERNEL_QUEUE_NEXT)
; if iy = (hl) : make (hl) be ix
	lea	de, iy+0
	ld	hl, (hl)
	sbc	hl, de
	pop	hl
	jr	nz, .remove_other_node
; we had the node set as current
	ld	(hl), ix
.remove_other_node:
	dec	hl
	ld	iy, (iy+KERNEL_QUEUE_PREVIOUS)
; next_node.prev=prev_node
; prev_node.next=next_node
	ld	(ix+KERNEL_QUEUE_PREVIOUS), iy
	ld	(iy+KERNEL_QUEUE_NEXT), ix
	pop	de
	pop	ix
	pop	iy
	or	a, a
	ret
.null_queue:
	push	de
	inc	hl
	ld	de, NULL
	ld	(hl), de
	dec	hl
	pop	de
	ret
 
