#!/bin/bash
# This script gets executed by a UDev rule whenever an external drive is unplugged.
# The following env variables are set by UDev, but can be obtained if the script is executed outside of UDev context:
# - DEVNAME: Device node name (i.e: /dev/sda1)
# - ID_BUS: Bus type (i.e: usb)
# - ID_FS_TYPE: Device filesystem (i.e: vfat)
# - ID_FS_UUID_ENC: Partition's UUID (i.e: 498E-12EF)
# - ID_FS_LABEL_ENC: Partition's label (i.e: YOURDEVICENAME)

. /usr/src/scripts/common.sh
. /usr/src/scripts/docker.sh

# Make sure we have a valid device name
DEVNAME=${DEVNAME:=$1}
if [[ -z $DEVNAME ]]; then
  info "Invalid device name: $DEVNAME"
  exit 1
fi

# Get required device information
ID_BUS=${ID_BUS:=$(udevadm info -n $DEVNAME | awk -F "=" '/ID_BUS/{ print $2 }')}
ID_FS_TYPE=${ID_FS_TYPE:=$(udevadm info -n $DEVNAME | awk -F "=" '/ID_FS_TYPE/{ print $2 }')}
ID_FS_UUID_ENC=${ID_FS_UUID_ENC:=$(udevadm info -n $DEVNAME | awk -F "=" '/ID_FS_UUID_ENC/{ print $2 }')}
# ID_PART_ENTRY_UUID=${ID_PART_ENTRY_UUID:=$(udevadm info -n $DEVNAME | awk -F "=" '/ID_PART_ENTRY_UUID/{ print $2 }')}
ID_FS_LABEL_ENC=${ID_FS_LABEL_ENC:=$(udevadm info -n $DEVNAME | awk -F "=" '/ID_FS_LABEL_ENC/{ print $2 }')}

if [[ -z $ID_BUS || -z $ID_FS_TYPE || -z $ID_FS_UUID_ENC || -z $ID_FS_LABEL_ENC ]]; then
  info "Could not get device information: $DEVNAME"
  exit 1
fi

# Construct the mount point path
MOUNT_POINT=/mnt/storage-$ID_BUS-$ID_FS_LABEL_ENC-$ID_FS_UUID_ENC

# Unmount device
if findmnt -rno SOURCE,TARGET $DEVNAME >/dev/null; then
  info "Unmounting device - Source: $DEVNAME - Destination: $MOUNT_POINT"
  umount -f $MOUNT_POINT
  rmdir $MOUNT_POINT
  action_containers $ID_FS_UUID_ENC >/proc/1/fd/1 2>/proc/1/fd/2
  action_services $ID_FS_UUID_ENC >/proc/1/fd/1 2>/proc/1/fd/2
else
  info "No mount point found for device $DEVNAME."
fi
