# Contains update status
# from https://chromium.googlesource.com/aosp/platform/system/update_engine/+/main/client_library/include/update_engine/update_status.h
# DO NOT add space after and before the `=` as this filter
# will be used in python and bash at the same time.
# Bash will use UpdateStatus prefix using awk

# enum UpdateStatus
IDLE=0
CHECKING_FOR_UPDATE=1
UPDATE_AVAILABLE=2
DOWNLOADING=3
VERIFYING=4
FINALIZING=5
UPDATED_NEED_REBOOT=6
REPORTING_ERROR_EVENT=7
ATTEMPTING_ROLLBACK=8
DISABLED=9
NEED_PERMISSION_TO_UPDATE=10

# enum UpdateAttemptFlags
kNone=0
kFlagNonInteractive=1 # (1<<0)
kFlagRestrictDownload=2 # (1<<2)

# enum UpdateEngineStatus aka. StatusResult
# It used to be here: /usr/include/chromeos/dbus/update_engine/update_engine.proto
# https://chromium.googlesource.com/chromiumos/platform2/+/master/system_api/dbus/update_engine/update_engine.proto
# Serial must be maintained
# Update engine last checked update (time_t: seconds from unix epoch).
last_checked_time=0  # 0
# Current status/operation of the update_engine.
status=0  # 1 (0=IDLE)
# Current product version (oem bundle id).
current_version=""  # 2
# Current progress (0.0f-1.0f).
progress=0.0  # 3
# Size of the update in bytes.
new_size_bytes=0  # 4
# New product version.
new_version=""  # 5
# Whether the update is an enterprise rollback.
is_enterprise_rollback=0  # 6 (boolean)
# Indication of install for DLC(s).
is_install=1  # 7 (boolean)
# The end-of-life date of the device in the number of days since Unix Epoch.
eol_date=0  # 8
