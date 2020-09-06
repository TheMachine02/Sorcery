include	'include/ez80.inc'

define	BOOT_DIRTY_MEMORY0			$D0009B		; 1 byte ]
define	BOOT_DIRTY_MEMORY1			$D000AC		; 1 byte ] on interrupt
define	BOOT_DIRTY_MEMORY2			$D000FF		; 3 bytes
define	BOOT_DIRTY_MEMORY3			$D00108		; 9 bytes

define	KERNEL_HW_POISON			$C7
define	KERNEL_MM_RESERVED_MASK			00101000b
define	KERNEL_MM_PAGE_FREE_MASK		128

 org	$D00000
KERNEL_INTERRUPT_IPT:
; IRQ priority : keyboard > lcd > usb > rtc > hrtr1 > hrtr2 > hrtr3 > power
kinterrupt_irq_reschedule	= $
kthread_current			= $+1
 db	$00, $90	; 0000
 db	$00, $D0	; 0000
 db	$04, $50	; 0001
 db	$01, $40	; 0001
 db	$08, $54	; 0010
 db	$02, $44	; 0010
 db	$04, $50	; 0011
 db	$02, $44	; 0011
 db	$10, $58	; 0100
 db	$04, $48	; 0100
 db	$04, $50	; 0101
 db	$04, $48	; 0101
 db	$08, $54	; 0110
 db	$02, $44	; 0110
 db	$04, $50	; 0111
 db	$02, $44	; 0111
 db	$20, $5C	; 1000
 db	$08, $4C	; 1000
 db	$04, $50	; 1001
 db	$08, $4C	; 1001
 db	$08, $54	; 1010 
 db	$02, $44	; 1010
 db	$04, $50	; 1011
 db	$02, $44	; 1011
 db	$20, $5C	; 1100
 db	$04, $48	; 1100
 db	$04, $50	; 1101
 db	$04, $48	; 1101
 db	$08, $54	; 1110
 db	$02, $44	; 1110
 db	$04, $50	; 1111
 db	$02, $44	; 1111
KERNEL_INTERRUPT_IPT_JP:
 jp	$00
 jp	$00
 jp	$00
 jp	$00
 jp	$00
 jp	$00
 jp	$00
 jp	$00
KERNEL_INTERRUPT_ISR_DATA:
; 6 bytes * 8, place for mutex + isr save
KERNEL_INTERRUPT_ISR_DATA_VIDEO:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_USB:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_RTC:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_KEYBOARD:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_HRTIMER1:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_HRTIMER2:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_HRTIMER3:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_POWER:
 db	6	dup	KERNEL_HW_POISON
; we are at $90, 24 bytes up to 
kernel_idle:
 db	$00			; ID 0 reserved
 dl	kernel_idle		; No next
 dl	kernel_idle		; No prev
 db	$00			; No PPID
 db	$FF			; IRQ all
 db	$FF			; Status		; 9B is here, we DONT care
 db	12			; Special anyway
 db	$FF			; quantum
 dl	$D000A8			; Stack limit
kernel_stack_pointer:
 dl	$D000FF			; Stack will be writed at first unschedule
 dl	$D00100			; Boot/kernel  heap
 dl	$000000			; Time
; up to $A8, end of stack
 db	87	dup	KERNEL_HW_POISON
KERNEL_STACK:
; $FF, scrap
  db	1	dup	KERNEL_HW_POISON
; 512 bytes scrap, used for lot of things
KERNEL_HEAP:
nmi_context		= $+64
nmi_stack		= $+250
; this stack is supposed to be ~ 256 bytes
kinterrupt_irq_stack_isr	= $+506
kinterrupt_irq_ret_ctx		= $+506
kinterrupt_irq_stack_ctx	= $+509
 db	512	dup	KERNEL_HW_POISON
; we are at $D00300 
; 16 bytes (4x4)
kthread_mqueue_active:
 db	16	dup	$FF
; retire queue
kthread_queue_retire:
 db	4	dup	$FF
; timer queue
ktimer_queue:
 db	4	dup	$FF
kinterrupt_power_mask:
 db	3	dup	KERNEL_HW_POISON
unallocated_zero: 
 db	37	dup	KERNEL_HW_POISON
kmem_cache_buffctl:
; 16 slub buffers, 6 defined, 10 user defined
kmem_cache_s8:
 db	8	dup	$FF
kmem_cache_s16:
 db	8	dup	$FF
kmem_cache_s32:
 db	8	dup	$FF
kmem_cache_s64:
 db	8	dup	$FF
kmem_cache_s128:
 db	8	dup	$FF
kmem_cache_s256:
 db	8	dup	$FF
kmem_cache_user:
 db	80	dup	KERNEL_HW_POISON
kvfs_root:
; 64 bytes
 db	$04	; directory
 db	$01	; reference
 dl	$000000	; size, it is a directory, so count of data holded
 dl	$000000	; parent
; atomic lock
 db	$00, $FF
 db	$FF, $FF
 db	$FF, $FF
 db	$FF, $FF
; data, 15 * 3, there is nothing in this directory
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
 dl	$000000
; operation lookup table, null physical operation (ie device callback are here)
 dl	$000000
; $400
kthread_pid_map:
 db	$01
 dl	kernel_idle
 db	252	dup	$00
; $500
kmm_ptlb_map:
 db	4	dup	KERNEL_MM_RESERVED_MASK
 db	89	dup	KERNEL_MM_PAGE_FREE_MASK
 db	1	dup	KERNEL_MM_RESERVED_MASK
 db	162	dup	KERNEL_MM_PAGE_FREE_MASK
 db	256	dup	$00
; $700
 db	256	dup	$00
 db	2048	dup	KERNEL_HW_POISON

kpower_lcd_save:
