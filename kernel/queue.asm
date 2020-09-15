define	QUEUE_DATA		$00
define	QUEUE_NEXT		$01
define	QUEUE_PREVIOUS		$04
; queue data ;
define	QUEUE_SIZE		$04
define	QUEUE_COUNT		$00		; marked as $FF = 0, you need to +1 if you want *physical* count
define	QUEUE_CURRENT		$01		; pointer 24 bits

kqueue:

; all register are preserved

.insert_head:
; iy is node to insert
; hl is queue pointer (count, queue_current)
; insert after current pointer if queue is non null, update current to node else
; inplace insert of the node
	inc	(hl)
	inc	hl
	jr	z, .create
	push	ix
; prev_node.next = new_node
; next_node.prev = new_node
; new_node.prev = prev_node
; new_node.next = next_node
	ld	ix, (hl)
	ld	ix, (ix+QUEUE_NEXT)
	ld	(iy+QUEUE_NEXT), ix
	ld	(ix+QUEUE_PREVIOUS), iy
	ld	ix, (hl)
	ld	(iy+QUEUE_PREVIOUS), ix
	ld	(ix+QUEUE_NEXT), iy
	dec	hl
	pop	ix
	ret
	
.create:
	ld	(hl), iy
	dec	hl
	ld	(iy+QUEUE_PREVIOUS), iy
	ld	(iy+QUEUE_NEXT), iy
	ret

.insert_tail:
; iy is node to insert
; hl is queue pointer (count, queue_current)
; insert before current pointer if queue is non null, update current to node else
; inplace insert of the node
	inc	(hl)
	inc	hl
	jr	z, .create
	push	ix
; prev_node.next = new_node
; next_node.prev = new_node
; new_node.prev = prev_node
; new_node.next = next_node
	ld	ix, (hl)
	ld	ix, (ix+QUEUE_PREVIOUS)
	ld	(iy+QUEUE_PREVIOUS), ix
	ld	(ix+QUEUE_NEXT), iy
	ld	ix, (hl)
	ld	(iy+QUEUE_NEXT), ix
	ld	(ix+QUEUE_PREVIOUS), iy
	dec	hl
	pop	ix
	ret

.remove_head:
; iy assumed to be queue head
; remove iy as node, update queue head to the next node of iy
; can also use as a general 'fast' remove node with random head updating (if you don't need head to point to something particular)
	dec	(hl)
	ret	m
	push	ix
	push	hl
	inc	hl
	ld	ix, (iy+QUEUE_NEXT)
	ld	(hl), ix
	ld	hl, (iy+QUEUE_PREVIOUS)
	ld	(ix+QUEUE_PREVIOUS), hl
	inc	hl
	ld	(hl), ix
	pop	hl
	pop	ix
	ret

.remove:
; iy is node to remove
; safe general queue remove
; update queue_current to NULL if count=0 or if the node removed is current, to the next node
; hl is queue pointer (count, queue_current)
; node MUST belong to the queue
	dec	(hl)
	ret	m
	push	de
	push	bc
	push	ix
	inc	hl
	ld	ix, (iy+QUEUE_NEXT)
; if iy = (hl) : make (hl) be ix
	lea	bc, iy+0
	ld	de, (hl)
	ex	de, hl
	or	a, a		; silly carry
	sbc	hl, bc
	jr	nz, .remove_other_node
; we had the node set as current
	ex	de, hl
	ld	(hl), ix
	ex	de, hl
.remove_other_node:
	ld	hl, (iy+QUEUE_PREVIOUS)
; next_node.prev=prev_node
; prev_node.next=next_node
	ld	(ix+QUEUE_PREVIOUS), hl
	inc	hl
	ld	(hl), ix
	ex	de, hl
	dec	hl
	pop	ix
	pop	bc
	pop	de
	ret

.insert_priority:
; iy is node to insert, a is node priority
; hl is queue pointer (count, queue_current)
; insert before lower priority node, starting at head
	inc	(hl)
	inc	hl
	ld	(iy+QUEUE_DATA), a
	jr	z, .create
	dec	hl
	push	hl
	push	bc
	ld	b, (hl)
	inc	hl
	push	ix
	ld	ix, (hl)
; check against queue data
.insert_priority_cmp:
	cp	a, (ix+QUEUE_DATA)
	jr	c, .insert_priority_node
	ld	ix, (ix+QUEUE_NEXT)
	djnz	.insert_priority_cmp
.insert_priority_node:
; insert the node before node ix
	ld	hl, (ix+QUEUE_PREVIOUS)
	ld	(iy+QUEUE_PREVIOUS), hl
	inc	hl
; write to previous node the next node
	ld	(hl), iy
	ld	(iy+QUEUE_NEXT), ix
	ld	(ix+QUEUE_PREVIOUS), iy
	pop	ix
	pop	bc
	pop	hl
	ret
