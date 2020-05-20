# Zephyr

## A preempted multitasked libre kernel for the ez80

What does than mean ? Zephyr can execute up to 64 concurrent tasks. It implements POSIX-like thread with signal, real-time scheduling, hardware and software interrupt. It aims to do fast context switches transparent to the end user

## Advanced memory gestion

All the memory is visible by all thread (except kernel memory, which is protected), but that doesn't mean thread can do what they want. They can fastly allocate memory page and malloc memory block within this space. A killed thread never will leak memory. Further more, each thread have their own stack with their own stack protection. If a thread stack overflow, calculator *will* reboot.

## Minimum drivers

Also implemented is minimal drivers to get a input / output (RTC, keyboard, video, timer)
