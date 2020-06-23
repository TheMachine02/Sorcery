

# Sorcery - a preemptive multitasking kernel

<p align="center">
<img src="https://i.imgur.com/i6wLFIz.png" />
</p>

## Features

Sorcery can execute up to 64 concurrent tasks sharing the same adress space (RAM space + flash space). Library are dynamically loaded in RAM and shared across thread. It implements POSIX-like (it won't be fully compatible) threading with signal, real-time scheduling, hardware and software interrupt, per thread timer. There is no difference between a thread and a process, a process is simply a thread whose code as been reallocated at startup.
Context switchs is ~ 4000 cycles, more if a thread need to be waked (~ 6000 cycles), 150 times per second (configurable), using a simple round robin scheduling with 4 priority queue implementing feedback (io bound thread are promoted, compute heavy thread are lowered). Lower priority thread are always preempted by the higher priority one.

## Memory gestion

All the memory is visible by all thread (except kernel memory, which is protected), but that doesn't mean thread can do what they want. They are mandated to call kernel function to fastly allocate memory page and malloc memory block within their heap. A killed thread never will leak memory, since all requested page of RAM are deallocated within the kernel. Further more, each thread have their own stack with their own stack protection. If a thread stack overflow, calculator *will* cleanly reboot to prevent other thread corruption and potentially file system corruption

## Program execution

Program are executed as thread, and are fully relocatable within memory. The program isn't certain to be at a fixed adress, and this change some programmation paradigms. It should be mostly transparent to the user though.

## Shared library

Standard library are shared among thread and loaded in memory. When all thread are done using the library, it is unloaded.

## Minimum drivers

Also implemented is minimal drivers to get a input / output (RTC, keyboard, video, timer)

## Boot code and other

Aims to be compatible with Noti boot code (https://github.com/beckadamtheinventor/noti-ez80) and TI boot code
Use the Sulphur boot loader as the 'base' OS image for loading kernel as an executable leaf file (custom elf like format)
