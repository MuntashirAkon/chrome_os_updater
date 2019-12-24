#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# This file is converted from the original delta_performer.cc
# located at https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master/payload_consumer/delta_performer.cc
# fetched at 23 December 2019
# NOTE: The conversion is a gradual process, it may take some time

# Get script directory 
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

#
# DeltaPerformer::Close
#
function DeltaPerformer_Close {
    umount "${install_plan['root_mountpoint']}"
    # umount "${install_plan['target_partition']}"
    rm "${install_plan['update_file_path']}"
    rm "${install_plan['kernel_path']}" 2> /dev/null
    rm "${install_plan['root_path']}" 2> /dev/null
    rmdir "${install_plan['root_mountpoint']}"
    # rmdir "${install_plan['target_partition']}"
}

#
# DeltaPerformer::PreparePartitionsForUpdate
#
function DeltaPerformer_PreparePartitionsForUpdate {
    # Convert to root.img using paycheck.py
    install_plan['kernel_path']="${install_plan['download_root']}/kernel"
    install_plan['root_path']="${install_plan['download_root']}/root.img"
    install_plan['root_mountpoint']="${install_plan['download_root']}/root"
    install_plan['target_partition']="${install_plan['download_root']}/target_root"
    python "$SCRIPT_DIR/scripts/paycheck.py" "${install_plan['update_file_path']}" --out_dst_part_paths  "${install_plan['kernel_path']}" "${install_plan['root_path']}"
    if [ $? -ne 0 ]; then
      echo_stderr "Failed to extract root image from update."
      rm "${install_plan['update_file_path']}"
      rm "${install_plan['kernel_path']}" 2> /dev/null
      rm "${install_plan['root_path']}" 2> /dev/null
      exit 1
    fi
    # mount root.img
    mkdir "${install_plan['root_mountpoint']}"
    mount -t ext4 -o ro "${install_plan['root_path']}" "${install_plan['root_mountpoint']}"
    if [ $? -ne 0 ]; then
      echo_stderr "Failed to mount root image."
      rm "${install_plan['update_file_path']}"
      rm "${install_plan['kernel_path']}" 2> /dev/null
      rm "${install_plan['root_path']}" 2> /dev/null
      rmdir "${install_plan['root_mountpoint']}"
      exit 1
    fi
    # mount target partition
    mkdir "${install_plan['target_partition']}"
    mount -t ext4 -o rw,exec "${install_plan['target_slot']}" "${install_plan['target_partition']}"
    if [ $? -ne 0 ] || [ "${install_plan['target_slot']}" == "" ]; then
      echo_stderr "Failed to mount root image."
      umount "${install_plan['root_mountpoint']}"
      rm "${install_plan['update_file_path']}"
      rm "${install_plan['kernel_path']}" 2> /dev/null
      rm "${install_plan['root_path']}" 2> /dev/null
      rmdir "${install_plan['root_mountpoint']}"
      rmdir "${install_plan['target_partition']}"
      exit 1
    fi
}

#
# DeltaPerformer::Write
#
function DeltaPerformer_Write {
    echo_stderr "Updating Chrome OS..."
    DeltaPerformer_PreparePartitionsForUpdate
    # Copy update files
    # Copy contents of root.img to the target partition
    rm -rf "${install_plan['target_partition']}"/*
    cp -a "${install_plan['root_mountpoint']}"/* "${install_plan['target_partition']}" 2> /dev/null
    # Copy required files from current to target partition
    rm -rf "${install_plan['target_partition']}/lib/firmware" "${install_plan['target_partition']}/lib/modules"
    rm -rf "${install_plan['target_partition']}/etc/modprobe.d"/alsa*.conf
    cp -a /{lib,boot} "${install_plan['target_partition']}/"
    cp -na /usr/lib64/{dri,va} "${install_plan['target_partition']}/usr/lib64/"
    cp -a "/usr/sbin/write_gpt.sh" "${install_plan['target_partition']}/usr/sbin"
    cp -a "/etc/gesture/40-touchpad-cmt.conf" "${install_plan['target_partition']}/etc/gesture"
    cp -a "/etc/chrome_dev.conf" "${install_plan['target_partition']}/etc"
    cp -a "/etc/init/mount-internals.conf" "${install_plan['target_partition']}/etc/init" 2> /dev/null
    sed '0,/enforcing/s/enforcing/permissive/' -i "${install_plan['target_partition']}/etc/selinux/config"
    # FIXME: Check for errors, use && for related commands to check at last and exit
    DeltaPerformer_Close
}

# Check environment variables
if [ "${0##*/}" == "delta_performer.sh" ]; then
    ( set -o posix ; set )
fi
