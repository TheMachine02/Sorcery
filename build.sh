#!/bin/bash
#generate config
str=$(git rev-parse --short HEAD)
echo "; auto generated file" > config
echo "define CONFIG_KERNEL_NAME \"Sorcery.0.0.1-slp-"$str"\"" >> config
cat config_build >> config
echo "Generating initramfs..."
./fasmg kernel/bss.asm kernel/initramfs
lz4 -f -l --best kernel/initramfs initramfs
rm kernel/initramfs
echo "Generating initial root..."
genromfs -d root -V root -f rootfs
echo "Building kernel..."
# build kernel
./fasmg sorcery.asm SORCERY.8xp
sha256sum -b SORCERY.8xp | sed 's/ \*.*//'> sha256
truncate sha256 -s -1
