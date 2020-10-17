

# Sorcery - a preemptive multitasking hybrid kernel

<p align="center">
<img src="https://i.imgur.com/i6wLFIz.png" />
</p>

## Features

Sorcery can execute up to 64 concurrent tasks sharing the same adress space (RAM space + flash space). Libraries are dynamically loaded in RAM and shared across threads. It implements POSIX-like (it won't be fully compatible) threading with signal, real-time scheduling, hardware and software interrupt, per thread timer. Each 'process' is a single thread and there is no difference between them. Context switchs are ~ 4000 cycle-long, more if a thread need to be waked (~ 5000 cycles), 105 times per second (configurable), using a simple round robin scheduling with 4 priority queues implementing feedback (io bound threads are promoted, compute heavy threads are lowered). Lower priority threads are always preempted by the higher ones, and that is mandatory across all the kernel.

## Memory gestion

All the memory is visible by all threads (except kernel memory, which is protected), but that doesn't mean threads can do what they want. They are mandated to call kernel function to fastly allocate memory page and malloc memory block within their heap. A killed thread will never leak memory, since all requested pages of RAM are deallocated within the kernel. Furthermore, each thread has its own protected stack. If a thread stack overflows, calculator *will* cleanly reboot to prevent other thread corruption and potentially file system corruption.

## Program execution

A program is executed as a thread, and fully relocatable within memory. The program isn't certain to be at a fixed adress, and this changes some programmation paradigms. It shall be mostly transparent to the user though.

## Shared library

Standard library is shared among threads and loaded in memory. When all threads are done using the library, it is unloaded.

## Minimal drivers

Also implemented are minimal drivers to get an input/output (RTC, keyboard, video, timer).

## Boot code and other

Aims to be compatible with Noti boot code (https://github.com/beckadamtheinventor/noti-ez80) and TI boot code.
Uses the Sulphur boot loader as the 'base' OS image for loading kernel as an executable leaf file (custom elf like format).
