#!/bin/bash
# 2020 (c) Muntashir Al-Islam. All rights reserved.
# Source: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/a1f4a7dcaa921fcb0ab395214a9558a62ca083f2/update_attempter.cc
# Fetched 2 Jan 2020

# Dependencies: RealSystemState, CertificateChecker, BootControlInterface, UpdateManager

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Don't ever break the sequence!
. "${SCRIPT_DIR}/update_status.py"
. "${SCRIPT_DIR}/image_properties.sh"
. "${SCRIPT_DIR}/omaha_request_params.sh"
. "${SCRIPT_DIR}/power_manager.sh"
. "${SCRIPT_DIR}/boot_control_chromeos.sh"
. "${SCRIPT_DIR}/common/prefs.sh"
. "${SCRIPT_DIR}/common/constants.sh"
. "${SCRIPT_DIR}/common/platform_constants.sh"
. "${SCRIPT_DIR}/update_status_utils.sh"

kMaxDeltaUpdateFailures=3  # Not supported ( DisableDeltaUpdateIfNeeded() )
kMaxConsecutiveObeyProxyRequests=20
kBroadcastThresholdProgress=0.01
kBroadcastThresholdSeconds=10
kAUTestURLRequest="autest"
kScheduledAUTestURLRequest="autest-scheduled"


last_notify_time_=
direct_proxy_resolver_=
chrome_proxy_resolver_=
processor_=
cert_checker_=
service_observers_=
install_plan_=() # import from omaha_response_handler_action
error_event_=
fake_update_success_="false"
http_response_code_=0
attempt_error_code_=0
cpu_limiter_=

# For status:
status_=$IDLE
download_progress_=0.0
last_checked_time_=0
prev_version_=
new_version_="0.0.0.0"
new_payload_size_=0

update_attempt_flags_=$kNone
current_update_attempt_flags_=$kNone

proxy_manual_checks_=0
obeying_proxies_="true"

is_install_="false"

forced_app_version_=
forced_omaha_url_=

#
# UpdateAttempter::RebootDirectly
#
function UpdateAttempter_RebootDirectly {
  if "/sbin/shutdown" -r now; then echo "true"; else echo "false"; fi
}

#
# UpdateAttempter::RebootIfNeeded
#
function UpdateAttempter_RebootIfNeeded {
  if [ "$(PowerManagerChromeOS_RequestReboot)" == "true" ]; then echo "true"; return 0; fi
  UpdateAttempter_RebootDirectly
}

#
# UpdateAttempter::GetBootTimeAtUpdate
#
function UpdateAttempter_GetBootTimeAtUpdate {
  local current_boot_id="$(Prefs_GetKey $kPrefsBootId)"
  local update_completed_on_boot_id="$(Prefs_GetKey $kPrefsUpdateCompletedOnBootId)"
  if [ -z "$current_boot_id" ] || [ -z $update_completed_on_boot_id ] || ! [ "$current_boot_id" == "$update_completed_on_boot_id" ]; then
    echo "0"
    return 0
  fi
  echo "$(Prefs_GetKey $kPrefsUpdateCompletedBootTime)"
}

#
# UpdateAttempter::ResetStatus
#
function UpdateAttempter_ResetStatus {
  case $status_ in
    $IDLE)
      return 0
      ;;
    $UPDATED_NEED_REBOOT)
      status_=$IDLE
      Prefs_Delete $kPrefsUpdateCompletedOnBootId
      Prefs_Delete $kPrefsUpdateCompletedBootTime
      
      BootControlChromeOS_Init
      if BootControlChromeOS_SetActiveBootSlot $current_slot_; then
        return 1
      fi
      # PayloadState::ResetUpdateStatus
      Prefs_Delete $kPrefsTargetVersionInstalledFrom
      local target_attempt=$(Prefs_GetKey $kPrefsTargetVersionAttempt)
      Prefs_SetKey $kPrefsTargetVersionAttempt "$(( target_attempt-1 ))"
      Prefs_SetKey $kPrefsPreviousVersion ""
      return 0
      ;;
    *)
      >&2 echo "Reset not allowed in this state."
      return 1
      ;;
  esac
}

