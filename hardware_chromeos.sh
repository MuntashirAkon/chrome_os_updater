#!/bin/bash
# 2020 (c) Muntashir Al-Islam. All rights reserved.
# Source: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/refs/heads/master/hardware_chromeos.cc
# Fetched 1 Jan 2020

kOOBECompletedMarker="/home/chronos/.oobe_completed"
kPowerwashSafeDirectory="/mnt/stateful_partition/unencrypted/preserve"
kPowerwashCountMarker="powerwash_count"
kPowerwashMarkerFile="/mnt/stateful_partition/factory_install_reset"
kRollbackSaveMarkerFile="/mnt/stateful_partition/.save_rollback_data"
kPowerwashCommand="safe fast keepimg reason=update_engine\n"
kRollbackPowerwashCommand="safe fast keepimg rollback reason=update_engine\n"
kConfigFilePath="/etc/update_manager.conf"
kConfigOptsIsOOBEEnabled="is_oobe_enabled"
kActivePingKey="first_active_omaha_ping_sent"
kOemRequisitionKey="oem_device_requisition"

function IsOfficialBuild {
  if [ "$(crossystem debug_build)" == "0" ]; then echo "true"; else echo "false"; fi
}

function IsNormalBootMode {
  if ! [ "$(crossystem devsw_boot)" == "0" ]; then echo "true"; else echo "false"; fi
}

function AreDevFeaturesEnabled {
  # TODO
  echo "true"
}

#
# HardwareChromeOS::GetHardwareClass
#
function GetHardwareClass {
  echo "$(crossystem hwid)"
}

#
# GetFirmwareVersion
#
function GetFirmwareVersion {
  echo "$(crossystem fwid)"
}

#
# GetECVersion
#
function GetECVersion {
  # Doesn't work /usr/sbin/mosys -k ec info
  echo ""
}


#
# GetDeviceRequisition
#
function GetDeviceRequisition {
  echo "$("/usr/sbin/vpd_get_value" $kOemRequisitionKey 2> /dev/null)"
}
