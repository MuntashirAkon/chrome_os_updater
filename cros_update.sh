#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# NOTE: TPM 1.2 fix is adapted from the Chromefy project and
# this copyright doesn't apply them.


if [ $UID -ne 0 ]; then
  >&2 echo "This script must be run as root!"
  exit 1
fi

# Global variables
code_name=
recovery="/tmp/recovery.conf"

# Echo to stderr
function echo_stderr {
  >&2 echo "$@"
}

# Print Usage
function print_usage {
  echo_stderr "Usage: cros_update.sh [--check-only]"
  echo_stderr "Run cros_update.sh without any argument to update Chrome OS"
  echo_stderr "--check-only  Only check for update."
}

# Get installed version info
# Output: <code name> <milestone> <platform version> <cros version>
# Example: eve 72 11316.165.0 72.0.3626.122
function get_installed {
  local rel_info=`cat /etc/lsb-release | grep CHROMEOS_RELEASE_BUILDER_PATH | sed -e 's/^.*=\(.*\)-release\/R\(.*\)-\(.*\)$/\1 \2 \3/'` # \1 = code name, eg. eve
  local cros_v=`/opt/google/chrome/chrome --version | sed -e 's/^[^0-9]\+\([0-9\.]\+\).*$/\1/'`
  echo "${rel_info} ${cros_v}"
}


# Get environment variable from recovery.conf
# $1: recovery.conf url
# $2: code name (all caps)
# $3: variable name
# Output: variable content
function get_env {
  local recovery=$1
  local loc=`cat "${recovery}" | grep -n "\b$2\b" | sed 's/:.*//' 2> /dev/null` # Get line number
  local match=$3
  local matched=

  local i=${loc}
  while true; do
    i=$(( i + 1 ))
    local text=`sed -n "${i}p" "${recovery}" 2> /dev/null`
    if [ "${text}" == "" ]; then break; fi
    echo "${text}" | grep "\b${match}\b" > /dev/null 2>&1
    if [ $? -ne 0 ]; then continue; fi
    matched=`echo "${text}" | sed 's/.*=\(.*\)/\1/' 2> /dev/null`
    break
  done

  if [ "${matched}" == "" ]; then
    i=${loc}
    while true; do
      i=$(( i - 1 ))
      local text=`sed -n "${i}p" "${recovery}" 2> /dev/null`
      if [ "${text}" == "" ]; then break; fi
      echo "${text}" | grep "\b${match}\b" > /dev/null 2>&1
      if [ $? -ne 0 ]; then continue; fi
      matched=`echo "${text}" | sed 's/.*=\(.*\)/\1/' 2> /dev/null`
      break
    done
  fi
  # return var content
  echo "${matched}"
}

# Check if there's an update
# $1: Code Name
# $2: Milestone
# $3: Platform version
# $4: Cros version
function check_for_update {
  echo_stderr "Checking for update..."
  curl -sL "https://dl.google.com/dl/edgedl/chromeos/recovery/recovery.conf" -o "${recovery}" 2> /dev/null
  if [ $? -ne 0 ] && ! [ -f "$recovery" ]; then
    echo_stderr "No internet connection! Try again."
    exit 1
  fi

  code_name=`echo "$1" | awk '{ print toupper($0) }'`
  local ins_plarform=$3
  local rem_platform=`get_env "${recovery}" "${code_name}" 'version'`

  if [ "${ins_plarform}" = "${rem_platform}" ]; then
    echo_stderr "No update available."
    exit 0
  else # Update available
    echo_stderr "Update available (Chrome OS ${rem_platform})."
    return 0
  fi
}

# Check if there's an update, download it if available.
# $1: Code Name
# $2: Milestone
# $3: Platform version
# $4: Cros version
# Output: recovery file location or empty
function download_update {
  check_for_update "$@"

  #local md5sum=`get_env "${recovery}" "${code_name}" 'md5'`
  local file_size=`get_env "${recovery}" "${code_name}" 'zipfilesize'`
  local file_name=`get_env "${recovery}" "${code_name}" 'file'`
  local file_url=`get_env "${recovery}" "${code_name}" 'url'`
  file_size=`bc -l <<< "scale=2; ${file_size}/1073741824"`

  echo_stderr "Downloading ${file_name} (${file_size} GB)..."
  # TODO: take ${root} as input
  local user=`logname 2> /dev/null`
  if [ "$user" == "" ]; then
    user="chronos"
  fi
  local root="/home/${user}"
  local file_loc_zip="${root}/${file_name}.zip"
  local file_loc="${root}/${file_name}"
  if ! [ -f "${file_loc}" ]; then
    curl -\#L -o "${file_loc_zip}" "${file_url}" 2> /dev/null
    # TODO: match checksum
    if [ $? -ne 0 ]; then
      echo_stderr "Failed downloading the update. Try again."
      exit 1
    fi
    unzip -d "${root}" "${file_loc_zip}"
    if [ $? -ne 0 ]; then
      echo_stderr "Failed extracting the update. Try again."
      exit 1
    fi
    rm ${file_loc_zip}
  fi
  echo "${file_loc}"
  return 0
}


