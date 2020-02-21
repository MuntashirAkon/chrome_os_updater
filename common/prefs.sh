#!/bin/bash
# 2020 (c) Muntashir Al-Islam. All rights reserved.
# Source: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/master/common/prefs.h
# Fetched 2 Jan 2020

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "${SCRIPT_DIR}/common/constants.sh"
. "${SCRIPT_DIR}/common/platform_constants.sh"

# Currently no support for powerwash-preserved directory
prefs_dir_="${kNonVolatileDirectory}/${kPrefsSubDirectory}"

#
# Prefs::Delete
# Args: PREF_KEY
function Prefs_Delete {
  local key="$1"
  local key_path="${prefs_dir_}/${key}"
  if [ -f "${key_path}" ]; then
    rm "${key_path}"
  fi
}

#
# Prefs::GetKey, GetString, GetInt*, etc.
# Args: PREF_KEY
# Return: VALUE
function Prefs_GetKey {
  local key="$1"
  local key_path="${prefs_dir_}/${key}"
  if [ -f "${key_path}" ]; then
    cat "${key_path}"
  else
    echo ""
  fi
}

#
# Prefs::SetKey, SetString, SetInt*, etc.
# Args: PREF_KEY VALUE
function Prefs_SetKey {
  local key="$1"
  local value="$2"
  local key_path="${prefs_dir_}/${key}"
  echo "${value}" > "${key_path}"
}

#
# Prefs::Init
# Args: ROOT_PREFIX
function Prefs_Init {
  local root_prefix="$1"
  prefs_dir_="${root_prefix}${kNonVolatileDirectory}/${kPrefsSubDirectory}"
}

