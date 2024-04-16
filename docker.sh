#!/bin/bash

docker build -t qemu:rpi4 .

docker run --privileged -it --rm -p 2222:2222 -p 5555:5555 qemu:rpi4