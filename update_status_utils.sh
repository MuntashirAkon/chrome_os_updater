#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# Taken from https://chromium.googlesource.com/aosp/platform/system/update_engine/+/master/update_status_utils.cc

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "${SCRIPT_DIR}/service_constants.sh"

#
# Args: UPDATE_STATUS
#
function UpdateStatusToString {
  . "${SCRIPT_DIR}/update_status.py"
  status="$1"
  case $status in
    $IDLE)
      echo $kUpdateStatusIdle
      ;;
    $CHECKING_FOR_UPDATE)
      echo $kUpdateStatusCheckingForUpdate
      ;;
    $UPDATE_AVAILABLE)
      echo $kUpdateStatusUpdateAvailable
      ;;
    $NEED_PERMISSION_TO_UPDATE)
      echo $kUpdateStatusNeedPermissionToUpdate
      ;;
    $DOWNLOADING)
      echo $kUpdateStatusDownloading
      ;;
    $VERIFYING)
      echo $kUpdateStatusVerifying
      ;;
    $FINALIZING)
      echo $kUpdateStatusFinalizing
      ;;
    $UPDATED_NEED_REBOOT)
      echo $kUpdateStatusUpdatedNeedReboot
      ;;
    $REPORTING_ERROR_EVENT)
      echo $kUpdateStatusReportingErrorEvent
      ;;
    $ATTEMPTING_ROLLBACK)
      echo $kUpdateStatusAttemptingRollback
      ;;
    $DISABLED)
      echo $kUpdateStatusDisabled
      ;;
    *)
      echo ""
      ;;
  esac
}


#
# Args: last_checked_time, progress, current_operation, new_version, new_size, is_enterprise_rollback, is_install, eol_date
#
function BroadcastStatus {
  last_checked_time=$1
  progress=$2
  current_operation=$3
  new_version=$4
  new_size=$5
  dbus-send --system --type=signal /org/chromium/UpdateEngine org.chromium.UpdateEngineInterface.StatusUpdateAdvanced int64:$last_checked_time double:$progress string:"$(UpdateStatusToString $current_operation)" string:"${new_version}" int64:$new_size
  pb_arr="$(python3 "${SCRIPT_DIR}/update_engine/status_result_to_pb_array.py" "$@")"
  dbus-send --system --type=signal /org/chromium/UpdateEngine org.chromium.UpdateEngineInterface.StatusUpdate array:byte:"${pb_arr}"
}
