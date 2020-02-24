#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# NOTE: TPM 1.2 fix is adapted from the Chromefy project and this copyright doesn't apply them.
# This file is converted from the original postinstall_runner_action.cc
# located at https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master/payload_consumer/postinstall_runner_action.cc
# fetched at 23 December 2019

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "$SCRIPT_DIR/download_action.sh"
. "$SCRIPT_DIR/delta_performer.sh"
. "$SCRIPT_DIR/update_bootloaders.sh"
[ command -v debug >/dev/null 2>&1 ] || source "${SCRIPT_DIR}/debug_utils.sh"

PostinstallRunnerAction_update_complete=false

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
        return 1
      fi
      debug "Syslinux: $sys_default, original $(cat "${install_plan['efi_partition']}/syslinux/default.cfg")"
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
                      "${root_a}" "${root_b}" \
                      "${install_plan['efi_slot']}" || return 1
    # Update partition data
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
      debug "No ROOT-B found in write_gpt"
      # FIXME: Rebuild write_gpt.sh
      cat "${install_plan['write_gpt_path']}" | sed \
      -e "s|^\(\s*PARTITION_NUM_ROOT_A=\)\"[0-9]\+\"$|\1\"${install_plan['target_slot_no']}\"|g" \
      -e "s|^\(\s*PARTITION_NUM_3=\)\"[0-9]\+\"$|\1\"${install_plan['target_slot_no']}\"|g" \
      | tee "${install_plan['write_gpt_path']}" > /dev/null
      if [ $? -ne 0 ]; then
        echo_stderr "Failed to update partition data. Update aborted."
        PostinstallRunnerAction_Cleanup
        return 1
      fi
    fi
    if ! ( grep -qE "_(KERN_(A|B)|2|4)" /usr/sbin/write_gpt.sh || \
      ( FindPartitionByLabel "KERN-A" | grep -q $root_dev && \
      FindPartitionByLabel "KERN-B" | grep -q $root_dev ) ); then  # Situation#2
      PostinstallRunnerAction_ChangeBootOrder || return 1
    else  # Situation#3
      . "${install_plan['write_gpt_path']}"
      load_base_vars
      # PARTITION_NUM_KERN_A or PARTITION_NUM_KERN_B
      local part_num="PARTITION_NUM_KERN_${install_plan['target_slot_alphabet']}"
      if ! [ $part_num ]; then
        part_num=`FindPartitionByLabel "KERN-${install_plan['target_slot_alphabet']}"`
      fi
      # Change boot priority
      # Mark the kernel as successfully booted (success=1, tries=0).
      debug "gptpriority: partition: $part_num"
      debug "cgpt add "${root_dev}" -i ${!part_num} -S1 -T0"
      debug "cgpt prioritize "${root_dev}" -i ${!part_num}"
      cgpt add "${root_dev}" -i ${!part_num} -S1 -T0
      # Mark the kernel as highest priority
      cgpt prioritize "${root_dev}" -i ${!part_num}  # Boot as successful device for now
      if [ $? -ne 0 ]; then
        # Probably not EFI, try syslinux
        debug "cgpt commands failed, trying syslinux"
        echo "DEFAULT chromeos-hd.${install_plan['target_slot_alphabet']}" > \
          "${install_plan['efi_partition']}/syslinux/default.cfg"
        if [ $? -ne 0 ]; then
          echo_stderr "Failed to prioritize new root. Without it new update will not boot."
          PostinstallRunnerAction_Cleanup
          return 1
        fi
      fi
    fi
    PostinstallRunnerAction_Cleanup
    return 0
}


# Determine support for swtpm
# NOTE: Although ArnoldTheBat's builds (74 or later) come with kernel
# that supports swtpm, other builds (e.g. FydeOS) may not support this.
function PostinstallRunnerAction_DetermineSWTPMSupport {
    if [ "${install_plan['tpm']}" == "false" ]; then
      # swtpm is forced disabled
      return 1
    else
      # Currently, tpm=true/auto has no difference here because if support
      # for swtpm support is not present, there's no point in applying it.
      kern_count=$(ls "${install_plan['target_partition']}/lib/modules" | wc -l) # Should be 1, but could be more than 1
      real_count=$(cat "${install_plan['target_partition']}"/lib/modules/*/modules.dep | grep tpm_vtpm_proxy.ko | wc -l 2> /dev/null)
      real_count=$(( real_count + $(cat "${install_plan['target_partition']}"/lib/modules/*/modules.builtin | grep tpm_vtpm_proxy.ko | wc -l 2> /dev/null) ))
      if [ $kern_count -eq $real_count ]; then
        # All kernels support swtpm
        install_plan['tpm']="true"
        return 0
      else
        # Not all kernels support swtpm
        install_plan['tpm']="false"
        return 1
      fi
    fi
}

#
# PostinstallRunnerAction::PerformPartitionPostinstall
#
function PostinstallRunnerAction_PerformPartitionPostinstall {
    install_plan['efi_partition']="${install_plan['download_root']}/efi_part"
    install_plan['swtpm_tar']="${install_plan['download_root']}/swtpm.tar"
    install_plan['swtpm_path']="${install_plan['download_root']}/swtpm"
    # swtpm
    PostinstallRunnerAction_DetermineSWTPMSupport
    if [ "${install_plan['tpm']}" == "true" ]; then
      debug "SWTPM support detected"
      # FIXME: Handle errors properly
      # Download swtpm
      curl -sL -o "${install_plan['swtpm_tar']}" "${install_plan['tpm_url']}" 2> /dev/null
      if [ $? -ne 0 ]; then
        echo_stderr "Failed to download swtpm.tar. Update aborted."
        rm "${install_plan['swtpm_tar']}" 2> /dev/null
        return 1
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
      return 1
    fi
    PostinstallRunnerAction_CompletePostinstall || return 1
    return 0
}

#
# PostinstallRunnerAction::PerformAction
#
function PostinstallRunnerAction_PerformAction {
    # Install update
    DeltaPerformer_Write || return 1
    # Run post install
    PostinstallRunnerAction_PerformPartitionPostinstall || return 1
    echo_stderr "Update is successfully installed. Please reboot to continue."
    PostinstallRunnerAction_update_complete="true"
    return 0
}
