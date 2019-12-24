#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# This file is converted from the original download_action.cc
# located at https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master/payload_consumer/download_action.cc
# fetched at 30 Jun 2019
# NOTE: The conversion is a gradual process, it may take some time

# Get script directory 
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

. "$SCRIPT_DIR/omaha_response_handler_action.sh"

#
# DownloadAction::TransferComplete
#
function DownloadAction_TransferComplete {
    # NOTE: Originally (and confusingly) both HTTP and HTTPS payloads are downloaded.
    #       However, we don't actually need to download both of them.
    # Verify payload using paycheck.py
    python "$SCRIPT_DIR/scripts/paycheck.py" -c "${install_plan['update_file_path']}"
    if [ $? -ne 0 ]; then
      echo_stderr "Download of ${install_plan['download_url']} failed due to payload verification error."
      rm "${install_plan['update_file_path']}"
      exit 1
    fi
}


#
# DownloadAction::StartDownloading
#
function DownloadAction_StartDownloading {
    # Create root if not exists
    if ! [ -d "${install_plan['download_root']}" ]; then
      mkdir "${install_plan['download_root']}" 2> /dev/null
      if ! [ $? -eq 0 ]; then
        echo_stderr "Could not create download directory. Update aborted."
        exit 1
      fi
    fi
    # Set download root as the pwd
    cd "${install_plan['download_root']}"
    # Download update
    local file_size=`bc -l <<< "scale=2; ${ORA_size}/1073741824"`
    echo_stderr "Update available."
    echo_stderr "Downloading ${ORA_package_name} (${file_size} GB)..."
    install_plan['update_file_path']="${install_plan['download_root']}/${ORA_package_name}"
    curl -\#L -o "${install_plan['update_file_path']}" "${install_plan['download_url']}" -C -
    if [ $? -ne 0 ]; then
      echo_stderr "Failed to download ${ORA_package_name}. Try again."
      exit 1
    fi
    # TODO: match checksum
    DownloadAction_TransferComplete
}


#
# DownloadAction::PerformAction
#
function DownloadAction_PerformAction {
    OmahaResponseHandlerAction_PerformAction
    # TODO: MarkSlotUnbootable
    if [[ "$1" == "1" ]]; then exit 1; fi
    DownloadAction_StartDownloading
}

# Check environment variables
if [ "${0##*/}" == "download_action.sh" ]; then
    DownloadAction_PerformAction 1
    ( set -o posix ; set )
fi
