#!/usr/bin/env python
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# Source: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/a1f4a7dcaa921fcb0ab395214a9558a62ca083f2/power_manager_chromeos.cc
# Fetched 1 Jan 2020

#
# PowerManagerChromeOS::RequestReboot
#
function PowerManagerChromeOS_RequestReboot {
  # Original method uses dbus send shutdown request. But I won't going to do that here for now
  if "/sbin/shutdown" -r now; then echo "true"; else echo "false"; fi
}
