#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# NOTE: TPM 1.2 fix is adapted from the Chromefy project and
# this copyright doesn't apply them.

# Get script directory 
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

#
# Echo to stderr
#
function echo_stderr {
  >&2 echo "$@"
}

# Print Usage
function print_usage {
  echo_stderr "Usage: ${0##*/} [--check-only|--help]"
  echo_stderr "Run ${0##*/} without any argument to update Chrome OS"
  echo_stderr "--check-only  Only check for update."
  echo_stderr "--help        This help page."
}

function main {
    if [ "$1" == "--check-only" ]; then
      . "$SCRIPT_DIR/omaha_request_action.sh"
      OmahaRequestAction_TransferComplete
      if [ ${ORA_update_exists} ]; then
        echo_stderr "A new update is available!"
        echo_stderr "Version: ${ORA_version}"
        echo_stderr "Download URL: ${ORA_payload_urls[1]}"
        exit 0
      fi
    elif [ "$1" == "--help" ]; then
      print_usage
      exit 0
    fi
    if [ $UID -ne 0 ]; then
      echo_stderr "Only root can do that."
      exit 1
    fi

    . "$SCRIPT_DIR/postinstall_runner_action.sh"
    PostinstallRunnerAction_PerformAction
    exit 0
}

main "$@"
exit 0
