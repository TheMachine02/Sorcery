#!/bin/bash
#generate config
version=${1:-1.5.0}
str=$(git rev-parse --short HEAD)
echo "; auto generated file" > config
echo "define CONFIG_KERNEL_VERSION \""$version"-slp-"$str"\"" >> config
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
fasmg sorcery.asm bin/SORCERY.8xp
fasmg vm.asm bin/VMLOADER.8xp
fasmg vmsorcerz.asm bin/sorcery-$version-slp
echo "include	'header/include/ez80.inc'" > image.asm
echo "include	'header/include/tiformat.inc'" >> image.asm
echo "format	ti executable 'VMSCZ'" >> image.asm
echo "file	'bin/sorcery-"$version"-slp'" >> image.asm
fasmg image.asm bin/VMSCZ.8xp
rm image.asm
rm initramfs

sha256sum -b bin/sorcery-$version-slp | sed 's/ \*.*//'> bin/sha256
truncate sha256 -s -1
