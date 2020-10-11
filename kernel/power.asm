define	KERNEL_POWER_CHARGING		$000B
; define	KERNEL_POWER_BATTERY		$0000
define	KERNEL_POWER_CPU_CLOCK		$0001
define	KERNEL_POWER_PWM		$F60024

macro	wait
	ld	b, $FF
	djnz	$
end	macro

kpower:

.init:
	di
	ld	a, $03
	ld	(KERNEL_FLASH_CTRL), a
	out0	(KERNEL_POWER_CPU_CLOCK), a
; default power up IRQ
	ld	hl, .irq_handler
	ld	a, KERNEL_IRQ_POWER
	call	kinterrupt.irq_request
	ld	a, $80
	
.backlight:
; set backlight level = a, max is $FF, min is $00
	ld	(KERNEL_POWER_PWM), a

.irq_handler:
	ret

; return : 0% error c, 20% a= 0, 40% a=1, 60% a=2, 80% a=3, 100% a=4
.battery_level=$0003B0

.battery_charging:
	in0	a, (KERNEL_POWER_CHARGING)
	bit	1, a
	ret

sysdef _shutdown
.cycle_off:
; TODO save and restore LCD parameters
	di
	call	kwatchdog.disarm
; backlight / LCD / SPI disable from boot
	ld	hl, kmem_cache_s512
	call	kmem.cache_alloc
; TODO use emergency memory if this carry
	ret	c
	ld	(kpower_lcd_mask), hl
	ex	de, hl
	ld	hl, DRIVER_VIDEO_PALETTE
	ld	bc, 512
	ldir
	call	_boot_TurnOffHardware
; 6Mhz speed
	di
	xor	a, a
	out0	(KERNEL_POWER_CPU_CLOCK), a
	inc	a
	ld	(KERNEL_FLASH_CTRL), a
; usb stuff ?
; 	ld	bc,$003030
; 	xor	a, a
; 	out	(bc), a
; 	ld	bc, $003114
; 	inc	a
; 	out	(bc), a
; reset rtc : enable, but no interrupts
	ld	hl, DRIVER_RTC_CTRL
	ld	(hl), a
	ld	l, DRIVER_RTC_ISCR and $FF
	ld	(hl), $FF
; set keyboard to idle
	ld	hl, DRIVER_KEYBOARD_CTRL
	ld	(hl), l
; let's do shady stuff
; various zeroing
	out0	($2C), l
; power to who ? DUNNO
	out0	($05), l
; disable display refresh
	out0	($06), l
; status ?
	in0	a, ($0F)
	add	a, a
	ld	b, $FC
	jp	m, .cycle_on_label_0
	jr	nc, .cycle_on_label_0
	inc	b
	ld	l, $05
.cycle_on_label_0:
	out0	($0C), l
	out0	($0A), b
; 0b1101
	ld	a, $0D
	out0	($0D), a
	wait
	ld	de, $000001
	ld	hl, KERNEL_INTERRUPT_IMSC
	dec	b
; let's got back to various power stuff
; disable screen ?
	in0	a, ($09)
	and	a, e
	or	a, $E6
	out0	($09), a
; most likely do something
	out0	($07), b
; let's setup interrupt now
; disable all
	ld	bc, (hl)
	ld	(kpower_interrupt_mask), bc
	ld	(hl), de
	ld	l, KERNEL_INTERRUPT_ICR and $FF
; acknowledge
	dec	de
	dec	de
	ld	(hl), de
; annnnnnd shutdown
	ld	a, $C0
	out0	($00), a
	nop
	ei
	slp

; will fall back on cycle ON when ON will be pressed, after trigger ON interrupt within kernel

.cycle_on:
	di
	ld	a, $0F
	out0	($0D), a
.wait_for_port_0D:
	in0	b, ($0D)
	inc	b
	jr	nz, .wait_for_port_0D
	ld	a, $76
	out0	($05), a
	ld	a, $03
	out0	($06), a
	wait
	ld	(KERNEL_FLASH_CTRL), a
	out0	(KERNEL_POWER_CPU_CLOCK), a
; usb ?
; 	ld.sis	bc,$3114
; 	inc	a
; 	out	(bc), a
; interrupts please
	ld	hl, KERNEL_INTERRUPT_IMSC
	ld	bc, (kpower_interrupt_mask)
	ld	(hl), bc
	ld	bc, $FFFFFF
	ld	l, KERNEL_INTERRUPT_ICR and $FF
	ld	(hl), bc
; RTC init
	ld	hl, DRIVER_RTC_CTRL
	ld	(hl), 10011111b
	ld	l, DRIVER_RTC_ISCR and $FF
	ld	(hl), c
; before _boot_InitializeHardware, check battery level
	call	.battery_level
	jp	c, .cycle_off
; LCD, SPI, backlight
; we'll do our own _boot_InitializeHardware to avoid white screen flashing. Thanks
	call	_boot_InitializeHardware
; lot of things broken
; restore crystal to correct kernel wide defined value
	ld	a, KERNEL_CRYSTAL_DIVISOR
	out0	(KERNEL_CRYSTAL_CTLR), a
	ld	hl, (kpower_lcd_mask)
	ld	de, DRIVER_VIDEO_PALETTE
	ld	bc, 512
	ldir
	ld	hl, (kpower_lcd_mask)
	call	kmem.cache_free
; get back our 8 bits LCD + interrupts
	ld	hl, DRIVER_VIDEO_IMSC
	ld	(hl), DRIVER_VIDEO_IMSC_DEFAULT
	ld	hl, DRIVER_VIDEO_CTRL_DEFAULT
	ld	(DRIVER_VIDEO_CTRL), hl
; setup timings
	ld	hl, video.LCD_TIMINGS
	ld	de, DRIVER_VIDEO_TIMING0 + 1
	ld	c, 8
	ldir
; not sure what this is for
; 	call	$000080
; 	ld	a, b
; 	or	a, a
; 	ret	z
; 	ld	a, $DC
; 	call	$000640
; 	cp	a, $35
	ei
	jp	kwatchdog.arm
