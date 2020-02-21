#!/bin/bash
# 2020 (c) Muntashir Al-Islam. All rights reserved.
# Source: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/master/boot_control_chromeos.cc
# Fetched 2 Jan 2020

# NOTICE: These values are not the same as the original
kChromeOSPartitionNameKernel="KERN"
kChromeOSPartitionNameRoot="ROOT"
kChromeOSPartitionNameESP="EFI-SYSTEM"

# DLC not supported (deprecated in the original repo)
kPartitionNamePrefixDlc="dlc"
kPartitionNameDlcA="dlc_a"
kPartitionNameDlcB="dlc_b"
kPartitionNameDlcImage="dlc.img"

kInvalidSlot=-1

kCrosUpdateConf="/usr/local/cros_update.conf" # Our conf file

boot_disk_name_=
num_slots_=
current_slot_=

#
# GetBootDevice (eg. /dev/sda3)
#
function GetBootDevice {
  rootdev -s
  if [ $? -ne 0 ]; then
    >&2 echo "rootdev failed to find the root device."
  fi
}

#
# BootControlChromeOS_SlotToAlphabet
# Args: SLOT
# Return: A|B
function BootControlChromeOS_SlotToAlphabet {
  if [ "$1" == "0" ]; then echo "A"; else echo "B"; fi
}

# Args: PARTLABEL (eg. ROOT-A) DEVICE (eg. /dev/sd%D)
# Return: DEVICE_PATH (eg. /dev/sd%D%P)
function BootControlChromeOS_FindPartitionByLabel {
    local label=$1
    local root_dev=$2
    if ! [ $root_dev ]; then
      root_dev=`rootdev -s -d 2> /dev/null`
    fi
    /sbin/blkid -o device -t PARTLABEL="${label}" "$root_dev"*
}

# Get partition by UUID, if not found, try using label
# Args: UUID PARTLABEL
# Return: DEVICE_PATH (eg. /dev/sd%D%P)
function BootControlChromeOS_GetPartitionFromUUID {
    local uuid=$1  # Can be empty
    local label=$2  # Not empty
    local part=
    if [ "$uuid" == "" ]; then
      part=$(BootControlChromeOS_FindPartitionByLabel "${label}")
    else
      part=`/sbin/blkid --uuid "${uuid}"`
      if [ "${part}" == "" ]; then
        >&2 echo "Warning: Given UUID for ${label} not found, default will be used."
        part=$(BootControlChromeOS_FindPartitionByLabel "${label}")
      fi
    fi
    echo "${part}"
}

#
# BootControlChromeOS::GetPartitionNumber
# (This is different from the original implementation to support multiboot)
# Args: PARTITION_NAME SLOT
# Return: PARTITION_NUM
function BootControlChromeOS_GetPartitionNumber {
  local partition_name="$1"
  local slot_name="$(BootControlChromeOS_SlotToAlphabet $2)"
  local part_label="${partition_name}-${slot_name}"
  local root_uuid=
  local part=
  # Look for conf
  if [ -f "${kCrosUpdateConf}" ]; then
    . "${kCrosUpdateConf}"
    if [ "${slot_name}" == "A" ]; then
      root_uuid="${ROOTA}"
    else
      root_uuid="${ROOTB}"
    fi
  fi
  
  if [ "${partition_name}" == "${kChromeOSPartitionNameRoot}" ]; then
    part="$(BootControlChromeOS_GetPartitionFromUUID "${root_uuid}" "$part_label")"
  elif [ "${partition_name}" == "${kChromeOSPartitionNameKernel}" ]; then
    part="$(BootControlChromeOS_GetPartitionFromUUID "" "${part_label}")"
  elif [ "${partition_name}" == "${kChromeOSPartitionNameESP}" ]; then
    part="$(BootControlChromeOS_GetPartitionFromUUID "${EFI}" "$kChromeOSPartitionNameESP")"
  fi

  if [ -z "${part}" ]; then
    echo "-1"
  else
    # No support for MMC and NAND block devices
    echo "${part}" | sed -e 's|/dev/[A-Za-z]\+\([0-9]\+\)|\1|'
  fi
  return 0
}

#
# BootControlChromeOS::IsRemovableDevice
# Args: DEVICE_PATH (/dev/sda, /dev/sdb, etc.)
function BootControlChromeOS_IsRemovableDevice {
  local disk_name="$(echo $1 | sed -e 's|/dev/||')"
  if [ "$(cat /sys/block/$disk_name/removable)" == "1" ]; then
    echo "true"
  else
    echo "false"
  fi
}

#
# BootControlChromeOS::SetActiveBootSlot
# Args: SLOT
function BootControlChromeOS_SetActiveBootSlot {
  local partition_num=$(BootControlChromeOS_GetPartitionNumber $kChromeOSPartitionNameKernel $1)
  if [ $partition_num -lt 0 ]; then return 1; fi
  cgpt add "/dev/${boot_disk_name_}" -i ${partition_num} -S1 -T0
  # Mark the kernel as highest priority
  cgpt prioritize "/dev/${boot_disk_name_}" -i ${partition_num}
  if [ $? -ne 0 ]; then
    >&2 echo "Unable to set highest priority for slot."
    return 1
  fi
  return 0
}

#
# BootControlChromeOS::IsSlotBootable
# Args: SLOT
function BootControlChromeOS_IsSlotBootable {
  local partition_num="$(BootControlChromeOS_GetPartitionNumber $kChromeOSPartitionNameKernel $1)"
  if [ $partition_num -lt 0 ]; then echo "false"; else echo "true"; fi
}

#
# BootControlChromeOS::Init
#
function BootControlChromeOS_Init {
  local boot_device="$(GetBootDevice)"
  if [ -z "${boot_device}" ]; then
    return 1
  fi
  boot_disk_name_="$(rootdev -s -d)"
  local partition_num=$(echo $boot_device | sed -e "s|${boot_disk_name_}||")
  if [ "$(BootControlChromeOS_IsRemovableDevice $boot_disk_name_)" == "true" ]; then
    num_slots_=1
  else
    num_slots_=2
  fi
  current_slot_=0
  while [ $current_slot_ -lt $num_slots_ ] && ! [ "${partition_num}" == "$(BootControlChromeOS_GetPartitionNumber $kChromeOSPartitionNameRoot $current_slot_)" ]; do
    current_slot_=$(( current_slot_ + 1 ))
  done
  
  if [ $current_slot_ -ge $num_slots_ ]; then
    >&2 echo "Couldn't find the slot number."
    current_slot_=$kInvalidSlot
  fi
}
