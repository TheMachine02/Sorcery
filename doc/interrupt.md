# General documentation
 
## Kernel jumper
 
 Interrupts are triggered by extern source and halt the processor to execute the special interrupt service handler (or ISR). This action is called an IRQ or Interrupt ReQuest.
 
 Sorcery framework for handling IRQ is based on mode im 1 of the ez80 and the i register. In im 1 mode, the processor execute the rst 38h instruction (it is just a call to adress 38, which reside in the boot code). Boot code will then handle the interrupt and give back control at .irq_handler in interrupt.asm with an extra push on the stack.
 
 The handler routine will then :
 - Find the source which triggered the interrupt by reading the interrupt controller register
 - If multiple source triggered in same time, choice the one with the highest priority
For indication : IRQ priority : crystal > keyboard > lcd > usb > rtc > hrtr1 > hrtr2 > hrtr3 > power
To very fastly priorize, it read the special crafted table pointed by register i (usually adress $D00000) and retrieve both the value needed to acknowledge the interrupt and the pointer to the jump table to the correct handler. It then simply change the stack pointer to point to the interrupt stack and jump to the handler.

A driver can install a handler with .irq_request function, suppress an handler with .irq_free. You can also disable a particular interrupt with .irq_enable and .irq_disable

Once the handler finished to process the interrupt, the kernel take back the hand and goes back to .irq_context_restore. This function cleanup changes made by the interrupts, restore registers, and if needed, trigger the kernel scheduler.

## Interrupts handler

In order, these handler need to :
- Acknowledge the interrupt at the driver side, ie, in the peripheral register. If it fail to do so, it may cause an interrupt storm and a deadlock.
- Wake / do anything they want.

Some thing to note : interrupts MUST be disabled in this handler and they need to be as small and fast as possible. If more processing power is needed, they can wake/suspend/wait thread using the .irq_resume / .irq_suspend / .irq_wait function. Normal threading function can't be used in such context. You also need to note that you have a limited stack space (about 256 bytes) and that some kernel function may not be usable due to hard iff1/iff2 status.

They also have dedicated space in the kernel memory (6 bytes per IRQ). Will most likely change in the futur to 16 bytes
