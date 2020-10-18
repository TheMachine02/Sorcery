include	'header/include/ez80.inc'

define	BOOT_DIRTY_MEMORY0		$D0009B		; 1 byte
define	BOOT_DIRTY_MEMORY1		$D000AC		; 1 byte on interrupt
define	BOOT_DIRTY_MEMORY2		$D000FF		; 3 bytes
define	BOOT_DIRTY_MEMORY3		$D00108		; 9 bytes

define	KERNEL_HW_POISON		$C7
define	KERNEL_MM_RESERVED_MASK		00101000b
define	KERNEL_MM_PAGE_FREE_MASK	128

if $<> $D00000
 org	$D00000
 define sorcery_hypervisor	$D01004		;$D01004
end if

KERNEL_INTERRUPT_IPT:			; IRQ priority table : keyboard > lcd > usb > rtc > hrtr1 > hrtr2 > hrtr3 > power
kinterrupt_irq_reschedule:		; Does we need to reschedule after an IRQ (only have a meaning at the end of an IRQ)
kthread_current:= $+1			; Current executing thread
 db	$00, $90			; 0000
 db	$00, $D0			; 0000
 db	$04, $50			; 0001
 db	$01, $40			; 0001
 db	$08, $54			; 0010
 db	$02, $44			; 0010
 db	$04, $50			; 0011
 db	$02, $44			; 0011
 db	$10, $58			; 0100
 db	$04, $48			; 0100
 db	$04, $50			; 0101
 db	$04, $48			; 0101
 db	$08, $54			; 0110
 db	$02, $44			; 0110
 db	$04, $50			; 0111
 db	$02, $44			; 0111
 db	$20, $5C			; 1000
 db	$08, $4C			; 1000
 db	$04, $50			; 1001
 db	$08, $4C			; 1001
 db	$08, $54			; 1010 
 db	$02, $44			; 1010
 db	$04, $50			; 1011
 db	$02, $44			; 1011
 db	$20, $5C			; 1100
 db	$04, $48			; 1100
 db	$04, $50			; 1101
 db	$04, $48			; 1101
 db	$08, $54			; 1110
 db	$02, $44			; 1110
 db	$04, $50			; 1111
 db	$02, $44			; 1111
KERNEL_INTERRUPT_IPT_JP:		; jump table, defined by the IRQ number
 jp	$00
 jp	$00
 jp	$00
 jp	$00
 jp	$00
 jp	$00
 jp	$00
 jp	$00
KERNEL_INTERRUPT_IPT_SIZE:=$
KERNEL_INTERRUPT_ISR_DATA:		; 6 bytes * 8, place for mutex + isr save + hypervisor data
KERNEL_INTERRUPT_ISR_DATA_VIDEO:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_USB:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_RTC:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_KEYBOARD:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_HRTIMER1:
 db	4	dup	KERNEL_HW_POISON
KERNEL_HYPERVISOR_DATA:
 dl	sorcery_hypervisor
KERNEL_HYPERVISOR_SETTINGS:			; should be placed at offset $79
 db	$01
KERNEL_INTERRUPT_ISR_DATA_POWER:
 db	4	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_HRTIMER2:
 db	6	dup	KERNEL_HW_POISON
KERNEL_INTERRUPT_ISR_DATA_HRTIMER3:
 db	6	dup	KERNEL_HW_POISON
kernel_idle:				; we are at offset $90, 24 bytes
 db	$00				; ID 0 reserved, location of the idle thread image
 dl	kernel_idle			; No next
 dl	kernel_idle			; No prev
 db	$00				; No PPID
 db	$FF				; IRQ all
 db	$FF				; Status, NOTE : offset $9B is here, we DONT care
 db	12				; Special anyway
 db	$FF				; quantum
 dl	kernel_stack_limit		; Stack limit
kernel_stack_pointer:			; Stack pointer within idle thread
 dl	kernel_stack			; Stack will be writed at first unschedule
 dl	kernel_heap			; Boot/kernel  heap
 dl	$000000				; Time, NOTE : we finish at offset $A8, end of stack
kernel_stack_limit:
 db	87	dup	KERNEL_HW_POISON
kernel_stack:				; kernel stack head (HW stack)
  db	KERNEL_HW_POISON		; scrap
kernel_heap:				; kernel heap bottom (HW heap), also 512 bytes scrap, used for lot of things
 db	64	dup	KERNEL_HW_POISON
nmi_context:				; 64 bytes context, offset $40 within heap
 db	64	dup	KERNEL_HW_POISON
nmi_console:				; 64 bytes console save
 db	378	dup	KERNEL_HW_POISON
nmi_stack:				; interrupt stack. Anyway, if we were in a interrupt, we'll reboot
kinterrupt_irq_boot_ctx:=$D177BA	; 1 byte, if nz, execute boot isr handler
kinterrupt_irq_stack_isr: 		;  constant, head of stack
kinterrupt_irq_ret_ctx: 		;  written in the init (return pointer to clean up function)
 db	3	dup	KERNEL_HW_POISON 
kinterrupt_irq_stack_ctx:		; written in IRQ handler
 db	3	dup	KERNEL_HW_POISON
kthread_mqueue_active:			; offset $300, multilevel priority queue, 16 bytes (4x4)
 db	16	dup	$FF
kthread_queue_retire:			; retire queue
 db	4	dup	$FF
ktimer_queue:				; timer queue
 db	4	dup	$FF
kpower_interrupt_mask:			; temporary interrupt save register
 db	3	dup	KERNEL_HW_POISON
kpower_lcd_mask:			; we need to save the lcd data (and the whales)
 db	3	dup	KERNEL_HW_POISON
unallocated_zero:
 db	34	dup	KERNEL_HW_POISON
kmem_cache_buffctl:			; 16 slub buffers, 7 defined, 9 user defined
kmem_cache_s8:
 db	4	dup	$FF
 dw	8
 db	128
 db	0
kmem_cache_s16:
 db	4	dup	$FF
 dw	16
 db	64
 db	0
kmem_cache_s32:
 db	4	dup	$FF
 dw	32
 db	32
 db	0
kmem_cache_s64:
 db	4	dup	$FF
 dw	64
 db	16
 db	0
kmem_cache_s128:
 db	4	dup	$FF
 dw	128
 db	8
 db	0
kmem_cache_s256:
 db	4	dup	$FF
 dw	256
 db	4
 db	0
kmem_cache_s512:
 db	4	dup	$FF
 dw	512
 db	2
 db	0
kmem_cache_user:
 db	72	dup	$00		; null is reference to not allocated
kvfs_root:				; 64 bytes inode, the root of all root
 db	15				; directory (8), RWX permission
 db	$00,$FF				; atomic lock
 dl	$000000				; atomic lock
 db	$00				; reference
 dl	$000000				; size, it is a directory, so count of data holded
 dl	$000000				; parent
 dl	$000000				; operation lookup table, null physical operation (ie device callback are here)
 dl	$000000				; data, 16 * 3, there is nothing in this directory 
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
kthread_pid_map:			; we are at offset $400
 db	$01
 dl	kernel_idle
 db	252	dup	$00
kmm_ptlb_map:				; the kernel page alloctor process tlb at offset $500
 db	24	dup	KERNEL_MM_RESERVED_MASK
 db	69	dup	KERNEL_MM_PAGE_FREE_MASK
 db	1	dup	KERNEL_MM_RESERVED_MASK
 db	162	dup	KERNEL_MM_PAGE_FREE_MASK
 db	256	dup	$00
; $700
 db	256	dup	$00
 db	2048	dup	KERNEL_HW_POISON
