FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y git libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev ninja-build libnfs-dev libiscsi-dev python3-pip flex bison libslirp-dev && \
    apt-get install -y fdisk wget mtools xz-utils qemu-utils

RUN git clone https://github.com/0xMirasio/qemu-patch-raspberry4.git

WORKDIR /qemu-patch-raspberry4

RUN mkdir build && \
    cd build && \
    ../configure --target-list=aarch64-softmmu --enable-user && \
    make -j$(nproc) && \
    make install

# Download the kernel image
RUN wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-03-15/2024-03-15-raspios-bookworm-arm64-lite.img.xz
ENV IMAGE_FILE=2024-03-15-raspios-bookworm-arm64-lite.img

# Uncompress the image
RUN xz -d ${IMAGE_FILE}.xz

# Resize the image to next power of two
RUN CURRENT_SIZE=$(stat -c%s "${IMAGE_FILE}") && \
    NEXT_POWER_OF_TWO=$(python3 -c "import math; \
                                    print(2**(math.ceil(math.log(${CURRENT_SIZE}, 2))))") && \
    qemu-img resize "${IMAGE_FILE}" "${NEXT_POWER_OF_TWO}"

RUN OFFSET=$(fdisk -lu ${IMAGE_FILE} | awk '/^Sector size/ {sector_size=$4} /FAT32 \(LBA\)/ {print $2 * sector_size}') && \
    # Check that the offset is not empty
    if [ -z "$OFFSET" ]; then \
        echo "Error: FAT32 not found in disk image" && \
        exit 1; \
    fi && \
    # Setup mtools config to extract files from the partition
    echo "drive x: file=\"${IMAGE_FILE}\" offset=${OFFSET}" > ~/.mtoolsrc

# Copy the kernel image from the disk image
RUN mcopy x:/bcm2711-rpi-4-b.dtb . && \
    mcopy x:/kernel8.img .

# Set up SSH
# RPI changed default password policy, there is no longer default password
RUN mkdir -p /tmp && \
    # First create ssh file to enable ssh
    touch /tmp/ssh && \
    # Then create userconf file to set default password (raspberry)
    echo 'pi:$6$rBoByrWRKMY1EHFy$ho.LISnfm83CLBWBE/yqJ6Lq1TinRlxw/ImMTPcvvMuUfhQYcMmFnpFXUPowjy2br1NA0IACwF9JKugSNuHoe0' | tee /tmp/userconf

# Copy the files onto the image
RUN mcopy /tmp/ssh x:/ && \
    mcopy /tmp/userconf x:/


EXPOSE 2222
EXPOSE 5555

ENTRYPOINT qemu-system-aarch64 -machine raspi4b1g -cpu cortex-a72 -m 1G -smp 4 \
            -dtb bcm2711-rpi-4-b.dtb \
            -kernel kernel8.img \
            -append "rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/mmcblk0p2 rootdelay=1" \
            -drive file=${IMAGE_FILE},format=raw \
            -device usb-net,netdev=net0 \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 \
            -monitor telnet:127.0.0.1:5555,server,nowait \
            -d guest_errors,unimp -D qemu.log \
            -nographic


