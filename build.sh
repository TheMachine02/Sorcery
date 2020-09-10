#!/bin/bash
str=$(git rev-parse --short HEAD)
echo "; auto generated file" > config
echo "define CONFIG_KERNEL_NAME \"Sorcery.0.0.1-slp-"$str"\"" >> config
cat config_build >> config
./fasmg kernel/bss.asm kernel/initramfs
lz4 -f -l --best kernel/initramfs initramfs
rm kernel/initramfs
./fasmg sorcery.asm SORCERY.8xp
