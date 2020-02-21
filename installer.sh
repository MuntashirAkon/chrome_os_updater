#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.

## Install requirements
# mount / as rw
sudo mount -o rw,remount /
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
# Install setup tools
yes | "${crew}" install setuptools
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
# Install protobuf
"${pip}" install protobuf
if [ $? -ne 0 ]; then
    echo "Failed to install protobuf python module(s)!"
    exit 1
fi
## Install chrome_os_updater
echo "Installing chrome_os_updater..."
install_dir="/usr/local/updater"
sudo rm -rf /usr/local/updater/chrome_os_updater 2> /dev/null
curl -Ls https://github.com/MuntashirAkon/chrome_os_updater/archive/master.zip -o /tmp/cros_updater.zip && \
sudo unzip -o -d "${install_dir}" /tmp/cros_updater.zip && \
sudo mv "${install_dir}/chrome_os_updater-master" "${install_dir}/chrome_os_updater" && \
sudo ln -sfn /usr/local/updater/chrome_os_updater/omaha_cros_update.sh /usr/local/bin/omaha_cros_update.sh && \
sudo chmod +x /usr/local/bin/omaha_cros_update.sh
if [ $? -ne 0 ]; then
    echo "Failed to install chrome_os_updater!"
    exit 1
fi
echo "chrome_os_updater installed at ${install_dir}/chrome_os_updater."
echo "Run: omaha_cros_update.sh --check-only for verification."
exit 0
