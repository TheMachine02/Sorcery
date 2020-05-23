define	KERNEL_POWER_CHARGING       0x000B
define	KERNEL_POWER_BATTERY        0x0000
define	KERNEL_POWER_CPU_CLOCK      0x0001

kpower:
.init:
	ld	a, 0x03
	out0	(KERNEL_POWER_CPU_CLOCK), a
	ret

.getBatteryLevel=0x0003B0

.getBatteryChargingStatus:
	in0	a, (KERNEL_POWER_CHARGING)
	or	a, a
	ret
    
kcstate:

; change clock every 100ms, based on the last 100ms load
define KERNEL_CSTATE_GRANULARITY 100

define	kcstate_timer		0xD00310

.get_clock:
	in0	a, (KERNEL_POWER_CPU_CLOCK)
	ret

.idle_inject:
; watchdog : 32768, 3277 MAX value for idle timing0
; cystal timer : 104Hz (tous les 20 sample)
	ld 	a, 0x03
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
