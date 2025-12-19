#!/bin/bash

export HOME=/home/root/
export LANG="en_US.UTF-8"

# Download and install image
scp -o StrictHostKeyChecking=no -i ttusb_key tt@192.168.0.100:/home/tt/yocto-build/storage/build/deploy/image-tt-swu.swu /home/root/
swupdate -H imx7-var-som:1.0 -i /home/root/image-tt-swu.swu

# Get port
PORT=$(ssh -o StrictHostKeyChecking=no -i ttusb_key tt@192.168.0.100 cat ttusb_port)
ssh -o StrictHostKeyChecking=no -i ttusb_key tt@192.168.0.100 "echo $((PORT + 1)) > ttusb_port"
echo "SSH port: $PORT"

# Remove home
rm -rf /home/root/* /home/root/.*

# Setup device
ttsetup.sh --tunnel ${PORT} 

# Clean & reboot
reboot
