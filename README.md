# Sorcery

## A libre preemptive multitasking kernel for the ez80

What does than mean ? Sorcery can execute up to 64 concurrent tasks sharing the same adress space (RAM space + flash space). Library a dynamically loaded in RAM and shared across thread. It implements POSIX-like (it won't be fully compatible) threading with signal, real-time scheduling, hardware and software interrupt, per thread timer. There is no difference between a thread and a process, a process is simply a thread whose code as been reallocated at startup.
Context switchs is around 4000 cycles, 150 times per second, using a simple round robin scheduling without (yet?) priority.

## Memory gestion

All the memory is visible by all thread (except kernel memory, which is protected), but that doesn't mean thread can do what they want. They are mandated to call kernel function to fastly allocate memory page and malloc memory block within their heap. A killed thread never will leak memory, since all requested page of RAM are deallocated within the kernel. Further more, each thread have their own stack with their own stack protection. If a thread stack overflow, calculator *will* reboot.

## Minimum drivers

Also implemented is minimal drivers to get a input / output (RTC, keyboard, video, timer)
