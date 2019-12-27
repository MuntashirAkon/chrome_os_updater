#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.

# Extract /boot, /lib, /usr/lib64/{dri,va} files and folders from ArnoldTheBat builds
# Args: atb_url directory catalog

if [ "$(whoami)" == "root" ]; then
    >&2 echo "Don't run it as root."
    exit 1
fi

# Args:
# $1: atb release url
# $2: save directory
# $3: atb catalog
function main {
    local cr_url="$1"
    local comp_file="$(readlink -f "$1")"
    local target_dir="$(readlink -f "$2")"
    local catalog="$(readlink -f "$3")"
    if [ -z "${cr_url}" ] || [ -z "${target_dir}" ] || [ -z "${catalog}" ]; then
        >&2 echo "USAGE: atb_url directory catalog"
        exit 1
    fi
    # The extracted file is very very large, use ~/tmp as temporary instead of /tmp
    local tmp_dir="/home/${USER}/tmp"
    local comp_file="${tmp_dir}/CrOS.7z"
    local tmp_export_dir="${tmp_dir}/export"
    local driver_export_dir="${tmp_export_dir}/usr/lib64"
    mkdir -p "${driver_export_dir}"
    # Download CrOS
    curl -#L -o "${comp_file}" "${cr_url}"
    # Extract to ~/tmp
    7z x -o"${tmp_dir}" "${comp_file}"
    # Mount ROOT-A
    local bin_path="${tmp_dir}/$(7z l "${comp_file}" | grep "chromiumos_image" | awk '{print $6}')"
    local loop_dev="$(sudo losetup --show -fP "${bin_path}")"
    local root_path="${tmp_dir}/root"
    if ! [ -d "${root_path}" ]; then
        mkdir "${root_path}"
    fi
    sudo mount "${loop_dev}p3" "${root_path}"
    # Get version
    local version="R$(cat "${root_path}"/etc/lsb-release | grep "CHROME_MILESTONE" | awk -F '=' '{print $2}')"
    local build="$(cat "${root_path}"/etc/lsb-release | grep "BUILD_NUMBER" | awk -F '=' '{print $2}')"
    # Copy files
    cp -a "${root_path}"/{lib,boot} "${tmp_export_dir}"
    cp -a "${root_path}"/usr/lib64/{dri,va} "${driver_export_dir}"
    # Create iso.gz
    local label="CrOS_${version}-${build}"
    local img_file="${target_dir}/${label}.iso.gz"
    mkisofs -V "${label}" -r "${tmp_export_dir}" | gzip > "${img_file}"
    # Add to catalog
    local cat_txt="${version} ${build} https://raw.githubusercontent.com/MuntashirAkon/chrome_os_updater/master/atb_updates/${label}.iso.gz"
    echo "${cat_txt}" > $catalog
    # Cleanup
    sudo umount "${root_path}"
    sudo losetup --detach "${loop_dev}"
    rm -rf "${tmp_dir}"/*
}

main "$@"
exit 0
