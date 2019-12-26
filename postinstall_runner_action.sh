#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# NOTE: TPM 1.2 fix is adapted from the Chromefy project and this copyright doesn't apply them.
# This file is converted from the original postinstall_runner_action.cc
# located at https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master/payload_consumer/postinstall_runner_action.cc
# fetched at 23 December 2019
# NOTE: The conversion is a gradual process, it may take some time

# Get script directory 
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "$SCRIPT_DIR/download_action.sh"
. "$SCRIPT_DIR/delta_performer.sh"

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
    # Sometimes, /boot and /boot/vmlinuz doesn't exist
    if [ ! -f "${root}/boot/vmlinuz" ]; then
      >&2 echo "Warning: ${root}/boot or ${root}/boot/vmlinuz not found."
    fi
    # Although documented, check if $efi_path is actually a mount point
    if ! mountpoint -q "$efi_path"; then
      >&2 echo "$efi_path is not a mountpoint."
      exit 1
    fi
    ### For EFI ###
    local grub_cfg_path="${root}/boot/efi/boot/grub.cfg"
    . "${root}/usr/sbin/write_gpt.sh"
    load_base_vars
    local root_dev=`rootdev -s -d 2>/dev/null`
    # Check if both kernels are exists
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
      sed -i "s|${old_prioA}|${new_prioA}|" "${grub_cfg_path}"
      sed -i "s|${old_prioB}|${new_prioB}|" "${grub_cfg_path}"
    fi
    # Get current (now old) values
    # NOTICE: The verified images are not supported when root is modified, therefore, they are ignored.
    local root_a_val=`grep -m 1 "root=" "${grub_cfg_path}" | sed -e 's/.*root=//'`
    local root_b_val=`grep -m 2 "root=" "${grub_cfg_path}" | sed -e 's/.*root=//' | tail -1`
    # Get root uuids
    local root_a_uuid="PARTUUID=$(/sbin/blkid -s PARTUUID -o value $root_a_part)"
    local root_b_uuid="PARTUUID=$(/sbin/blkid -s PARTUUID -o value $root_b_part)"
    # Replace with the current values
    sed -i "s|${root_a_val}|${root_a_uuid}|" "${grub_cfg_path}"
    sed -i "s|${root_b_val}|${root_b_uuid}|" "${grub_cfg_path}"
    ### For Syslinux ###
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
    rm -rf "${efi_path}"/{efi,syslinux}
    cp -a "${root}"/boot/{efi,syslinux} "${efi_path}"
    # Copy the vmlinuz's into place for syslinux
    cp -f "${root}"/boot/vmlinuz "${efi_path}"/syslinux/vmlinuz.A
    cp -f "${root}"/boot/vmlinuz "${efi_path}"/syslinux/vmlinuz.B
    # Install Syslinux loader
    umount "${efi_path}"
    syslinux -d /syslinux "${efi_part}"
    mount "${efi_part}" "${efi_path}"
}

#
# PostinstallRunnerAction::Cleanup
#
function PostinstallRunnerAction_Cleanup {
    umount "${install_plan['target_partition']}"
    rmdir "${install_plan['target_partition']}"
    umount "${install_plan['efi_partition']}"
    rmdir "${install_plan['efi_partition']}"
}

#
# ChangeBootOrder
#
function PostinstallRunnerAction_ChangeBootOrder {
      # Change boot order
      local old_default=`tac "${install_plan['grub_path']}" | grep -m 1 "set default" | awk '{print $2}' | cut -d'=' -f2`
      local new_default="\$default${install_plan['target_slot_alphabet']}"  # For grub ($defaultA|$defaultB)
      local sys_default="DEFAULT chromeos-hd.${install_plan['target_slot_alphabet']}"  # For syslinux
      sed -i "s|${old_default}|${new_default}|" "${install_plan['target_partition']}/boot/efi/boot/grub.cfg" \
      && sed -i "s|${old_default}|${new_default}|" "${install_plan['grub_path']}" \
      && echo "${sys_default}" > "${install_plan['efi_partition']}/syslinux/default.cfg"
      if [ $? -ne 0 ]; then
        echo_stderr "Failed to update GRUB. Without it new update will not boot."
        PostinstallRunnerAction_Cleanup
        exit 1
      fi
}

