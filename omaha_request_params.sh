#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# This file is converted from the original omaha_request_params.cc
# located at https://chromium.googlesource.com/chromiumos/platform/update_engine/+/refs/heads/master/omaha_request_params.cc
# Fetched 1 Jan 2020

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

[ command -v debug >/dev/null 2>&1 ] || source "${SCRIPT_DIR}/debug_utils.sh"

kOsVersion="Indy"
kChannelsByStability=(
    # This list has to be sorted from least stable to most stable channel.
    "canary-channel"
    "dev-channel"
    "beta-channel"
    "stable-channel"
)
os_platform_=
os_version_=
os_sp_=
app_lang_=
download_channel_=
hwid_=  # We don't have this
fw_version_=  # We don't have this
ec_version_=  # We don't have this
device_requisition_=  # We don't have this
delta_okay_=
interactive_=
update_url_=
target_version_prefix_=
rollback_allowed_=
rollback_data_save_requested_=
rollback_allowed_milestones_=
wall_clock_based_wait_enabled_=
waiting_period_=
update_check_count_wait_enabled_=
min_update_checks_needed_=
max_update_checks_allowed_=
root_=${root_prefix}  # OmahaRequestParams::set_root
dlc_module_ids_=
is_install_=
autoupdate_token_=

# Inline functions taken from the header file are not needed since there's no encapsulation
# Ref: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/refs/heads/master/omaha_request_params.h

#
# OmahaRequestDeviceParams::GetMachineType
#
function OmahaRequestDeviceParams_GetMachineType {
  echo `uname --machine`
}

#
# OmahaRequestParams::IsUpdateUrlOfficial
#
function OmahaRequestParams_IsUpdateUrlOfficial {
  if [ "${update_url_}" == "${kOmahaDefaultAUTestURL}" ] || [ "${update_url_}" == "${ImageProperties['omaha_url']}" ]; then
    echo "true"
  else
    echo "false"
  fi
}

#
# OmahaRequestParams::GetAppId
#
function OmahaRequestDeviceParams_GetAppId {
  if [ "${download_channel_}" == "canary-channel" ]; then
    echo "${ImageProperties['canary_product_id']}"
  else
    echo "${ImageProperties['product_id']}"
  fi
}

#
# OmahaRequestParams::GetChannelIndex
# Args: CHANNEL
function OmahaRequestParams_GetChannelIndex {
  channel="$1"
  for i in "${!kChannelsByStability[@]}"; do
   if [[ "${kChannelsByStability[$i]}" == "${channel}" ]]; then
       echo $i
       return 0
   fi
  done
  echo -1
  return 1
}

#
# OmahaRequestParams::IsValidChannel
# Args: CHANNEL
function OmahaRequestParams_IsValidChannel {
  local channel="$1"
  if [ "${ImageProperties['allow_arbitrary_channels']}" == "true" ]; then
    if ! [ "${channel##*-}" == "channel" ]; then
      echo "false"
      return 1
    fi
    echo "true"
    return 0
  fi
  
  if [ $(OmahaRequestParams_GetChannelIndex $channel) -lt 0 ]; then
    echo "false"
    return 1
  fi
  echo "true"
  return 0
}

#
# OmahaRequestParams::UpdateDownloadChannel
#
function OmahaRequestParams_UpdateDownloadChannel {
  download_channel_="${ImageProperties['target_channel']}"
  echo_stderr "Download channel for this attempt = ${download_channel_}"
}

#
# OmahaRequestParams::SetTargetChannel
# Args: NEW_TARGET_CHANNEL IS_POWERWASH_ALLOWED
function OmahaRequestParams_SetTargetChannel {
  local new_target_channel="$1"
  local is_powerwash_allowed="$2"
  if [ "$(OmahaRequestParams_IsValidChannel $new_target_channel)" == "false" ]; then
   echo "false"
   return 1
  fi
  # FIXME: keep the values in temporary identifiers
  ImageProperties['target_channel']="${new_target_channel}"
  ImageProperties['is_powerwash_allowed']="${is_powerwash_allowed}"
  
  if [ "$(StoreMutableImageProperties)" == "false" ]; then
    # FIXME: Restore data
    echo "false"
    return 1
  fi
  
  echo "true"
  return 0
}

