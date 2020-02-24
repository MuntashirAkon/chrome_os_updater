#!/usr/bin/env python3
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# Idea taken from: https://github.com/freedesktop/dbus-python/tree/f8ffd3ab796ae622912b243c1e6f1d3e12c90ad7/examples
# Documentation: https://chromium.googlesource.com/aosp/platform/system/update_engine/+/master/dbus_service.h
#                https://chromium.googlesource.com/aosp/platform/system/update_engine/+/a1f4a7dcaa921fcb0ab395214a9558a62ca083f2/dbus_bindings/org.chromium.UpdateEngineInterface.dbus-xml
# Quick commands:
# Launch update_engine: sudo python3 ./update_engine.py
# Launch common_service daemon: sudo bash ./common_service.sh
# Monitor dbus: sudo dbus-monitor --system "interface='org.chromium.UpdateEngineInterface'"
# TODO: Use python-daemon to daemonize update_engine
# TODO: Run only a single instance of update_engine and common_service
# TODO: Replace bash with python (part of Roadmap)

# TODO: Add support for usage
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
import os
import time
import datetime

import commons as UE
from update_engine_pb2 import StatusResult

# Constants
UE_DIR = str(Path(__file__).parent.absolute().parent)
SH_SERVICE_PATH = UE_DIR + "/common_service.sh"
UE_OUT = '/tmp/update-engine-output'
UE_LOCK = '/tmp/update-engine-lock'
LOG_DIR = '/var/log'
UE_LOG_DIR = LOG_DIR + '/update_engine'
UE_MAIN_LOG = LOG_DIR + '/update_engine.log'
TIMEOUT = 10*20  # 10 sec
INTERVAL = 0.05  # 500 ms

def runService():
    while True: # do while
        ue_service = subprocess.Popen(['bash', SH_SERVICE_PATH], stdout=f_log_file, stderr=f_log_file)
        if ue_service.pid > 0: break

# Conversions
boolToString=['false', 'true']
stringToBool={'true': True, 'false': False}

def waitAndReadOutput():
    lock_file = "{}-{:.6f}".format(UE_LOCK, time.time())
    open(lock_file, 'w').close()
    print("Lock created")
    end_time = time.time() + TIMEOUT
    while time.time() <= end_time:
        if os.path.exists(UE_OUT):
            f = open(UE_OUT, 'r')
            line = f.readline()
            f.close()
            os.remove(UE_OUT)
            os.remove(lock_file)
            print(line)
            print("Lock removed")
            print(time.time())
            return line.strip()
        else:
            time.sleep(INTERVAL)
    if os.path.exists(UE_OUT): os.remove(UE_OUT)
    if os.path.exists(lock_file):
        os.remove(lock_file)
        print("Lock removed")
    print("TIMEOUT")
    return ""

#
# The update engine class
#
class UpdateEngine(dbus.service.Object):
    def __init__(self, conn, object_path=UE.PATH):
        dbus.service.Object.__init__(self, conn, object_path)
        self.bus = conn

    @dbus.service.method(UE.INTERFACE)
    def AttemptUpdate(self, in_app_version, in_omaha_url): # s, s
        return None
    
    @dbus.service.method(UE.INTERFACE)
    def AttemptUpdateWithFlags(self, in_app_version, in_omaha_url, in_flags): # s, s, i
        return None

    @dbus.service.method(UE.INTERFACE)
    def AttemptInstall(self, in_request): # ay
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def AttemptRollback(self, in_powerwash): # b
        pass
    
    @dbus.service.method(UE.INTERFACE)
    def CanRollback(self): # -> b
        return stringToBool[waitAndReadOutput()]
    
    @dbus.service.method(UE.INTERFACE)
    def ResetStatus(self):
        return None

    # deprecated
    @dbus.service.method(UE.INTERFACE)
    def GetStatus(self): # -> (x, d, s, s, x)
        outStr = waitAndReadOutput().split(" ")
        # (out_last_checked_time, out_progress, out_current_operation, out_new_version, out_new_size)
        return (dbus.Int64(outStr[0]), dbus.Double(outStr[1]), dbus.String(outStr[2]), dbus.String(outStr[3]), dbus.Int64(outStr[4]))

    @dbus.service.method(UE.INTERFACE)
    def GetStatusAdvanced(self): # -> ay
        outStr = waitAndReadOutput().split(" ")
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
        return None

    @dbus.service.method(UE.INTERFACE)
    def SetChannel(self, in_target_channel, in_is_powerwash_allowed): # s, b
        return None

    @dbus.service.method(UE.INTERFACE)
    def GetChannel(self, in_get_current_channel): # b -> s
        return waitAndReadOutput()

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
        return waitAndReadOutput()
    
    @dbus.service.method(UE.INTERFACE)
    def GetRollbackPartition(self): # -> s
        return waitAndReadOutput()
    
    @dbus.service.method(UE.INTERFACE)
    def GetLastAttemptError(self): # -> i
        return int(waitAndReadOutput())
    
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
        if os.path.exists(UE_OUT): os.remove(UE_OUT)
        # Create log
        dt = datetime.date.today()
        log_file = UE_LOG_DIR + '/update_engine.' + dt.strftime('%Y%m%d-%H%I%S')
        open(log_file, 'w').close()
        subprocess.Popen(['ln', '-sf', log_file, UE_MAIN_LOG])
        
        # Run service in the background
        f_log_file = open(UE_MAIN_LOG, 'a')
        runService()
        
        loop.run()
    except dbus.DBusException:
        traceback.print_exc()