#
# UpdateAttempter::GetStatus
#
function UpdateAttempter_GetStatus {
  last_checked_time=${last_checked_time_:-0}
  status=${status_:-$IDLE}
  current_version="${ImageProperties['version']}"
  progress=${download_progress_:-0.0}
  new_size_bytes=${new_payload_size_:-0}
  new_version=${new_version_:-'0.0.0.0'}
  is_enterprise_rollback="${install_plan['is_rollback']}"
  is_enterprise_rollback="${is_enterprise_rollback:-false}"
  is_install=${is_install_:-'false'}
  eol_date=$(Prefs_GetKey $kPrefsOmahaEolDate)
  eol_date=${eol_date:-0}
  return 0
}

#
# UpdateAttempter::GetRollbackSlot
#
function UpdateAttempter_GetRollbackSlot {
  BootControlChromeOS_Init
  local num_slots=$num_slots_
  local current_slot=$current_slot_
  if [ "${current_slot}" ==  "${kInvalidSlot}" ] || [ $(( num_slots < 2 )) -eq 1 ]; then echo $kInvalidSlot; return 1; fi
  for (( slot=0 ; slot<num_slots ; ++slot )); do
    if [ $slot -ne $current_slot ] && [ "$(BootControlChromeOS_IsSlotBootable $slot)" == "true" ]; then
      echo $slot
      return 0
    fi
  done
  echo $kInvalidSlot
  return 1
}

#
# UpdateAttempter::CanRollback
#
function UpdateAttempter_CanRollback {
  if [ $status_ -eq $IDLE ] && [ $(UpdateAttempter_GetRollbackSlot) -ne $kInvalidSlot ]; then
    echo "true"
  else
    echo "false"
  fi
}

#
# UpdateAttempter::IsAnyUpdateSourceAllowed
#
function UpdateAttempter_IsAnyUpdateSourceAllowed {
  . "${SCRIPT_DIR}/hardware_chromeos.sh"
  if [ "$(IsOfficialBuild)" == "false" ]; then
    echo "true"
    return 0
  fi
  if [ "$(AreDevFeaturesEnabled)" == "true" ]; then
    echo "true"
    return 0
  fi
  echo "false"
  return 1
}


#
# UpdateAttempter::CalculateUpdateParams
#
function UpdateAttempter_CalculateUpdateParams {
  # TODO: RefreshDevicePolicy
  # TODO: UpdateRollbackHappened
  # TODO: target_version_prefix_=
  # TODO: rollback_allowed_=
  # TODO: rollback_data_save_requested_=
  # TODO: CalculateStagingParams
  # TODO: CalculateScatteringParams
  # TODO: rollback_allowed_milestones_=
  # NO P2P!!
  OmahaRequestParams_Init "$forced_app_version_" "$forced_omaha_url_" "$interactive"
  # TODO: Set target channel from policy

  # No support for DLC, so not going to CalculateDlcParams()
  # is_install_ is already set
  
  # TODO: add support for token
  
  # No support for proxy
  # Delta is disabled
  return 0
}

#
# UpdateAttempter::BuildUpdateActions
#
function UpdateAttempter_BuildUpdateActions {
  # TODO: processor_->IsRunning()
  # Check for update and apply if available
  . "$SCRIPT_DIR/omaha_request_action.sh"
  . "$SCRIPT_DIR/omaha_response_handler_action.sh"
  . "$SCRIPT_DIR/download_action.sh"
  . "$SCRIPT_DIR/delta_performer.sh"
  OmahaRequestAction_TransferComplete

  # Send signal: UPDATE_AVAILABLE?
  if [ ${ORA_update_exists} ]; then
    status_=${UPDATE_AVAILABLE}
    new_payload_size_=${ORA_size:-0}
    new_version_=${ORA_version:-'0.0.0.0'}
    UpdateAttempter_GetStatus
    BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
    echo $(UpdateStatusToString $status)
  else
    status_=${REPORTING_ERROR_EVENT}
    UpdateAttempter_GetStatus
    BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
    echo $(UpdateStatusToString $status)
    return 1
  fi
  
  if ! $is_install; then
    return 0
  fi

  OmahaResponseHandlerAction_PerformAction
  # TODO: Run checks

  # Send signal: DOWNLOADING
  status_=${DOWNLOADING}
  UpdateAttempter_GetStatus
  BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
  echo $(UpdateStatusToString $status)

  DownloadAction_PerformAction
  # TODO: Check if the update is downloaded properly

  # Send signal: VERIFYING
  status_=${VERIFYING}
  UpdateAttempter_GetStatus
  BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
  echo $(UpdateStatusToString $status)

  DownloadAction_TransferComplete
  # TODO: Check if the verification is completed properly

  # Send signal: FINALIZING
  status_=${FINALIZING}
  UpdateAttempter_GetStatus
  BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
  echo $(UpdateStatusToString $status)
  
  PostinstallRunnerAction_PerformAction

  if [ ${PostinstallRunnerAction_update_complete} ]; then
    status_=${UPDATED_NEED_REBOOT}
    UpdateAttempter_GetStatus
    BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
    echo $(UpdateStatusToString $status)
  else
    status_=${REPORTING_ERROR_EVENT}
    UpdateAttempter_GetStatus
    BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
    echo $(UpdateStatusToString $status)
    return 1
  fi
  return 0
}

