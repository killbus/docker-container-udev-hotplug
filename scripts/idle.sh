#!/bin/bash

# dump system environment
env >/tmp/environmentfile

# initlal mounts
declare -a storage_devices
if [ $ONLY_USB -eq 1 ]; then
  storage_devices=($(lsblk -do name,tran |grep usb | awk '{print $1}'))
else
  storage_devices=($(lsblk -do name,tran | awk '{print $1}'))
fi
for device in ${storage_devices[@]}; do
  usb_storage_partitions=$(lsblk "/dev/${device}" | grep -oP "sd[a-z][0-9]" | awk '{print "/dev/"$1}')
  for partition in ${usb_storage_partitions[@]}; do
    /usr/src/scripts/mount.sh "$partition"
  done
done

# Just an infinite loop to prevent container from exiting
balena-idle