#!/bin/bash
# 2020 (c) Muntashir Al-Islam. All rights reserved.
# Source: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/master/image_properties_chromeos.cc
# Fetched 1 Jan 2020

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "${SCRIPT_DIR}/common/constants.sh"
. "${SCRIPT_DIR}/common/platform_constants.sh"
. "${SCRIPT_DIR}/hardware_chromeos.sh"

kLsbRelease="/etc/lsb-release"

kLsbReleaseAppIdKey="CHROMEOS_RELEASE_APPID"
kLsbReleaseAutoUpdateServerKey="CHROMEOS_AUSERVER"
kLsbReleaseBoardAppIdKey="CHROMEOS_BOARD_APPID"
kLsbReleaseBoardKey="CHROMEOS_RELEASE_BOARD"
kLsbReleaseCanaryAppIdKey="CHROMEOS_CANARY_APPID"
kLsbReleaseIsPowerwashAllowedKey="CHROMEOS_IS_POWERWASH_ALLOWED"
kLsbReleaseUpdateChannelKey="CHROMEOS_RELEASE_TRACK"
kLsbReleaseVersionKey="CHROMEOS_RELEASE_VERSION"
kDefaultAppId="{87efface-864d-49a5-9bb3-4b050a7c227a}"

root_prefix=  # must end with a slash `/`

LsbReleaseSource_kSystem=0
LsbReleaseSource_kStateful=1

declare -A ImageProperties

ImageProperties['product_id']=
ImageProperties['canary_product_id']=
ImageProperties['system_id']=
ImageProperties['version']=
ImageProperties['system_version']=
ImageProperties['product_components']=
ImageProperties['build_fingerprint']=
ImageProperties['build_type']=
ImageProperties['board']=
ImageProperties['current_channel']=
ImageProperties['allow_arbitrary_channels']="false"
ImageProperties['omaha_url']=
ImageProperties['target_channel']=  # MutableImageProperties
ImageProperties['is_powerwash_allowed']="false"  # MutableImageProperties

# Args: $key default_value
function GetStringWithDefault {
  key="$1"
  default_value="$2"
  if [ "${!key}" ]; then
    echo "${!key}"
  else
    echo "${default_value}"
  fi
}

# Args: LsbReleaseSource
function LoadLsbRelease {
  local source="$1"
  local path="${root_prefix}"
  if [ "${source}" == "${LsbReleaseSource_kStateful}" ];then
    path+="${kStatefulPartition}"
  fi
  path+="${kLsbRelease}"
  touch "${path}" 2> /dev/null
  eval $(awk -F '=' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $1"=\""$2"\""}' "${path}" 2> /dev/null)
}


function LoadImageProperties {
  LoadLsbRelease $LsbReleaseSource_kSystem
  ImageProperties['current_channel']="$(GetStringWithDefault $kLsbReleaseUpdateChannelKey "stable-channel")"
  if [ "$(IsOfficialBuild)" == "false" ] || [ "$(IsNormalBootMode)" == "false" ]; then
    LoadLsbRelease $LsbReleaseSource_kStateful
  fi
  local release_app_id="$(GetStringWithDefault $kLsbReleaseAppIdKey $kDefaultAppId)"
  ImageProperties['product_id']="$(GetStringWithDefault $kLsbReleaseBoardAppIdKey $release_app_id)"
  ImageProperties['canary_product_id']="$(GetStringWithDefault $kLsbReleaseCanaryAppIdKey $release_app_id)"
  ImageProperties['board']="$(GetStringWithDefault $kLsbReleaseBoardKey "")"
  ImageProperties['version']=$(GetStringWithDefault $kLsbReleaseVersionKey "")
  ImageProperties['omaha_url']="$(GetStringWithDefault $kLsbReleaseAutoUpdateServerKey $kOmahaDefaultProductionURL)"
  ImageProperties['build_fingerprint']=""
  ImageProperties['allow_arbitrary_channels']="false"
}

function LoadMutableImageProperties {
  LoadLsbRelease $LsbReleaseSource_kSystem
  LoadLsbRelease $LsbReleaseSource_kStateful
  ImageProperties['target_channel']="$(GetStringWithDefault $kLsbReleaseUpdateChannelKey "stable-channel")"
  ImageProperties['is_powerwash_allowed']="$(GetStringWithDefault $kLsbReleaseIsPowerwashAllowedKey "false")"
}

function StoreMutableImageProperties {
  local path="${root_prefix}/${kStatefulPartition}/${kLsbRelease}"
  mkdir -p "${root_prefix}/${kStatefulPartition}/etc"
  echo -e "${kLsbReleaseUpdateChannelKey}=${ImageProperties['target_channel']}\n${kLsbReleaseIsPowerwashAllowedKey}=${ImageProperties['is_powerwash_allowed']}" > "${path}"
  chmod 644 $path  # Make readable for all
  if [ $? -eq 0 ]; then echo "true"; else echo "false"; fi
}

# Args: root_prefix
function SetImagePropertiesRootPrefix {
  root_prefix="$1"
}
