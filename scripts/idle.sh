#!/bin/bash

# dump system environment
env >/tmp/environmentfile

# initlal mounts
usb_storage_devices=$(lsblk | grep -oP "sd[a-z][0-9]" | awk '{print "/dev/"$1}')
for device in ${usb_storage_devices[@]}; do
  /usr/src/scripts/mount.sh "$device"
done

# Just an infinite loop to prevent container from exiting
balena-idle