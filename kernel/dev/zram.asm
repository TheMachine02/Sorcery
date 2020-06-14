define	KERNEL_ZRAM_SIZE		65536
define	KERNEL_ZRAM_HUGEPAGE		768

; virtual page index, with link from page index (0-255) <> dev_adress
; try to fit two compressed page in within one real page

; ENOMEM
; huge page

zram:

.init:
; init from kernel
; map one page please
	ld	bc, 1
	call	kmm.page_map
; this is our index map

	ret

.phy_write_page:
; find a page to write to ?
; parse list and find a size were we can write it, or else allocate it

	ret
	
.phy_read_page:
; extract compressed page and write it to a RAM page

	ret
