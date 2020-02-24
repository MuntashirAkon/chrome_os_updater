#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
## "sudo" check
if [ $UID -eq 0 ]; then
  echo "Don't run it as root!"
  exit 1
fi
## Install requirements
# Does this really necessary?
sudo mount -o rw,remount /
# Workaround for some python packages (e.g. dbus-python)
sudo mount -o exec,remount /tmp
# Install crew
crew="$(command -v crew)"
if ! [ -x "${crew}" ]; then
    yes | bash <(curl -Ls https://raw.github.com/skycocker/chromebrew/master/install.sh)
fi
crew="$(command -v crew)"
if ! [ -x "${crew}" ]; then
    echo "Failed to install crew!"
    exit 1
fi
# Install setup tools, pygobject, dbus glib
yes | "${crew}" install setuptools pygobject2 pygobject dbus_glib
if [ $? -ne 0 ]; then
    echo "Failed to install setuptools"
    exit 1
fi
# Install pip
pip="$(command -v pip3)"
if ! [ -x "${pip}" ]; then
    curl -Ls https://bootstrap.pypa.io/get-pip.py | python3
fi
pip="$(command -v pip3)"
if ! [ -x "${pip}" ]; then
    echo "Failed to install pip!"
    exit 1
fi
# Install protobuf, PyGObject, dbus-python
"${pip}" install protobuf PyGObject dbus-python
if [ $? -ne 0 ]; then
    echo "Failed to install python module(s)!"
    exit 1
fi
# Remove dbus
"${crew}" remove dbus
## Install chrome_os_updater
echo "Installing chrome_os_updater..."
install_dir="/usr/local/updater"
bin_dir="/usr/local/bin"
# Remove old files
[ -e "${install_dir}" ] && ( rm -rf "${install_dir}" 2> /dev/null || sudo rm -rf "${install_dir}" )
[ -e "${bin_dir}"/omaha_cros_update.sh ] && ( rm "${bin_dir}"/omaha_cros_update.sh 2> /dev/null || sudo rm "${bin_dir}"/omaha_cros_update.sh )
mkdir -p "${install_dir}" 2> /dev/null
# Download and install cros_updater
tmp_file="/tmp/chrome_os_updater.zip"
curl -Ls https://github.com/MuntashirAkon/chrome_os_updater/archive/master.zip -o "${tmp_file}" && \
unzip -o -d "${install_dir}" "${tmp_file}" && \
mv "${install_dir}"/chrome_os_updater{-master,} && \
ln -sfn "${install_dir}"/chrome_os_updater/omaha_cros_update.sh "${bin_dir}"/omaha_cros_update.sh && \
chmod +x "${bin_dir}"/omaha_cros_update.sh && \
ln -sfn "${install_dir}"/chrome_os_updater/update_engine/update_engine.py "${bin_dir}"/update_engine && \
chmod +x "${bin_dir}"/update_engine  # This should take precedence over the real update_engine
if [ $? -ne 0 ]; then
    echo "Failed to install chrome_os_updater!"
    exit 1
fi
echo "chrome_os_updater installed at ${install_dir}/chrome_os_updater."
echo "Run: omaha_cros_update.sh --version for verification."
exit 0