# Download swtpm.tar
# $1: swtpm.tar location
function download_swtpm {
    local swtpm_tar=$1
    echo_stderr -n "Downloading swtpm.tar..."
    if ! [ -f "${swtpm_tar}" ]; then
      curl -\#L -o "${swtpm_tar}" "https://github.com/imperador/chromefy/raw/master/swtpm.tar" 2> /dev/null
      if [ $? -ne 0 ]; then
        echo_stderr -e "\nFailed downloading the swtpm.tar. Try again."
        exit 1
      fi
    fi
    echo_stderr "Done."
    return 0
}


# Cleanup the mount point if exists
# $1: Partition name e.g. /dev/sda11
# $2: Mount point
function cleanupIfAlreadyExists {
    local part_name="$1"
    local mount_point="$2"
    if [ -e "${mount_point}" ]; then
      umount "${mount_point}" 2> /dev/null
      umount "${part_name}" 2> /dev/null
      rm -rf "${mount_point}"
    fi
    mkdir "${mount_point}"
}


function main {
    if [ "$1" == "--check-only" ]; then
      check_for_update $(get_installed)
      exit 0
    fi
    echo_stderr "Reading cros_update.conf..."
    local conf_path="/usr/local/cros_update.conf"
    # Create cros_update.conf if not exists
    touch "${conf_path}"

    # cros_update.conf format:
    # ROOTA='<ROOT-A UUID, lowercase>'
    # ROOTB='<ROOT-B UUID, lowercase>'
    # EFI='<EFI-SYSTEM UUID, lowercase>'
    # TPM=true/false

    # Read cros_update.conf
    source "${conf_path}"
    local root_a_uuid=${ROOTA}
    local root_b_uuid=${ROOTB}
    local efi_uuid=${EFI}

    # Validate conf
    if [ "${root_a_uuid}" = "" ] || [ "${root_b_uuid}" = "" ] || [ "${efi_uuid}" = "" ]; then
      echo_stderr "Invalid configuration, mandatory items missing."
      exit 1
    fi

    # Whether to apply TPM 1.2 fix
    local tpm_fix=${TPM}

    # Convert uuid to /dev/sdXX
    local root_a_part=`sudo /sbin/blkid --uuid "${root_a_uuid}"`
    local root_b_part=`sudo /sbin/blkid --uuid "${root_b_uuid}"`
    local efi_part=`sudo /sbin/blkid --uuid "${efi_uuid}"`
    
    # Current root, /dev/sdXX
    local c_root=`mount | grep -E '\s/\s' -m 1 | awk '{print $1}'`
    # Target root, /dev/sdXX
    local t_root=''
    if [ "${c_root}" = "${root_a_part}" ]; then
      t_root="${root_b_part}"
    else
      t_root="${root_a_part}"
    fi

    # Set root directory
    local user=`logname 2> /dev/null`
    if [ "$user" == "" ]; then
      user="chronos"
    fi
    local root="/home/${user}"


    # Check for update & download them
    local installed_data=`get_installed`
    local recovery_img=`download_update ${installed_data}`
    if [ $? -ne 0 ] || [ "$recovery_img" == "" ]; then
      exit 1
    fi
    
    local swtpm_tar="${root}/swtpm.tar"
    if [ "${tpm_fix}" == true ]; then
      download_swtpm "${swtpm_tar}"
    fi

    # Update
    echo_stderr -n "Updating Chrome OS..."
    local hdd_root="${root}/t_root_a" # Target root
    local img_root_a="${root}/i_root_a" # Img root
    local swtpm="${root}/swtpm"
    
    # Mount target partition
    cleanupIfAlreadyExists "${t_root}" "${hdd_root}"
    mount -o rw -t ext4 "${t_root}" "${hdd_root}"

    # Mount recovery image
    local img_disk=`/sbin/losetup --show -fP "${recovery_img}"`
    local img_root_a_part="${img_disk}p3"
    cleanupIfAlreadyExists "${img_root_a_part}" "${img_root_a}"
    mount -o ro "${img_root_a_part}" "${img_root_a}"

    # Copy all the files from image to target partition
    rm -rf "${hdd_root}"/*
    cp -a "${img_root_a}"/* "${hdd_root}" 2> /dev/null
    
    # Copy modified files from current partition to target partition
    rm -rf "${hdd_root}/lib/firmware" "${hdd_root}/lib/modules"
    rm -rf "${hdd_root}/etc/modprobe.d"/alsa*.conf
    cp -a /{lib,boot} "${hdd_root}/"
    cp -na /usr/lib64/{dri,va} "${hdd_root}/usr/lib64/"
    cp -a "/usr/sbin/write_gpt.sh" "${hdd_root}/usr/sbin"
    cp -a "/etc/gesture/40-touchpad-cmt.conf" "${hdd_root}/etc/gesture"
    cp -a "/etc/chrome_dev.conf" "${hdd_root}/etc"
    cp -a "/etc/init/mount-internals.conf" "${hdd_root}/etc/init" 2> /dev/null
    sed '0,/enforcing/s/enforcing/permissive/' -i "${hdd_root}/etc/selinux/config"
    echo_stderr "Done."
    # Apply TPM fix
    if [ "${tpm_fix}" = true ]; then
      echo_stderr -n "Fixing TPM..."
      # Extract swtpm.tar
      tar -xf "${swtpm_tar}" -C "${root}"
      # Copy necessary files
      cp -a "${swtpm}"/usr/sbin/* "${hdd_root}/usr/sbin"
      cp -a "${swtpm}"/usr/lib64/* "${hdd_root}/usr/lib64"
      # Symlink libtpm files
      cd "${hdd_root}/usr/lib64"
      ln -s libswtpm_libtpms.so.0.0.0 libswtpm_libtpms.so.0
      ln -s libswtpm_libtpms.so.0 libswtpm_libtpms.so
      ln -s libtpms.so.0.6.0 libtpms.so.0
      ln -s libtpms.so.0 libtpms.so
      ln -s libtpm_unseal.so.1.0.0 libtpm_unseal.so.1
      ln -s libtpm_unseal.so.1 libtpm_unseal.so
      # Start at boot (does is necessary?)
      cat > "${hdd_root}/etc/init/_vtpm.conf" <<EOL
    start on started boot-services

    script
        mkdir -p /var/lib/trunks
        modprobe tpm_vtpm_proxy
        swtpm chardev --vtpm-proxy --tpm2 --tpmstate dir=/var/lib/trunks --ctrl type=tcp,port=10001
        swtpm_ioctl --tcp :10001 -i
    end script
EOL
      echo_stderr "Done."
    fi

    # Update Grub
    echo_stderr -n "Updating GRUB..."
    local efi_dir="${root}/efi"
    cleanupIfAlreadyExists "${efi_part}" "${efi_dir}"
    mount -o rw "${efi_part}" "${efi_dir}"
    local hdd_uuid=`/sbin/blkid -s PARTUUID -o value "${t_root}"`
    local old_uuid=`cat "${efi_dir}/efi/boot/grub.cfg" | grep -m 1 "PARTUUID=" | awk '{print $15}' | cut -d'=' -f3`
    sed -i "s/${old_uuid}/${hdd_uuid}/" "${efi_dir}/efi/boot/grub.cfg"
    if [ $? -eq 0 ]; then
      echo_stderr "Done."
    else
      echo_stderr
      echo_stderr "Failed fixing GRUB, please try fixing it manually."
      exit 1
    fi
    
    echo_stderr -n "Updating partition data..."
    local hdd_root_part_no=`echo ${t_root} | sed 's/^[^0-9]\+\([0-9]\+\)$/\1/'`
    local write_gpt_path="${hdd_root}/usr/sbin/write_gpt.sh"
    # Remove unnecessary partitions & update properties
    cat "${write_gpt_path}" | grep -vE "_(KERN_(A|B|C)|2|4|6|ROOT_(B|C)|5|7|OEM|8|RESERVED|9|10|RWFW|11)" | sed \
    -e "s/^\(\s*PARTITION_NUM_ROOT_A=\)\"[0-9]\+\"$/\1\"${hdd_root_part_no}\"/g" \
    -e "s/^\(\s*PARTITION_NUM_3=\)\"[0-9]\+\"$/\1\"${hdd_root_part_no}\"/g" \
     | tee "${write_gpt_path}" > /dev/null
    # -e "w ${write_gpt_path}" # doesn't work on CrOS
    if [ $? -eq 0 ]; then
      echo_stderr "Done."
    else
      echo_stderr
      echo_stderr "Failed updating partition data, please try fixing it manually."
      exit 1
    fi

    # Unmount and cleanup
    umount "${hdd_root}" 2> /dev/null
    if [ $? -eq 0 ]; then
      rm -rf "${hdd_root}"
    fi
    umount "${img_root_a}" 2> /dev/null
    if [ $? -eq 0 ]; then
      rm -rf "${img_root_a}"
    fi
    umount "${efi_dir}" 2> /dev/null
    if [ $? -eq 0 ]; then
      rm -rf "${efi_dir}"
    fi
    /sbin/losetup -d "${img_disk}" 2> /dev/null
    rm "${swtpm_tar}" "${recovery_img}" 2> /dev/null
    rm -rf "${swtpm}" 2> /dev/null
    echo_stderr "Update complete. You can now reboot safely."
}

main "$@"
exit 0
