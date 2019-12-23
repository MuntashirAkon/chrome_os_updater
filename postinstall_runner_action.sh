#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# This file is converted from the original postinstall_runner_action.cc
# located at https://android.googlesource.com/platform/system/update_engine/+/refs/heads/master/payload_consumer/postinstall_runner_action.cc
# fetched at 23 December 2019
# NOTE: The conversion is a gradual process, it may take some time

. delta_performer.sh

#
# PostinstallRunnerAction::PerformPartitionPostinstall
#
function PostinstallRunnerAction_PerformPartitionPostinstall {
# TODO: Mount efi partition, download and apply swtpm if required
}

#
# PostinstallRunnerAction::PerformAction
#
function PostinstallRunnerAction_PerformAction {
    # This function is completely useless in our case
    PostinstallRunnerAction_PerformPartitionPostinstall
}

#
# PostinstallRunnerAction::Cleanup
#
function PostinstallRunnerAction_Cleanup {
# TODO: unmount efi and target partition, delete tpm, root.img, update file
}

#
# PostinstallRunnerAction::CompletePostinstall
#
function PostinstallRunnerAction_CompletePostinstall {
# TODO: Update grub, partition data
}

# Check environment variables
if [ "${0##*/}" == "postinstall_runner_action.sh" ]; then
    ( set -o posix ; set )
fi