#
# OmahaRequestParams::CollectECFWVersions
#
function OmahaRequestParams_CollectECFWVersions {
  # XXXX: We don't need this
  echo "false"
  return 0
}

#
# OmahaRequestParams::ToMoreStableChannel
#
function OmahaRequestParams_ToMoreStableChannel {
  local current_channel_index="$(OmahaRequestParams_GetChannelIndex "${ImageProperties['current_channel']}")"
  local download_channel_index="$(OmahaRequestParams_GetChannelIndex "${download_channel_}")"
  
  if [ $current_channel_index -gt $download_channel_index ]; then
    echo "true"
  else
    echo "false"
  fi
}

#
# OmahaRequestParams::ShouldPowerwash
#
function OmahaRequestParams_ShouldPowerwash {
  if [ "${ImageProperties['is_powerwash_allowed']}" == "false" ]; then echo "false"; return 1; fi
  if [ "${ImageProperties['allow_arbitrary_channels']}" == "true" ]; then
    if [ "${ImageProperties['current_channel']}" == "${download_channel_}" ]; then
      echo "false"
    else
      echo "true"
    fi
  fi
  OmahaRequestParams_ToMoreStableChannel
  return 0;
}

#
# OmahaRequestParams::Init
# Args: APP_VERSION (ForcedUpdate) UPDATE_URL INTERACTIVE
function OmahaRequestParams_Init {
  in_app_version="$1"
  in_update_url="$2"
  in_interactive="$3"
  
  echo_stderr "Initializing parameters for this update attempt"

  LoadImageProperties
  LoadMutableImageProperties
  
  if ! [ "$(OmahaRequestParams_IsValidChannel ${ImageProperties['current_channel']})" == "true" ]; then
    ImageProperties['current_channel']="stable-channel"
  fi

  if ! [ "$(OmahaRequestParams_IsValidChannel ${ImageProperties['target_channel']})" == "true" ]; then
    ImageProperties['target_channel']="${ImageProperties['current_channel']}"
  fi
  OmahaRequestParams_UpdateDownloadChannel
  
  echo_stderr "Running from channel ${ImageProperties['current_channel']}"
  os_platform_="${kOmahaPlatformName}"
  
  if [ -n "${ImageProperties['system_version']}" ]; then
    if [ "${in_app_version}" == "ForcedUpdate" ]; then
      ImageProperties['system_version']="${in_app_version}"
    fi
    os_version_="${ImageProperties['system_version']}"
  else
    os_version_="${kOsVersion}"
  fi
  
  if [ -n "${in_app_version}" ]; then
    ImageProperties['version']="${in_app_version}"
  fi
  
  os_sp_="${ImageProperties['version']}_$(OmahaRequestDeviceParams_GetMachineType)"
  app_lang_="en-US"
  hwid_="$(GetHardwareClass)"
  
  if [ "$(OmahaRequestParams_CollectECFWVersions)" == "true" ];then
    fw_version_="$(GetFirmwareVersion)"
    ec_version_="$(GetECVersion)"
  fi
  
  device_requisition_="$(GetDeviceRequisition)"
  
  if [ "${ImageProperties['current_channel']}" == "${ImageProperties['target_channel']}" ]; then
    if [ -e "${root_}/.nodelta" ]; then
      delta_okay_="false";
    else
      delta_okay_="true"
    fi
  else
    delta_okay_="false"
  fi
  delta_okay_="false"  # For now
  
  if [ -z "${in_update_url}" ];then
    update_url_="${ImageProperties['omaha_url']}"
  else
    update_url_="${in_update_url}"
  fi
  
  interactive_="${in_interactive}"
  
  dlc_module_ids_=()
  
  is_install_="false"
  
  # custom (omaha_cros_update compatibility)
  os_board_="${ImageProperties['board']}"
  app_version_="${ImageProperties['version']}"
  download_channel_="${ImageProperties['target_channel']}"
  current_channel_="${ImageProperties['current_channel']}"
}

# test
if [ "${0##*/}" == "omaha_request_params.sh" ]; then
    OmahaRequestParams_Init
    ( set -o posix ; set )
fi
