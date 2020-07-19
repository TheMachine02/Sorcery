#!/bin/bash
str=$(git rev-parse --short HEAD)
echo "; auto generated file" > config
echo "define CONFIG_KERNEL_NAME \"Sorcery.0.0.1-slp-"$str"\"" >> config
cat config_build >> config
./fasmg sorcery.asm SORCERY.8xp
