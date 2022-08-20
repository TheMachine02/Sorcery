#!/bin/bash
rm -rf bin
mkdir bin
#generate config
version=${1:-0.3.3}
str=$(git rev-parse --short HEAD)
echo "; auto generated file" > config
echo "define CONFIG_KERNEL_VERSION \""$version"-slp-"$str"\"" >> config
echo "define CONFIG_KERNEL_RELEASE \"slp-"$str"\"" >> config
cat build_config >> config
echo "generating initramfs..."
fasmg kernel/bss.asm bin/initramfs
lz4 -f -l --best bin/initramfs initramfs
# echo "Generating initial root..."
# genromfs -d root -V root -f rootfs
echo "building multiboot loader..."
fasmg vm.asm bin/VMLOADER.8xp
echo "building kernel..."
# build kernel
# fasmg sorcery.asm bin/SORCERY.8xp
fasmg vmsorcerz.asm bin/sorcery-$version-slp
echo "include	'header/include/ez80.inc'" > image.asm
echo "include	'header/include/tiformat.inc'" >> image.asm
echo "format	ti executable archived 'VMSCZ'" >> image.asm
echo "file	'bin/sorcery-"$version"-slp'" >> image.asm
fasmg image.asm bin/VMSCZ.8xp
sha256sum -b bin/sorcery-$version-slp | sed 's/ \*.*//'> bin/sha256
truncate bin/sha256 -s -1
# cleanup
rm image.asm initramfs bin/initramfs

# build a small demo executable
fasmg executable.asm bin/crc
echo "include	'header/include/ez80.inc'" > crc.asm
echo "include	'header/include/tiformat.inc'" >> crc.asm
echo "format	ti executable archived 'CRC'" >> crc.asm
echo "file	'bin/crc'" >> crc.asm
fasmg crc.asm bin/CRC.8xp
# cleanup
rm crc.asm
