pragma Singleton

import Quickshell
import QtQuick

Singleton {
    // Absolute paths: the greeter must not depend on PATH lookups.
    function powerOff() {
        Quickshell.execDetached(["/usr/bin/systemctl", "poweroff"]);
    }

    function reboot() {
        Quickshell.execDetached(["/usr/bin/systemctl", "reboot"]);
    }
}
