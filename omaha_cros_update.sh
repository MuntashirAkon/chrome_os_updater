#!/bin/bash
# 2019-2020 (c) Muntashir Al-Islam. All rights reserved.

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
  echo_stderr "Usage: ${0##*/} [-chv]"
  echo_stderr "Run ${0##*/} without any argument to update Chrome OS"
  echo_stderr " -c, --check-only  Only check for update."
  echo_stderr " -h, --help        This help page."
  echo_stderr " -v, --version     Print version information"
}

function main {
    case "$1" in
      '--check-only'|'-c')
        if [ $UID -ne 0 ]; then
          echo_stderr "Only root can do that."
          exit 1
        fi
        . "${SCRIPT_DIR}/image_properties.sh"
        . "$SCRIPT_DIR/omaha_request_params.sh"
        . "$SCRIPT_DIR/omaha_request_action.sh"
        OmahaRequestParams_Init
        OmahaRequestAction_TransferComplete
        if [ ${ORA_update_exists} ]; then
          echo_stderr "A new update is available!"
          echo_stderr "Version: ${ORA_version}"
          echo_stderr "Download URL: ${ORA_payload_urls[1]}"
          exit 0
        fi
        ;;
      '--help'|'-h')
        print_usage
        exit 0
        ;;
      '--version'|'-v')
        . "$SCRIPT_DIR/version.sh"
        echo_stderr "Version: ${OCU_VERSION}.${OCU_PATCH}"
        exit 0
        ;;
      '')
        if [ $UID -ne 0 ]; then
          echo_stderr "Only root can do that."
          exit 1
        fi
        . "${SCRIPT_DIR}/image_properties.sh"
        . "$SCRIPT_DIR/omaha_request_params.sh"
        . "$SCRIPT_DIR/postinstall_runner_action.sh"
        OmahaRequestParams_Init
        OmahaRequestAction_TransferComplete
        OmahaResponseHandlerAction_PerformAction
        DownloadAction_PerformAction
        DownloadAction_TransferComplete
        PostinstallRunnerAction_PerformAction
        exit 0
        ;;
      *)
        echo_stderr "Illegal option $@."
        print_usage
        exit 1
    esac
}

main "$@"
exit 0
