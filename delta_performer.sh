#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# This file is converted from the original delta_performer.cc
# located at https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master/payload_consumer/delta_performer.cc
# fetched at 23 December 2019
# NOTE: The conversion is a gradual process, it may take some time

. download_action.sh

#
# DeltaPerformer::Write
#
function DeltaPerformer_Write {
    # TODO: Convert and copy update files
    # Copy contents of root.img to the target partition
    # Also copy required files from current to target partition
}

#
# DeltaPerformer::PreparePartitionsForUpdate
#
function DeltaPerformer_PreparePartitionsForUpdate {
    # TODO: Convert to root.img using paycheck.py, mount root.img & target partition
}

#
# DeltaPerformer::Close
#
function DeltaPerformer_Close {
    # TODO: unmount root.img
}

# Check environment variables
if [ "${0##*/}" == "delta_performer.sh" ]; then
    ( set -o posix ; set )
fi
