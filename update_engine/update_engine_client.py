#!/usr/bin/env python
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# For testing purpose only

import sys
import traceback
from gi.repository import GLib
import dbus
import dbus.mainloop.glib

import commons as UE


if __name__ == '__main__':
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    bus = dbus.SystemBus()
    try:
        obj = bus.get_object(UE.SERVICE, UE.PATH)
        inf = dbus.Interface(obj, UE.INTERFACE)
        # --show_channel
        # print "Current channel: ", inf.GetChannel(True)
        # print "Target channel:  ", inf.GetChannel(False)
        # --status
        # status = inf.GetStatusAdvanced()
        # print("Status:\n", status)
        # --check_for_update
        # inf.AttemptUpdateWithFlags("", "", 0)
        # --update
        inf.AttemptUpdateWithFlags("", "", 0)
        # inf.StatusUpdate()
        sys.exit(0)
    except dbus.DBusException:
        traceback.print_exc()
        sys.exit(1)

    loop = Glib.MainLoop()
    loop.run()
