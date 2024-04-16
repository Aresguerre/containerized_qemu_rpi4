FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    # Install QEMU dependencies
    apt-get install -y git libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev ninja-build meson libslirp-dev python3-pip && \
    # Install dtmerge dependencies
    apt-get install -y cmake libfdt-dev && \
    # Install mtools to extract files from the disk image
    apt-get install -y fdisk wget mtools xz-utils qemu-utils

# Build QEMU
RUN git clone https://gitlab.freedesktop.org/slirp/libslirp.git && \
    cd libslirp && \
    meson build && \
    ninja -C build install

RUN git clone https://github.com/qemu/qemu.git && \
    cd qemu && mkdir build && cd build && \
    ../configure --target-list=aarch64-softmmu && \
    make -j$(nproc) && \
    make install

# Build dtmerge
RUN git clone https://github.com/raspberrypi/utils.git && \
    cd utils && \
    cmake . && \
    make && \
    make install

# Download the kernel image
ENV IMAGE_FILE=2024-03-12-raspios-bullseye-arm64-lite.img

RUN wget https://downloads.raspberrypi.com/raspios_oldstable_lite_arm64/images/raspios_oldstable_lite_arm64-2024-03-12/${IMAGE_FILE}.xz && \
    xz -d ${IMAGE_FILE}.xz

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

ENV DTB=bcm2711-rpi-4-b.dtb

# Copy the kernel image and the device tree from the disk
RUN mcopy x:/${DTB} . && \
    mcopy x:/overlays/disable-bt.dtbo . && \
    mcopy x:/kernel8.img .

# Merge the device tree with the overlay
RUN cp ${DTB} custom.dtb && \
    dtmerge custom.dtb merged.dtb - uart0=on && \
    mv merged.dtb custom.dtb && \
    dtmerge custom.dtb merged.dtb disable-bt.dtbo && \
    mv merged.dtb custom.dtb

COPY . .

RUN chmod +x entrypoint.sh

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

ENTRYPOINT [ "./entrypoint.sh" ]
