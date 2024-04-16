#!/bin/bash

DEVICE=/dev/loop0

if [ -e ${DEVICE} ]; then
    if losetup -a | grep -q ${DEVICE}; then
        losetup -d ${DEVICE}
    fi
    rm -f ${DEVICE}
fi

mknod -m660 ${DEVICE} b 7 0

START_SECTOR=$(fdisk -l ${IMAGE_FILE} | awk '/Linux/ {print $2; exit}')

losetup ${DEVICE} ${IMAGE_FILE} -o $((START_SECTOR*512))

mount ${DEVICE} /mnt

chmod 777 regenerate_ssh_host_keys

cp regenerate_ssh_host_keys /mnt/usr/lib/raspberrypi-sys-mods/

umount /mnt

losetup -d ${DEVICE}

rm -f ${DEVICE}

qemu-system-aarch64 -machine raspi3b -cpu cortex-a72 -m 2G -smp 4 \
            -dtb custom.dtb \
            -kernel kernel8.img \
            -append "rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/mmcblk1p2 rootdelay=5 autologin=pi" \
            -drive file=${IMAGE_FILE},format=raw \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 \
            -device usb-net,netdev=net0 \
            -monitor telnet:127.0.0.1:5555,server,nowait \
            -serial stdio \
            -nographic