#
# UpdateAttempter::Update
#
function UpdateAttempter_Update {
  if [ "${status_}" == "${UPDATED_NEED_REBOOT}" ]; then
    >&2 echo "Not updating b/c we already updated and we're waiting for reboot, we'll ping Omaha instead"
    # TODO: UpdateAttempter_PingOmaha
    return 1
  fi
  if ! [ "${status_}" == "${IDLE}" ]; then
    return 1
  fi

  # Send signal: CHECKING_FOR_UPDATE
  status_=${CHECKING_FOR_UPDATE}
  UpdateAttempter_GetStatus
  BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
  echo $(UpdateStatusToString $status)

  if ! UpdateAttempter_CalculateUpdateParams; then
    return 1
  fi
  
  UpdateAttempter_BuildUpdateActions
  
  # Send signal: UPDATED_NEED_REBOOT
  status_=${UPDATED_NEED_REBOOT}
  UpdateAttempter_GetStatus
  BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
  echo $(UpdateStatusToString $status)
}


#
# UpdateAttempter::OnUpdateScheduled
#
function UpdateAttempter_OnUpdateScheduled {
  # TODO: UpdateManager/policy
  # For now, just call Update
  UpdateAttempter_Update
}

#
# UpdateAttempter::CheckForUpdate
# Args: APP_VERSION OMAHA_URL FLAGS
function UpdateAttempter_CheckForUpdate {
  local app_version="$1"
  local omaha_url="$2"
  local flags="$3"
  
  # Send signal: default status
  #UpdateAttempter_GetStatus
  #BroadcastStatus "$last_checked_time" "$progress" "$status" "$new_version" "$new_size_bytes" "$is_enterprise_rollback" "$is_install" "$eol_date"
    
  if ! [ "${status_}" == "${IDLE}" ]; then
    >&2 echo "Refusing to do an update as there already an update/install in progress"
    return 1
  fi
  
  local interactive=$(( ! ( flags & kFlagNonInteractive ) ))
  is_install_="false"

  forced_app_version_=
  forced_omaha_url_=

  if [ "$(UpdateAttempter_IsAnyUpdateSourceAllowed)" == "true" ]; then
    forced_app_version_=$app_version
    forced_omaha_url_=$omaha_url
  fi
  
  if [ "${omaha_url}" == "${kScheduledAUTestURLRequest}" ]; then
    forced_omaha_url_=${kOmahaDefaultAUTestURL}
    interactive=0
  elif [ "${omaha_url}" == "${kAUTestURLRequest}" ]; then
    forced_omaha_url_=${kOmahaDefaultAUTestURL}
  fi
  
  if [ $interactive -eq 1 ]; then
    current_update_attempt_flags_="$flags"
  fi

  # No need for forced_update_pending_callback_ or UpdateAttempter::ScheduleUpdates() or UpdateManager
  # since we're checking for update immediately
  UpdateAttempter_OnUpdateScheduled
}

#
# UpdateAttempter::Init
#
function UpdateAttempter_Init {
  Prefs_Init
  OmahaRequestParams_Init
  # TODO: cert_checker_
  if ! [ "$(UpdateAttempter_GetBootTimeAtUpdate)" == "0" ]; then
    status_=$UPDATED_NEED_REBOOT
  else
    status_=$IDLE
  fi
  is_install_="false"
  # UpdateAttempter::UpdateEngineStarted
  # TODO:
}