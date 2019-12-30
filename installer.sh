#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.

## Install requirements
# mount / as rw
sudo mount -o rw,remount /
# Install crew
crew="$(command -v crew)"
if ! [ -x "${crew}" ]; then
    curl -Ls https://raw.github.com/skycocker/chromebrew/master/install.sh | bash
fi
crew="$(command -v crew)"
if ! [ -x "${crew}" ]; then
    echo "Failed to install crew!"
    exit 1
fi
# Install setup tools, python27
"${crew}" install setuptools python27
if [ $? -ne 0 ]; then
    echo "Failed to install setuptools or python 2.7!"
    exit 1
fi
# Install pip
pip="$(command -v pip2.7)"
if ! [ -x "${pip}" ]; then
    curl -Ls https://bootstrap.pypa.io/get-pip.py | python2.7
fi
pip="$(command -v pip2.7)"
if ! [ -x "${pip}" ]; then
    echo "Failed to install pip!"
    exit 1
fi
# Install protobuf and lzma
sudo "${pip}" install protobuf backports.lzma
if [ $? -ne 0 ]; then
    echo "Failed to install protobuf or lzma python module(s)!"
    exit 1
fi
## Install chrome_os_updater
echo "Installing chrome_os_updater..."
install_dir="/usr/local/updater"
sudo rm -rf /usr/local/updater/chrome_os_updater 2> /dev/null
sudo rm /usr/local/bin/omaha_cros_update.sh 2> /dev/null
curl -Ls https://github.com/MuntashirAkon/chrome_os_updater/archive/master.zip -o /tmp/cros_updater.zip && \
sudo unzip -o -d "${install_dir}" /tmp/cros_updater.zip && \
sudo mv "${install_dir}/chrome_os_updater-master" "${install_dir}/chrome_os_updater" && \
sudo ln -s /usr/local/updater/chrome_os_updater/omaha_cros_update.sh /usr/local/bin/omaha_cros_update.sh && \
sudo chmod +x /usr/local/bin/omaha_cros_update.sh
if [ $? -ne 0 ]; then
    echo "Failed to install chrome_os_updater!"
    exit 1
fi
echo "chrome_os_updater installed at ${install_dir}/chrome_os_updater."
echo "Run: omaha_cros_update.sh --check-only for verification."
exit 0