define	DRIVER_SPI_CR0		$F80000
define	DRIVER_SPI_CR1		$F80004
define	DRIVER_SPI_CR2		$F80008
define	DRIVER_SPI_STATUS	$F8000C
define	DRIVER_SPI_CTRL		$F80010
define	DRIVER_SPI_ISR		$F80014
define	DRIVER_SPI_FIFO		$F80018
define	DRIVER_SPI_REVISION	$F80060
define	DRIVER_SPI_FEATURE	$F80064


spi:

.init:
	di
	ret
	
.param:
	scf
	db $30

.cmd:
	or	a, a
	ld	hl, DRIVER_SPI_FIFO
	call	.write
	ld	l, h
	ld	(hl), $01
.wait:
	ld	l, (DRIVER_SPI_STATUS+1) and $FF
	ld	a, $F0
.wait_1:
	tst	a, (hl)
	jr	nz, .wait_1
	dec	l
.wait_2:
	bit	2, (hl)
	jr	nz, .wait_2
	ld	l, h
	ld	(hl), a
	ret
	
.write:
	rla
	rla
	rla
	ld	(hl), a
	rla
	rla
	rla
	ld	(hl), a
	rla
	rla
	rla
	ld	(hl), a
	ret