#
# PostinstallRunnerAction::CompletePostinstall
#
function PostinstallRunnerAction_CompletePostinstall {
    install_plan['target_slot_no']=`echo ${install_plan['target_slot']} | sed 's/^[^0-9]\+\([0-9]\+\)$/\1/'`
    install_plan['write_gpt_path']="${install_plan['target_partition']}/usr/sbin/write_gpt.sh"
    install_plan['grub_path']="${install_plan['efi_partition']}/efi/boot/grub.cfg"
    local root_dev=`rootdev -s -d 2>/dev/null`
    local root_a="${install_plan['source_slot']}"
    local root_b="${install_plan['target_slot']}"
    if [ "${install_plan['target_slot_alphabet']}" == "A" ]; then
      root_a="${install_plan['target_slot']}"
      root_b="${install_plan['source_slot']}"
    else
      root_a="${install_plan['source_slot']}"
      root_b="${install_plan['target_slot']}"
    fi
    # Reset bootloaders (efi, syslinux)
    UpdateBootloaders "${install_plan['target_partition']}" \
                      "${install_plan['efi_partition']}" \
                      "${root_a}" "${root_a}" \
                      "${install_plan['efi_slot']}"
    # Update partition data
    # Just copy the previous write_gpt.sh, should go in the delta_performer.sh but kept here
    # since related works are done here
    rm "${install_plan['write_gpt_path']}"
    cp /usr/sbin/write_gpt.sh "${install_plan['target_partition']}/usr/sbin/"
    # There are three situations to deal with:
    # 1. ROOT_B doesn't exist in write_gpt.sh (but physically exists, of course)
    #    This is true for multibooted devices in general and in some special installations.
    #    It needs partition number replacement for ROOT_A (part no. 3) and change of
    #    boot order.
    # 2. KERN_A and KERN_B don't exist (but ROOT_A and ROOT_B do exist) in write_gpt.sh
    #    This is a special case and should only occurs due to some mistakes. It doesn't need
    #    any partition number replacement, but need to change the boot order.
    # 3. Otherwise ROOT_A, ROOT_B, KERN_A, KERN_B and possibly all other partitions exist
    #    This is a typical case of a clean install. Some multibooted device may also have
    #    ROOT_B, KERN_A and KERN_B (others are not checked/needed) which are also supported
    # NOTE: Situation#1 is a spcial case of situation#2
    # FIXME: Simplify by including write_gpt.sh at the top
    if ! grep -qE "_(ROOT_B|5)" "${install_plan['write_gpt_path']}"; then  # Situation#1
      # Replace ROOT_A partition number with the target partition number
      # FIXME: Rebuild write_gpt.sh
      cat "${install_plan['write_gpt_path']}" | sed \
      -e "s|^\(\s*PARTITION_NUM_ROOT_A=\)\"[0-9]\+\"$|\1\"${install_plan['target_slot_no']}\"|g" \
      -e "s|^\(\s*PARTITION_NUM_3=\)\"[0-9]\+\"$|\1\"${install_plan['target_slot_no']}\"|g" \
      | tee "${install_plan['write_gpt_path']}" > /dev/null
      if [ $? -ne 0 ]; then
        echo_stderr "Failed to update partition data. Update aborted."
        PostinstallRunnerAction_Cleanup
        exit 1
      fi
    fi  
    if ! ( grep -qE "_(KERN_(A|B)|2|4)" /usr/sbin/write_gpt.sh || \
      ( FindPartitionByLabel "KERN-A" | grep -q $root_dev && \
      FindPartitionByLabel "KERN-B" | grep -q $root_dev ) ); then  # Situation#2
      PostinstallRunnerAction_ChangeBootOrder
    else  # Situation#3
      . "${install_plan['write_gpt_path']}"
      load_base_vars
      # PARTITION_NUM_KERN_A or PARTITION_NUM_KERN_B
      local part_num="PARTITION_NUM_KERN_${install_plan['target_slot_alphabet']}"
      if ! [ $part_num ]; then
        part_num=`FindPartitionByLabel "KERN-${install_plan['target_slot_alphabet']}"`
      fi
      # Change boot priority
      cgpt prioritize -P 4 $root_dev \
      && cgpt add -i ${!part_num} -P 5 -T 0 -S 1 $root_dev  # Boot as successful device for now
      if [ $? -ne 0 ]; then
        # Probably not EFI, try syslinux
        echo "DEFAULT chromeos-hd.${install_plan['target_slot_alphabet']}" > \
          "${install_plan['efi_partition']}/syslinux/default.cfg"
        if [ $? -ne 0 ]; then
          echo_stderr "Failed to prioritize new root. Without it new update will not boot."
          PostinstallRunnerAction_Cleanup
          exit 1
        fi
      fi
    fi
    PostinstallRunnerAction_Cleanup
}

