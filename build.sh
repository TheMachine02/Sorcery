#!/bin/bash
#generate config
str=$(git rev-parse --short HEAD)
echo "; auto generated file" > config
echo "define CONFIG_KERNEL_VERSION \"0.1.4-slp-"$str"\"" >> config
echo "define CONFIG_KERNEL_RELEASE \"slp-"$str"\"" >> config
cat build_config >> config
echo "Generating initramfs..."
fasmg kernel/bss.asm kernel/initramfs
lz4 -f -l --best kernel/initramfs initramfs
rm kernel/initramfs
# echo "Generating initial root..."
# genromfs -d root -V root -f rootfs
echo "Building kernel..."
# build kernel
fasmg sorcery.asm SORCERY.8xp
fasmg vm.asm VMLOADER.8xp
fasmg vmsorcerz.asm sorcery-0.1.4-slp
echo "include	'header/include/ez80.inc'" > image.asm
echo "include	'header/include/tiformat.inc'" >> image.asm
echo "format	ti executable 'VMSCZ'" >> image.asm
echo "file	'sorcery-0.1.4-slp'" >> image.asm
fasmg image.asm VMSCZ.8xp
rm image.asm

sha256sum -b sorcery-0.1.4-slp | sed 's/ \*.*//'> sha256
truncate sha256 -s -1
