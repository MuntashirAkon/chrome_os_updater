#!/usr/bin/env python
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# Idea taken from: https://github.com/freedesktop/dbus-python/tree/f8ffd3ab796ae622912b243c1e6f1d3e12c90ad7/examples
# Documentation: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/master/dbus_service.h
#                https://chromium.googlesource.com/aosp/platform/system/update_engine/+/a1f4a7dcaa921fcb0ab395214a9558a62ca083f2/dbus_bindings/org.chromium.UpdateEngineInterface.dbus-xml
# Quick commands:
# Launch update_engine: sudo python ./update_engine.py
# Monitor dbus: sudo dbus-monitor --system "interface='org.chromium.UpdateEngineInterface'"
# ChromeOS update checks: (found so far)
# - AttemptUpdateWithFlags("", "", 0)
# - Signal: StatusUpdate(0, 0, "UPDATE_STATUS_DISABLED", "0.0.0.0", 0)
# - Singal: StatusUpdateAdvanced([18 09 22 07 30 2e 30 2e 30 2e 30 40 f1 b1 ff ff ff ff ff ff ff 01])
# - Signal: StatusUpdate(0, 0, "UPDATE_STATUS_DISABLED", "0.0.0.0", 0)
# - Signal: StatusUpdateAdvanced([22 07 30 2e 30 2e 30 2e 30 40 f1 b1 ff ff ff ff ff ff ff 01])
usage = """A/B Update Engine

  --foreground  (Don't daemon()ize; run in foreground.)  type: bool  default: false
  --help  (Show this help message)  type: bool  default: false
  --logtofile  (Write logs to a file in log_dir.)  type: bool  default: false
  --logtostderr  (Write logs to stderr instead of to a file in log_dir.)  type: bool  default: false

"""

import traceback
from gi.repository import GLib
import dbus
import dbus.service
import dbus.mainloop.glib
import subprocess
import sys
import google.protobuf
from pathlib import Path

import commons as UE
from update_engine_pb2 import StatusResult

# Constants
UE_DIR = str(Path(__file__).parent.absolute().parent)
SH_SERVICE_PATH = UE_DIR + "/common_service.sh"

# Conversions
boolToString=['false', 'true']

stringToBool={'true': True, 'false': False}

#
# Fetch values from bash script
#
def BashToPython(arguments_as_array, function=None):
    if function is None:
        function = sys._getframe().f_back.f_code.co_name
    command = ["bash", SH_SERVICE_PATH, function] + arguments_as_array
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    return process.stdout.read().strip().decode('utf-8')

#
# The update engine class
#
class UpdateEngine(dbus.service.Object):
    def __init__(self, conn, object_path=UE.PATH):
        dbus.service.Object.__init__(self, conn, object_path)

    @dbus.service.method(UE.INTERFACE)
    def AttemptUpdate(self, in_app_version, in_omaha_url): # s, s
        BashToPython([ in_app_version, in_omaha_url ])
        return None
    
    @dbus.service.method(UE.INTERFACE)
    def AttemptUpdateWithFlags(self, in_app_version, in_omaha_url, in_flags): # s, s, i
        BashToPython([ in_app_version, in_omaha_url, str(in_flags) ])
        return None

    @dbus.service.method(UE.INTERFACE)
    def AttemptInstall(self, in_request): # ay
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def AttemptRollback(self, in_powerwash): # b
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def CanRollback(self): # -> b
        return stringToBool[BashToPython([])]
    
    @dbus.service.method(UE.INTERFACE)
    def ResetStatus(self):
        BashToPython([])
        return None

    # deprecated
    @dbus.service.method(UE.INTERFACE)
    def GetStatus(self): # -> (x, d, s, s, x)
        outStr = BashToPython([]).split(" ")
        # (out_last_checked_time, out_progress, out_current_operation, out_new_version, out_new_size)
        return (dbus.Int64(outStr[0]), dbus.Double(outStr[1]), dbus.String(outStr[2]), dbus.String(outStr[3]), dbus.Int64(outStr[4]))

    @dbus.service.method(UE.INTERFACE)
    def GetStatusAdvanced(self): # -> ay
        outStr = BashToPython([]).split(" ")
        # (last_checked_time, progress, current_operation, new_version, new_size, is_enterprise_rollback, is_install, eol_date)
        res = StatusResult()
        res.last_checked_time = int(outStr[0])
        res.progress = float(outStr[1])
        res.current_operation = int(outStr[2])
        res.new_version = outStr[3]
        res.new_size = int(outStr[4])
        res.is_enterprise_rollback = stringToBool[outStr[5]]
        res.is_install = stringToBool[outStr[6]]
        res.eol_date = int(outStr[7])
        return dbus.ByteArray(res.SerializeToString())

    @dbus.service.method(UE.INTERFACE)
    def RebootIfNeeded(self):
        BashToPython([])
        return None

    @dbus.service.method(UE.INTERFACE)
    def SetChannel(self, in_target_channel, in_is_powerwash_allowed): # s, b
        BashToPython([ in_target_channel, boolToString[in_is_powerwash_allowed] ])
        return None

    @dbus.service.method(UE.INTERFACE)
    def GetChannel(self, in_get_current_channel): # b -> s
        return BashToPython([ boolToString[in_get_current_channel] ])

    @dbus.service.method(UE.INTERFACE)
    def SetCohortHint(self, in_cohort_hint): # s
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def GetCohortHint(self, out_cohort_hint): # -> s
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def SetP2PUpdatePermission(self, in_enabled): # b
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def GetP2PUpdatePermission(self, out_enabled): # -> b
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def SetUpdateOverCellularPermission(self, in_allowed): # b
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def SetUpdateOverCellularTarget(self, in_target_version, in_target_size): # s, x
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def GetUpdateOverCellularPermission(self, out_allowed): # -> b
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def GetDurationSinceUpdate(self, out_usec_wallclock): # -> x
        pass
    
    # deprecated
    @dbus.service.signal(UE.INTERFACE)
    def StatusUpdate(self, out_last_checked_time, out_progress, out_current_operation, out_new_version, out_new_size): # x, d, s, s, x
        pass
    
    @dbus.service.signal(UE.INTERFACE)
    def StatusUpdateAdvanced(self, out_status): # ay
        pass

    @dbus.service.method(UE.INTERFACE)
    def GetPrevVersion(self): # -> s
        return BashToPython([])
    
    @dbus.service.method(UE.INTERFACE)
    def GetRollbackPartition(self): # -> s
        return BashToPython([])
    
    @dbus.service.method(UE.INTERFACE)
    def GetLastAttemptError(self): # -> i
        return int(BashToPython([]))
    
    @dbus.service.method(UE.INTERFACE)
    def GetEolStatus(self, out_eol_status): # -> i
        pass


if __name__ == '__main__':
    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    
        bus = dbus.SystemBus()
        name = dbus.service.BusName(UE.SERVICE, bus)
        object = UpdateEngine(bus)
    
        loop = GLib.MainLoop()
        print("A/B Update Engine")
        # print usage
        loop.run()
    except dbus.DBusException:
        traceback.print_exc()
