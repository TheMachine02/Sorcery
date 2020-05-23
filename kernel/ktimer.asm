
; ; bucket 256 bytes = 64 entries
; ; 16 precision exact 
; ; 16 precision 16 jiffies
; ; 16 precision 256 jiffies
; ; 16 precision 4096 jiffies
; ; more than uint16 worth of jiffies
; 
; ; (point to thread, thread point to next timer, thread hold timeout)
; ; for cascade
; ; retire current slot and inc slot
; ; if > 16 cascade next one, cascade timer found at current slot and inc slot
; ; if > 16 cascade next one, cascade timer found at current slot and inc slot
; ; if > 16 cascade next one, cascade timer found at current slot and inc slot
;	


 
