define	KERNEL_POWER_CHARGING		$000B
define	KERNEL_POWER_BATTERY		$0000
define	KERNEL_POWER_CPU_CLOCK		$0001

define	KERNEL_POWER_PWM		$B024

kpower:
.init:
	ld	a, $00
	out0	(KERNEL_POWER_CPU_CLOCK), a
	ret

.get_battery_level=$0003B0

.get_battery_charging_status:
	in0	a, (KERNEL_POWER_CHARGING)
	or	a, a
	ret
    
define	KERNEL_CSTATE_GRANULARITY	100
; change clock every 100ms, based on the last 100ms load
define	KERNEL_CSTATE_SAMPLING		15

define	kcstate_timer		$D00310

kcstate:

.idle_adjust:
; watchdog : 32768, ~3250 MAX value for idle timing0
; cystal timer : 150 Hz (tous les 15 sample)
	ld 	a, $03
	ld	hl, (KERNEL_THREAD+KERNEL_THREAD_TIME)
	ld	de, 410
	or	a, a
	sbc	hl, de
	jr	c, .set_clock
	dec	a
	or	a, a
	sbc	hl, de
	jr	c, .set_clock
	dec	a
	or	a, a
	sbc	hl, de
	jr	c, .set_clock
	dec	a
	
.set_clock:
	out0	(KERNEL_POWER_CPU_CLOCK), a
	ret

.get_clock:
	in0	a, (KERNEL_POWER_CPU_CLOCK)
	ret
