define	QUEUE_ID		$00
define	QUEUE_NEXT		$01
define	QUEUE_PREVIOUS		$04
; queue data ;
define	QUEUE_SIZE		$04
define	QUEUE_COUNT		$00
define	QUEUE_CURRENT		$01

kqueue:

; those routine destroy a
; all other register are preserved

.insert_head:
; iy is node to insert
; hl is queue pointer (count, queue_current)
; insert after current pointer if queue is non null, update current to node else
; inplace insert of the node
; return 
	ld	a, (hl)
	inc	(hl)
	inc	hl
	or	a, a
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
; return 
	ld	a, (hl)
	inc	(hl)
	inc	hl
	or	a, a
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
	ret	z
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
	ret	z
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

define	LIST_PRIORITY		$00
define	LIST_NEXT		$01
; queue data ;
define	LIST_SIZE		$04
define	LIST_COUNT		$00
define	LIST_HEAD		$01

klist:
; priority list

.append:
; hl is list, iy is node, c is node priority (0 is highest priority)
	ld	(iy+LIST_PRIORITY), c
	ld	a, (hl)
	inc	(hl)
	or	a, a
	jr	z, .create
	push	hl
; parse from LIST_START to find where to insert our node
	inc	hl
	ld	ix, (hl)
	ld	b, a
	ld	a, c
; compare ix priority to priority (register c)
	cp	a, (ix+LIST_PRIORITY)
	jr	c, .append_head
	djnz	.append_end
.append_parse:
	ld	hl, (ix+LIST_NEXT)
	cp	a, (hl)
	jr	c, .append_end
	ld	ix, (ix+LIST_NEXT)
	djnz	.append_parse
.append_end:
; node should be next of ix
	ld	hl, (ix+LIST_NEXT)
	ld	(ix+LIST_NEXT), iy
	ld	(iy+LIST_NEXT), hl
	pop	hl
	ret
.append_head:
; head = node, node next = previous_head
	ld	(hl), iy
	ld	(iy+LIST_NEXT), ix
	pop	hl
	ret

.create:
	inc	hl
	ld	(hl), iy
	dec	hl
	ret

.retire:
; retire the first node >> iy
; return z if none to retire, else, iy is the node retired
; hl is list
	ld	a, (hl)
	or	a, a
	ret	z
	dec	(hl)
	inc	hl
	ld	iy, (hl)
	ld	bc, (iy+LIST_NEXT)
	ld	(hl), bc
	dec	hl
	or	a, a
	ret
