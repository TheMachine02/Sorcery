define	KERNEL_POWER_CHARGING		$000B
define	KERNEL_POWER_BATTERY		$0000
define	KERNEL_POWER_CPU_CLOCK		$0001
define	KERNEL_POWER_PWM		$F60024

define	kinterrupt_power_mask		$D00008
; we need to save the whales (and the palette)
define	kpower_lcd_save			$D00B00

macro	wait
	ld	b, $FF
	djnz	$
end	macro

power:

.init:
	di
	ld	a, $03
	out0	(KERNEL_POWER_CPU_CLOCK), a
	ld	a, $80
	
.backlight:
; set backlight level = a, max is $FF, min is $00
	ld	hl, KERNEL_POWER_PWM
	ld	(hl), a
	ret

; return : 0% error c, 20% a= 0, 40% a=1, 60% a=2, 80% a=3, 100% a=4
.battery_level=$0003B0

.battery_charging:
	in0	a, (KERNEL_POWER_CHARGING)
	bit	1, a
	ret

.cycle_off:
	di
	call	kwatchdog.disarm
; backlight / LCD / SPI disable from boot
	ld	hl, DRIVER_VIDEO_PALETTE
	ld	de, kpower_lcd_save
	ld	bc, 512
	ldir
	call	_boot_TurnOffHardware
; 6Mhz speed
	di
	xor	a, a
	out0	(KERNEL_POWER_CPU_CLOCK), a
	inc	a
	ld	($E00005), a
; usb stuff ?
; 	ld	bc,$003030
; 	xor	a, a
; 	out	(bc), a
; 	ld	bc, $003114
; 	inc	a
; 	out	(bc), a
; reset rtc : enable, but no interrupts
	ld	hl, DRIVER_RTC_CTRL
	ld	(hl), $01
	ld	l, DRIVER_RTC_ISCR and $FF
	ld	(hl), $FF
; set keyboard to idle
	ld	hl, DRIVER_KEYBOARD_CTRL
	xor	a, a
	ld	(hl), a
; let's do shady stuff
; various zeroing
	out0	($2C), a
; power to who ? DUNNO
	out0	($05), a
; disable display refresh
	out0	($06), a
; status ?
	in0	a, ($0F)
	bit	6, a
	jr	nz, .cycle_on_label_0
	bit	7, a
	jr	z, .cycle_on_label_0
	ld	b, $FD
	ld	a, $05
	jr	.cycle_on_label_1
.cycle_on_label_0:
	ld	b, $FC
	xor	a, a
.cycle_on_label_1:
	out0	($0C), a
	ld	a, b
	out0	($0A), a
; 0b1101
	ld	a, $0D
	out0	($0D), a
	wait
; let's got back to various power stuff
; disable screen ?
	in0	a, ($09)
	and	a, $01
	or	a, $E6
	out0	($09), a
; most likely do something
	ld	a, $FF
	out0	($07), a
; let's setup interrupt now
; disable all
	ld	de, $01
	ld	hl, KERNEL_INTERRUPT_IMSC
	ld	bc, (hl)
	ld	(kinterrupt_power_mask), bc
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
	in0	a, ($0D)
	inc	a
	jr	nz, .wait_for_port_0D
	ld	a, $76
	out0	($05), a
	ld	a, $03
	out0	($06), a
	wait
	ld	($E00005), a
	out0	(KERNEL_POWER_CPU_CLOCK), a
; usb ?
; 	ld.sis	bc,$3114
; 	inc	a
; 	out	(bc), a
; interrupts
	ld	hl, KERNEL_INTERRUPT_IMSC
	ld	bc, (kinterrupt_power_mask)
	ld	(hl), bc
	ld	bc, $FFFFFF
	ld	l, KERNEL_INTERRUPT_ICR and $FF
	ld	(hl), bc
; RTC init
	ld	hl, DRIVER_RTC_CTRL
	ld	(hl), 10011111b
	ld	l, DRIVER_RTC_ISCR and $FF
	ld	(hl), $FF
; before _boot_InitializeHardware, check battery level
	call	.battery_level
	jp	c, .cycle_off
; LCD, SPI, backlight
	call	_boot_InitializeHardware
; lot of things broken
	ld	a, KERNEL_CRYSTAL_DIVISOR
	out0	(KERNEL_CRYSTAL_CTLR), a
	ld	de, DRIVER_VIDEO_PALETTE
	ld	hl, kpower_lcd_save
	ld	bc, 512
	ldir
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
