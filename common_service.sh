#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# Taken from https://chromium.googlesource.com/aosp/platform/system/update_engine/+/a1f4a7dcaa921fcb0ab395214a9558a62ca083f2/common_service.h
# Combined with https://chromium.googlesource.com/aosp/platform/system/update_engine/+/a1f4a7dcaa921fcb0ab395214a9558a62ca083f2/dbus_service.cc
#
# Dependency: system_state.h (device_policy, ConnectionManagerInterface, ClockInterface)

# update_engine.py calls this to get information
# DO NOT call it yourself as it may be unstable

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "${SCRIPT_DIR}/update_attempter.sh"

UE_OUT='/tmp/update-engine-output'
UE_LOCK='/tmp/update-engine-lock'

# Most of these are initialized in real_system_state.cc
BootControlChromeOS_Init
UpdateAttempter_Init  # Prefs_Init, OmahaRequestParams_Init


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
  UpdateAttempter_CheckForUpdate "$in_app_version" "$in_omaha_url" "$flags"
}

# bool AttemptInstall(const std::string& omaha_url, const std::vector<std::string>& dlc_module_ids);
# bool AttemptRollback(bool in_powerwash);

function CanRollback { # out_can_rollback
  UpdateAttempter_CanRollback
}

function ResetStatus {
  UpdateAttempter_ResetStatus
  return 0
}

function GetStatus { # Serials: out_last_checked_time, out_progress, out_current_operation, out_new_version, out_new_size
  . "${SCRIPT_DIR}/update_status_utils.sh"
  UpdateAttempter_GetStatus
  echo "${last_checked_time:-0} ${progress:-0.0} $(UpdateStatusToString "${status:-0}") ${new_version:-0.0.0.0} ${new_size_bytes:-0}"
}

function GetStatusAdvanced {
  UpdateAttempter_GetStatus
  echo "${last_checked_time:-0} ${progress:-0.0} ${status:-0} ${new_version:-0.0.0.0} ${new_size_bytes:-0} ${is_enterprise_rollback:-false} ${is_install:-false} ${eol_date:-0}"
}

function RebootIfNeeded {
  if [ "$(UpdateAttempter_RebootDirectly)" == "true" ]; then return 0; else return 1; fi
}

function SetChannel {
  local in_target_channel="$1"
  local in_is_powerwash_allowed="$2"
  
  # TODO: Implement device policy
  if [ "$(OmahaRequestParams_SetTargetChannel "${in_target_channel}" "${in_is_powerwash_allowed}")" == "false" ]; then
    return 1
  else
    return 0
  fi
}

function GetChannel {
  local in_get_current_channel="$1"
  
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
  echo "${prev_version_}"
}

function GetRollbackPartition {
  local rollback_slot=$(UpdateAttempter_GetRollbackSlot)
  if [ "${rollback_slot}" == "${kInvalidSlot}" ]; then echo ""; return 0; fi
  local part_num=$(BootControlChromeOS_GetPartitionNumber "${kChromeOSPartitionNameKernel}" $rollback_slot)
  # BootControlChromeOS::GetPartitionDevice
  echo "${boot_disk_name_}${part_num}"
}

function GetLastAttemptError {
  echo $attempt_error_code_
}
# bool GetEolStatus(int32_t* out_eol_status);

# Returns: ARG_COUNT NEED_LOCK
function count_arg {
  method="$1"
  case "$method" in
    "AttemptUpdate") # in_app_version, in_omaha_url
      echo 2 false
      ;;
    "AttemptUpdateWithFlags") # in_app_version, in_omaha_url, in_flags
      echo 3 false
      ;;
    "AttemptInstall")
      echo 1 false
      ;;
    "AttemptRollback")
      echo 1 false
      ;;
    "CanRollback")
      echo 0 true
      ;;
    "ResetStatus")
      echo 0 false
      ;;
    "GetStatus")
      echo 0 true
      ;;
    "GetStatusAdvanced") # conversion to protobuff is done in update_engine.py
      echo 0 true
      ;;
    "RebootIfNeeded")
      echo 0 false
      ;;
    "SetChannel") # in_target_channel, in_is_powerwash_allowed
      echo 2 false
      ;;
    "GetChannel") # in_get_current_channel, out_channel
      echo 1 true
      ;;
    "SetCohortHint")
      echo 1 false
      ;;
    "GetCohortHint")
      echo 0 true
      ;;
    "SetP2PUpdatePermission")
      echo 1 false
      ;;
    "GetP2PUpdatePermission")
      echo 0 true
      ;;
    "SetUpdateOverCellularPermission")
      echo 1 false
      ;;
    "SetUpdateOverCellularTarget")
      echo 2 false
      ;;
    "GetUpdateOverCellularPermission")
      echo 0 true
      ;;
    "GetDurationSinceUpdate")
      echo 0 true
      ;;
    "GetPrevVersion")
      echo 0 true
      ;;
    "GetRollbackPartition")
      echo 0 true
      ;;
    "GetLastAttemptError")
      echo 0 true
      ;;
    "GetEolStatus")
      echo 0 true
      ;;
    *)
      echo 0 false
      ;;
  esac
}

function invoke_method {
  if [ -n "$member" ]; then
    echo $member: $(date +%s)
    first_lock="$(ls -t $UE_LOCK* 2>/dev/null | head -1)"
    has_output="$(count_arg $member | awk '{print $2}')"
    if $has_output; then
      $member "${args[@]}" > $UE_OUT
    else
      $member "${args[@]}"
    fi
    echo "$member ${args[@]}"
    # Need lock and has lock file
    if $has_output && [ -n "$first_lock" ]; then
      # Don't execute another method until first lock goes away
      while [ -e $first_lock ]; do sleep 0.05; done
    fi
  fi
  # Reset vars
  member=
  args=()
  sender=
}

member=
args=()
sender=

function main {
  while [ -e $UE_LOCK ]; do touch $UE_OUT; sleep 0.5; done
  
  dbus-monitor --system --monitor "type='method_call',interface='org.chromium.UpdateEngineInterface'" | \
  while read -r line; do
    if [ "$(echo $line | awk '{print $1}')" == "method" ]; then
      invoke_method
      member="$(echo $line | grep -o "member=[A-Za-z]\+" | awk -F'=' '{print $2}')"
      sender="$(echo $line | grep -o "sender=[:0-9A-Za-z]\+" | awk -F'=' '{print $2}')"
      if [ "$(count_arg $member | awk '{print $1}')" == "${#args[@]}" ]; then invoke_method; fi
    elif [ "$(echo $line | awk '{print $1}')" == "signal" ]; then
      invoke_method
    else  # probably an argument (array|dict not supported)
      arg="$(echo $line | awk '{print $2}' )"
      if [ "$arg" == "\"\"" ]; then args+=( '' ); else args+=( $arg ); fi
      if [ "$(count_arg $member | awk '{print $1}')" == "${#args[@]}" ]; then invoke_method; fi
    fi
  done
}

main "$@"
exit 0