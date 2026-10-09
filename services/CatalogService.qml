pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property var users: fallbackUsers()
    property var discoveredSessions: []
    property string discoveryError: ""
    readonly property var sessions: mergeSessions(Config.sessions, discoveredSessions)

    // Discovery runs in a separate Python file (services/catalog.py) so it can
    // be tested outside Quickshell. The shell root is the directory that
    // contains shell.qml, both in preview mode and when installed.
    readonly property string discoveryScript: Quickshell.shellPath("services/catalog.py")

    function fallbackUsers() {
        if (!Config.defaultUser)
            return [];
        return [{
            "username": Config.defaultUser,
            "displayName": Config.displayName || Config.defaultUser,
            "avatar": Config.avatarSource
        }];
    }

    function sourceUrl(path) {
        if (!path || path.startsWith("file:") || path.startsWith("qrc:"))
            return path || "";
        return path.startsWith("/") ? `file://${path}` : path;
    }

    function normaliseUsers(items) {
        if (!Array.isArray(items))
            return fallbackUsers();
        return items.filter(item => item && item.username).map(item => {
            const username = String(item.username);
            const discoveredAvatar = sourceUrl(String(item.avatar || ""));
            const avatar = username === Config.defaultUser && Config.avatarSource
                ? Config.avatarSource
                : discoveredAvatar;
            return {
                "username": username,
                "displayName": String(item.displayName || username),
                "avatar": avatar
            };
        });
    }

    function isHiddenSession(item) {
        const hidden = Config.hiddenSessions;
        if (!hidden.length)
            return false;
        const desktopFile = String(item.desktopFile || "");
        const baseName = desktopFile.substring(desktopFile.lastIndexOf("/") + 1);
        return hidden.includes(baseName) || hidden.includes(String(item.name || ""));
    }

    function normaliseSessions(items) {
        if (!Array.isArray(items))
            return [];
        return items.filter(item => item && item.name && Array.isArray(item.command) && item.command.length > 0 && !isHiddenSession(item)).map(item => ({
            "name": String(item.name),
            "command": item.command.map(part => String(part)),
            "type": "wayland",
            "desktopFile": String(item.desktopFile || "")
        }));
    }

    function mergeSessions(configured, discovered) {
        const result = [];
        const seen = {};
        const append = item => {
            if (!item || !item.name || !Array.isArray(item.command) || item.command.length === 0)
                return;
            const command = item.command.map(part => String(part));
            const key = JSON.stringify(command);
            if (seen[key])
                return;
            seen[key] = true;
            result.push({
                "name": String(item.name),
                "command": command,
                "type": "wayland",
                "desktopFile": String(item.desktopFile || "")
            });
        };

        if (Array.isArray(configured))
            configured.forEach(append);
        if (Array.isArray(discovered))
            discovered.forEach(append);
        return result;
    }

    function applyDiscovery(text) {
        try {
            const parsed = JSON.parse(text);
            const discoveredUsers = normaliseUsers(parsed.users);
            root.users = discoveredUsers.length > 0 ? discoveredUsers : fallbackUsers();
            root.discoveredSessions = normaliseSessions(parsed.sessions);
            root.discoveryError = "";
        } catch (error) {
            root.users = fallbackUsers();
            root.discoveredSessions = [];
            root.discoveryError = String(error);
            console.warn("Caelestia Greeter: failed to discover users and sessions:", error);
        }
    }

    Process {
        id: discoveryProcess

        running: true
        command: ["/usr/bin/python3", root.discoveryScript]
        stdout: StdioCollector {
            onStreamFinished: root.applyDiscovery(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message)
                    console.warn("Caelestia Greeter: catalogue discovery warning:", message);
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.users = root.fallbackUsers();
                root.discoveredSessions = [];
                root.discoveryError = `Discovery exited with status ${exitCode}`;
            }
        }
    }
}
