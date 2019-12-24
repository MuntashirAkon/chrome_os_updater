#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# This file is converted from the original postinstall_runner_action.cc
# located at https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master/payload_consumer/postinstall_runner_action.cc
# fetched at 23 December 2019
# NOTE: The conversion is a gradual process, it may take some time

# Get script directory 
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "$SCRIPT_DIR/download_action.sh"
. "$SCRIPT_DIR/delta_performer.sh"

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
# PostinstallRunnerAction::CompletePostinstall
#
function PostinstallRunnerAction_CompletePostinstall {
    install_plan['target_slot_no']=`echo ${install_plan['target_slot']} | sed 's/^[^0-9]\+\([0-9]\+\)$/\1/'`
    install_plan['write_gpt_path']="${install_plan['target_partition']}/usr/sbin/write_gpt.sh"
    # Remove unnecessary partitions & update partition data
    cat "${install_plan['write_gpt_path']}" | grep -vE "_(KERN_(A|B|C)|2|4|6|ROOT_(B|C)|5|7|OEM|8|RESERVED|9|10|RWFW|11)" | sed \
    -e "s/^\(\s*PARTITION_NUM_ROOT_A=\)\"[0-9]\+\"$/\1\"${install_plan['target_slot_no']}\"/g" \
    -e "s/^\(\s*PARTITION_NUM_3=\)\"[0-9]\+\"$/\1\"${install_plan['target_slot_no']}\"/g" \
     | tee "${install_plan['write_gpt_path']}" > /dev/null
    # -e "w ${install_plan['write_gpt_path']}" # doesn't work on CrOS
    if [ $? -ne 0 ]; then
      echo_stderr "Failed to update partition data. Update aborted."
      PostinstallRunnerAction_Cleanup
      exit 1
    fi
    # Update grub FIXME: should be part of BootControl
    local hdd_uuid=`/sbin/blkid -s PARTUUID -o value "${install_plan['target_slot']}"`
    local old_uuid=`cat "${install_plan['efi_partition']}/efi/boot/grub.cfg" | grep -m 1 "PARTUUID=" | awk '{print $15}' | cut -d'=' -f3`
    sed -i "s/${old_uuid}/${hdd_uuid}/" "${install_plan['efi_partition']}/efi/boot/grub.cfg"
    if [ $? -ne 0 ]; then
      echo_stderr "Failed to update GRUB. Without it new update will not boot."
      PostinstallRunnerAction_Cleanup
      exit 1
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
    PostinstallRunnerAction_PerformAction
    ( set -o posix ; set )
fi
