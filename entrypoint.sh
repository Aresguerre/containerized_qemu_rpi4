#!/bin/bash

export START_SECTOR=$(fdisk -l ${IMAGE_FILE} | awk '/Linux/ {print $2; exit}')
export DEVICE=$(losetup -f --show -o $((START_SECTOR*512)) ${IMAGE_FILE})
mount ${DEVICE} /mnt
chmod 777 regenerate_ssh_host_keys
cp regenerate_ssh_host_keys /mnt/usr/lib/raspberrypi-sys-mods/
umount /mnt
losetup -d $DEVICE
qemu-system-aarch64 -machine raspi4b -cpu cortex-a72 -m 2G -smp 4 \
            -dtb custom.dtb \
            -kernel kernel8.img \
            -append "rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/mmcblk1p2 rootdelay=5 autologin=root" \
            -drive file=${IMAGE_FILE},format=raw \
            -device usb-net,netdev=net0 \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 \
            -monitor telnet:127.0.0.1:5555,server,nowait \
            -serial stdio && \
            -nographic