#
# PostinstallRunnerAction::PerformPartitionPostinstall
#
function PostinstallRunnerAction_PerformPartitionPostinstall {
    install_plan['efi_partition']="${install_plan['download_root']}/efi_part"
    install_plan['swtpm_tar']="${install_plan['download_root']}/swtpm.tar"
    install_plan['swtpm_path']="${install_plan['download_root']}/swtpm"
    # swtpm
    if [ "${install_plan['tpm']}" == "true" ]; then
      # FIXME: Handle errors properly
      # Download swtpm
      curl -sL -o "${install_plan['swtpm_tar']}" "${install_plan['tpm_url']}" 2> /dev/null
      if [ $? -ne 0 ]; then
        echo_stderr "Failed to download swtpm.tar. Update aborted."
        rm "${install_plan['swtpm_tar']}" 2> /dev/null
        exit 1
      fi
      # Extract swtpm.tar
      tar -xf "${install_plan['swtpm_tar']}" -C "${install_plan['download_root']}"
      # Copy necessary files
      cp -a "${install_plan['swtpm_path']}"/usr/sbin/* "${install_plan['target_partition']}/usr/sbin"
      cp -a "${install_plan['swtpm_path']}"/usr/lib64/* "${install_plan['target_partition']}/usr/lib64"
      # Symlink libtpm files
      cd "${install_plan['target_partition']}/usr/lib64"
      ln -s libswtpm_libtpms.so.0.0.0 libswtpm_libtpms.so.0
      ln -s libswtpm_libtpms.so.0 libswtpm_libtpms.so
      ln -s libtpms.so.0.6.0 libtpms.so.0
      ln -s libtpms.so.0 libtpms.so
      ln -s libtpm_unseal.so.1.0.0 libtpm_unseal.so.1
      ln -s libtpm_unseal.so.1 libtpm_unseal.so
      # Restore download root
      cd "${install_plan['download_root']}"
      # Start at boot (does it necessary?)
      cat > "${install_plan['target_partition']}/etc/init/_vtpm.conf" <<EOL
    start on started boot-services

    script
        mkdir -p /var/lib/trunks
        modprobe tpm_vtpm_proxy
        swtpm chardev --vtpm-proxy --tpm2 --tpmstate dir=/var/lib/trunks --ctrl type=tcp,port=10001
        swtpm_ioctl --tcp :10001 -i
    end script
EOL
      # Cleanups
      rm "${install_plan['swtpm_tar']}" 2> /dev/null
      rm -rf "${install_plan['swtpm_path']}" 2> /dev/null
    fi
    # Mount efi partition
    mkdir "${install_plan['efi_partition']}"
    mount -o rw "${install_plan['efi_slot']}" "${install_plan['efi_partition']}"
    if [ $? -ne 0 ]; then
      echo_stderr "Failed to mount efi partition."
      rmdir "${install_plan['efi_partition']}"
      exit 1
    fi
    PostinstallRunnerAction_CompletePostinstall
}

#
# PostinstallRunnerAction::PerformAction
#
function PostinstallRunnerAction_PerformAction {
    # Download
    DownloadAction_PerformAction
    # Install update
    DeltaPerformer_Write
    # Run post install
    PostinstallRunnerAction_PerformPartitionPostinstall
    echo_stderr "Update is successfully installed. Please reboot to continue."
}


# Check environment variables
if [ "${0##*/}" == "postinstall_runner_action.sh" ]; then
    UpdateBootloaders "/" "/home/chronos/user/Downloads/anew" /dev/sdb12 /dev/sdb14 /dev/sdb11
    # PostinstallRunnerAction_PerformAction
    #( set -o posix ; set )
fi
