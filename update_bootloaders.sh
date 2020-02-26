#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

[ command -v debug >/dev/null 2>&1 ] || source "${SCRIPT_DIR}/debug_utils.sh"

#
# UpdateBootloaders, similar to update_x86_bootloaders.sh
# located at https://chromium.googlesource.com/chromiumos/platform/crosutils/+/refs/heads/master/update_bootloaders.sh
# The content of grub.cfg should have the format as given in
# https://chromium.googlesource.com/chromiumos/platform/crosutils/+/refs/heads/master/build_library/create_legacy_bootloader_templates.sh
# If this format is not respected, this process will not work.
# Arguments:
# $1: Writable root path (to modify /boot)
# $2: EFI (mounted) path
# $3: ROOT-A partition (e.g. /dev/sd%D%P)
# $4: ROOT-B partition (e.g. /dev/sd%D%P)
# $5: EFI-SYSTEM partition (e.g. /dev/sd%D%P)
function UpdateBootloaders {
    local root="$1"
    local efi_path="$2"
    local root_a_part="$3"
    local root_b_part="$4"
    local efi_part="$5"
    # Check if root is really mountable
    if ! [ -w "${root}" ]; then
      echo_stderr "${root} is a read only path."
    fi
    # Sometimes, /boot and /boot/vmlinuz doesn't exist
    if [ ! -f "${root}/boot/vmlinuz" ]; then
      echo_stderr "${root}/boot or ${root}/boot/vmlinuz not found."
      return 1
    fi
    # Although documented, check if $efi_path is actually a mount point
    if ! mountpoint -q "$efi_path"; then
      echo_stderr "$efi_path is not a mountpoint."
      return 1
    fi
    debug "UpdateBootloaders: $@"
    ### For EFI ###
    local grub_cfg_path="${root}/boot/efi/boot/grub.cfg"
    . "${root}/usr/sbin/write_gpt.sh"
    load_base_vars
    local root_dev=`rootdev -s -d 2>/dev/null`
    # Check if both kernels exist
    local kern_a_part=$PARTITION_NUM_KERN_A
    local kern_b_part=$PARTITION_NUM_KERN_B
    if ! ( [ $kern_a_part ] && [ $kern_b_part ] ); then
      kern_a_part=`FindPartitionByLabel "KERN-A" $root_dev | sed "s|$root_dev\(.*\)|\1|"`
      kern_b_part=`FindPartitionByLabel "KERN-B" $root_dev | sed "s|$root_dev\(.*\)|\1|"`
    fi
    if [ $kern_a_part ] && [ $kern_b_part ]; then
      # Set gpt priority: works only if the EFI-SYSTEM is in the same drive as the ROOT
      local old_prioA=`grep -m 1 "gptpriority" "${grub_cfg_path}"`
      local old_prioB=`grep -m 2 "gptpriority" "${grub_cfg_path}" | tail -1`
      local new_prioA="gptpriority \$grubdisk ${kern_a_part} prioA"
      local new_prioB="gptpriority \$grubdisk ${kern_b_part} prioB"
      # Replace all with new PrioB
      sed -i "s|${old_prioA}|${new_prioB}|" "${grub_cfg_path}"
      sed -i "s|${old_prioB}|${new_prioB}|" "${grub_cfg_path}"
      # Replace first one with prioA
      sed -i "0,/${new_prioB}/s|${new_prioB}|${new_prioA}|" "${grub_cfg_path}"
    fi
    # Get current (now old) values
    # NOTICE: The verified images are not supported when root is modified, therefore, they are ignored.
    local root_a_val=`grep -m 1 "root=" "${grub_cfg_path}" | sed -e 's/.*root=//'`
    local root_b_val=`grep -m 2 "root=" "${grub_cfg_path}" | sed -e 's/.*root=//' | tail -1`
    # Get root uuids
    local root_a_uuid="PARTUUID=$(/sbin/blkid -s PARTUUID -o value $root_a_part)"
    local root_b_uuid="PARTUUID=$(/sbin/blkid -s PARTUUID -o value $root_b_part)"
    # Replace all old values with new values of ROOT-B
    sed -i "s|${root_a_val}|${root_b_uuid}|" "${grub_cfg_path}"
    sed -i "s|${root_b_val}|${root_b_uuid}|" "${grub_cfg_path}"
    # Replace first one with new value of ROOT-A
    sed -i "0,/${root_b_uuid}/s|${root_b_uuid}|${root_a_uuid}|" "${grub_cfg_path}"
    ### For Syslinux (Legacy) ###
    # Get current (now old) values
    local syslinux_path="${root}/boot/syslinux"
    local root_a_path="${syslinux_path}/root.A.cfg"
    local root_b_path="${syslinux_path}/root.B.cfg"
    root_a_val=`grep -m 1 "root=" "${root_a_path}" | sed -e 's/.*root=\(.*\)/\1/' | awk '{print $1}'`
    root_b_val=`grep -m 1 "root=" "${root_b_path}" | sed -e 's/.*root=\(.*\)/\1/' | awk '{print $1}'`
    # Replace with the current values
    sed -i "s|${root_a_val}|${root_a_uuid}|" "${root_a_path}"
    sed -i "s|${root_b_val}|${root_b_uuid}|" "${root_b_path}"
    # Copy files into place
    rm -rf "${efi_path}"/efi
    cp -a "${root}"/boot/{efi,syslinux} "${efi_path}"
    # Copy the vmlinuz's into place for syslinux
    cp -f "${root}"/boot/vmlinuz "${efi_path}"/syslinux/vmlinuz.A
    cp -f "${root}"/boot/vmlinuz "${efi_path}"/syslinux/vmlinuz.B
    # Install Syslinux loader: skip as syslinux doesn't always work
    #umount "${efi_path}"
    #syslinux -d /syslinux "${efi_part}"
    #mount "${efi_part}" "${efi_path}"
    debug "grub.cfg: $(cat "${efi_path}"/efi/boot/grub.cfg)"
    return 0
}


# Run the script independently if called that way
if [ "${0##*/}" == "update_bootloaders.sh" ]; then
  UpdateBootloaders "$@" || echo_stderr "Updating bootloaders failed." && exit 1
  exit 0
fi
