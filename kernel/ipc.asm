; 8 bytes structure describing the msg queue, msqid is address of the queue (in slab)
define	KERNEL_SYSV_QUEUE_MSG_COUNT		0	; 1 byte
define	KERNEL_SYSV_QUEUE_MSG_HEAD		1	; 3 bytes
define	KERNEL_SYSV_QUEUE_MSG_PERMISSION	4	; 1 byte
define	KERNEL_SYSV_QUEUE_MSG_SIZE		5	; 3 bytes, size of the queue in byte

; msg structure, 16 bytes
define	KERNEL_SYSV_MSG_SIZE			0	; 1 byte, message size in byte
define	KERNEL_SYSV_MSG_NEXT			1
define	KERNEL_SYSV_MSG_PREVIOUS		4
define	KERNEL_SYSV_MSG_TYPE			7
define	KERNEL_SYSV_MSG_POINTER			8	; 3 bytes pointer to allocated message
; up to 11, still 5 bytes

define	KERNEL_SYSV_MSG_MAX_ID			16
define	KERNEL_SYSV_MSG_MAX_SIZE		128	; in byte
define	KERNEL_SYSV_QUEUE_MAX_SIZE		4096	; in byte

msg:

.get:
	ret

.ctl:
	ret
	
.rcv:
	ret
	
.snd:
	ret
