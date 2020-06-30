define	KERNEL_POWER_CHARGING		$000B
define	KERNEL_POWER_BATTERY		$0000
define	KERNEL_POWER_CPU_CLOCK		$0001
define	KERNEL_POWER_PWM		$B024

kpower:

.init:
	ld	a, $03
	out0	(KERNEL_POWER_CPU_CLOCK), a
	ret

.battery_level=$0003B0

.battery_charging:
	in0	a, (KERNEL_POWER_CHARGING)
	or	a, a
	ret

.cycle_off:
	di
	call	kwatchdog.disarm
; backlight / LCD / SPI disable from boot
	call	_boot_TurnOffHardware
; 6Mhz speed
	di
	xor	a,a
	out0	($01),a
; 	ld.sis	bc,$1005
; 	ld	a, $02
; 	out	(bc),a
; usb stuff ?
; 	ld	bc,$003030
; 	xor	a, a
; 	out	(bc), a
; 	ld	bc, $003114
; 	inc	a
; 	out	(bc), a
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
	ld	a, $0D	; 0b1101
	out0	($0D), a
	ld	b, $FF
.cycle_wait_busy:
	djnz	.cycle_wait_busy
; reset rtc : enable, but no interrupts
	ld	hl, DRIVER_RTC_CTRL
	ld	(hl), $01
	ld	l, DRIVER_RTC_ISCR and $FF
	ld	(hl), $FF
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
; enable mask
	ld	de, 0
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	ld	(hl), $01
	inc	l
	ld	(hl), $00
	ld	l, KERNEL_INTERRUPT_ACKNOWLEDGE and $FF
; acknowledge
	ld	(hl), $FF
	inc	l
	ld	(hl), $FF
; annnnnnd shutdown
	ld	a, $C0
	out0	($00), a
	nop
	ei
	slp
	rst	$00
	
.cycle_on:
	ret

