#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# This file is converted from the original download_action.cc
# located at https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master/payload_consumer/download_action.cc
# fetched at 30 Jun 2019
# NOTE: The conversion is a gradual process, it may take some time

. omaha_response_handler_action.sh


#
# DownloadAction::TransferComplete
#
function DownloadAction_TransferComplete {
    # NOTE: Originally (and confusingly) both HTTP and HTTPS payloads are downloaded.
    #       However, we don't actually need to download both of them.
    # TODO: Verify payload using paycheck.py
    # paycheck -t payload_type payload_file
    return 0
}


#
# DownloadAction::StartDownloading
#
function DownloadAction_StartDownloading {
    local file_size=`bc -l <<< "scale=2; ${ORA_size}/1073741824"`
    echo_stderr "Update available."
    echo_stderr "Downloading ${ORA_package_name} (${file_size} GB)..."
    local user='chronos/user'
    local root="/home/${user}"
    local file_loc="${root}/${ORA_package_name}"
    curl -\#L -o "${file_loc}" "${install_plan['download_url']}" -C -
    # TODO: match checksum
    if [ $? -ne 0 ]; then
        echo_stderr "Failed to download ${ORA_package_name}. Try again."
        exit 1
    fi
    echo "${file_loc}"  # Where did it go in the original file?
    DownloadAction_TransferComplete
}


#
# DownloadAction::PerformAction
#
function DownloadAction_PerformAction {
    OmahaResponseHandlerAction_PerformAction
    # TODO: MarkSlotUnbootable
    if [ $1 -eq 1 ]; then exit 1; fi
    DownloadAction_StartDownloading
}

# Check environment variables
if [ "${0##*/}" == "download_action.sh" ]; then
    DownloadAction_PerformAction 1
    ( set -o posix ; set )
fi
