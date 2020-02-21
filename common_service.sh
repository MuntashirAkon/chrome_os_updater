#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# Taken from https://chromium.googlesource.com/aosp/platform/system/update_engine/+/a1f4a7dcaa921fcb0ab395214a9558a62ca083f2/common_service.h
# Combined with https://chromium.googlesource.com/aosp/platform/system/update_engine/+/a1f4a7dcaa921fcb0ab395214a9558a62ca083f2/dbus_service.cc
#
# Dependency: system_state.h (update_attempter, device_policy, prefs_interface, ConnectionManagerInterface, ClockInterface, BootControlInterface)

# update_engine.py calls this to get information
# DO NOT call it yourself as it may be unstable

# IN: As argument <method|signal> <method|signal args...>
# OUT: As echo (stdout)

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"


function AttemptUpdate { # in_app_version, in_omaha_url
  AttemptUpdateWithFlags "$1" "$2"
}


function AttemptUpdateWithFlags {
  local in_app_version="$1"
  local in_omaha_url="$2"
  local in_flags="$3"
  
  . "${SCRIPT_DIR}/update_status.py"
  local interactive=$(( ! ( in_flags & kFlagNonInteractive ) ))
  local flags=$kFlagNonInteractive
  if [ $interactive -eq 1 ]; then flags=0; fi
  # From UpdateEngineService::AttemptUpdate
  . "${SCRIPT_DIR}/update_attempter.sh"
  UpdateAttempter_Init
  UpdateAttempter_CheckForUpdate "$1" "$2" "$flags"
}

# bool AttemptInstall(const std::string& omaha_url, const std::vector<std::string>& dlc_module_ids);
# bool AttemptRollback(bool in_powerwash);

function CanRollback { # out_can_rollback
  . "${SCRIPT_DIR}/update_attempter.sh"
  UpdateAttempter_Init
  UpdateAttempter_CanRollback
}

function ResetStatus {
  . "${SCRIPT_DIR}/update_attempter.sh"
  UpdateAttempter_Init
  UpdateAttempter_ResetStatus
  return 0
}

function GetStatus { # Serials: out_last_checked_time, out_progress, out_current_operation, out_new_version, out_new_size
  . "${SCRIPT_DIR}/update_attempter.sh"
  . "${SCRIPT_DIR}/update_status_utils.sh"
  UpdateAttempter_Init
  UpdateAttempter_GetStatus
  echo "${last_checked_time:-0} ${progress:-0.0} $(UpdateStatusToString "${status:-0}") ${new_version:-0.0.0.0} ${new_size_bytes:-0}"
}

function GetStatusAdvanced {
  . "${SCRIPT_DIR}/update_attempter.sh"
  UpdateAttempter_Init
  UpdateAttempter_GetStatus
  echo "${last_checked_time:-0} ${progress:-0.0} ${status:-0} ${new_version:-0.0.0.0} ${new_size_bytes:-0} ${is_enterprise_rollback:-false} ${is_install:-false} ${eol_date:-0}"
}

function RebootIfNeeded {
  . "${SCRIPT_DIR}/update_attempter.sh"
  if [ "$(UpdateAttempter_RebootDirectly)" == "true" ]; then return 0; else return 1; fi
}

function SetChannel {
  local in_target_channel="$1"
  local in_is_powerwash_allowed="$2"
  
  . "${SCRIPT_DIR}/omaha_request_params.sh"
  OmahaRequestParams_Init
  # TODO: Implement device policy
  if [ "$(OmahaRequestParams_SetTargetChannel "${in_target_channel}" "${in_is_powerwash_allowed}")" == "false" ]; then
    return 1
  else
    return 0
  fi
}

function GetChannel {
  local in_get_current_channel="$1"
  
  . "${SCRIPT_DIR}/omaha_request_params.sh"
  OmahaRequestParams_Init
  if [ "$in_get_current_channel" == "true" ]; then
    echo "${ImageProperties['current_channel']}"
  else
    echo "${ImageProperties['target_channel']}"
  fi
  return 0
}

# bool SetCohortHint(std::string in_cohort_hint);
# bool GetCohortHint(std::string* out_cohort_hint);
# bool SetP2PUpdatePermission(bool in_enabled);
# bool GetP2PUpdatePermission(bool* out_enabled);
# bool SetUpdateOverCellularPermission(bool in_allowed);
# bool SetUpdateOverCellularTarget(const std::string& target_version, int64_t target_size);
# bool GetUpdateOverCellularPermission(bool* out_allowed);
# bool GetDurationSinceUpdate(int64_t* out_usec_wallclock);

function GetPrevVersion {
  . "${SCRIPT_DIR}/update_attempter.sh"
  UpdateAttempter_Init
  echo "${prev_version_}"
}

function GetRollbackPartition {
  . "${SCRIPT_DIR}/update_attempter.sh"
  BootControlChromeOS_Init
  UpdateAttempter_Init
  local rollback_slot=$(UpdateAttempter_GetRollbackSlot)
  if [ "${rollback_slot}" == "${kInvalidSlot}" ]; then echo ""; return 0; fi
  local part_num=$(BootControlChromeOS_GetPartitionNumber "${kChromeOSPartitionNameKernel}" $rollback_slot)
  # BootControlChromeOS::GetPartitionDevice
  echo "${boot_disk_name_}${part_num}"
}

function GetLastAttemptError {
  . "${SCRIPT_DIR}/update_attempter.sh"
  UpdateAttempter_Init
  echo $attempt_error_code_
}
# bool GetEolStatus(int32_t* out_eol_status);

function main {
  method="$1"
  case "$method" in
    "AttemptUpdate") # in_app_version, in_omaha_url
      AttemptUpdate  "$2" "$3"
      ;;
    "AttemptUpdateWithFlags") # in_app_version, in_omaha_url, in_flags
      AttemptUpdateWithFlags "$2" "$3" "$4"
      ;;
    "AttemptInstall")
      ;;
    "AttemptRollback")
      ;;
    "CanRollback")
      UpdateAttempter_CanRollback
      ;;
    "ResetStatus")
      ResetStatus
      ;;
    "GetStatus")
      GetStatus
      ;;
    "GetStatusAdvanced") # conversion to protobuff is done in update_engine.py
      GetStatusAdvanced
      ;;
    "RebootIfNeeded")
      RebootIfNeeded
      ;;
    "SetChannel") # in_target_channel, in_is_powerwash_allowed
      SetChannel "$2" "$3"
      ;;
    "GetChannel") # in_get_current_channel, out_channel
      GetChannel "$2"
      ;;
    "SetCohortHint")
      ;;
    "GetCohortHint")
      ;;
    "SetP2PUpdatePermission")
      ;;
    "GetP2PUpdatePermission")
      ;;
    "SetUpdateOverCellularPermission")
      ;;
    "SetUpdateOverCellularTarget")
      ;;
    "GetUpdateOverCellularPermission")
      ;;
    "GetDurationSinceUpdate")
      ;;
    "GetPrevVersion")
      GetPrevVersion
      ;;
    "GetRollbackPartition")
      GetRollbackPartition
      ;;
    "GetLastAttemptError")
      GetLastAttemptError
      ;;
    "GetEolStatus")
      ;;
    *)
      echo ""
      ;;
  esac
}


main "$@"
exit 0