pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import QtQuick
import "../design"
import "../i18n"

Singleton {
    id: root

    property string prompt: I18n.t("login.password")
    property string errorMessage: ""
    property string statusMessage: ""
    property string pendingResponse: ""
    property var launchCommand: []
    property bool busy: false
    property bool awaitingResponse: false
    property bool echoResponse: false
    property bool markerPending: false
    property bool launching: false

    // Provided by caelestia-greeter-run as a path inside a private mktemp
    // directory. Without it (preview mode) the marker is not needed.
    readonly property string launchMarkerPath: Quickshell.env("CAELESTIA_GREETER_LAUNCH_MARKER") || ""
    readonly property bool previewMode: {
        const value = Quickshell.env("CAELESTIA_GREETER_PREVIEW") || "";
        return value === "1" || value.toLowerCase() === "true" || !Greetd.available;
    }

    function authenticate(user, response, command) {
        const username = user.trim();
        if (!username) {
            root.errorMessage = I18n.t("auth.usernameRequired");
            return;
        }
        if (!command || command.length === 0) {
            root.errorMessage = I18n.t("auth.invalidSession");
            return;
        }

        root.pendingResponse = response;
        root.launchCommand = command;
        root.errorMessage = "";
        root.statusMessage = I18n.t("auth.authenticating");
        root.awaitingResponse = false;
        root.busy = true;

        if (root.previewMode) {
            previewTimer.restart();
            return;
        }

        Greetd.createSession(username);
    }

    function provideResponse(response) {
        if (!root.awaitingResponse || root.previewMode)
            return;

        root.errorMessage = "";
        root.statusMessage = I18n.t("auth.authenticating");
        root.awaitingResponse = false;
        root.busy = true;
        Greetd.respond(response);
    }

    function cancel() {
        root.pendingResponse = "";
        root.launchCommand = [];
        root.busy = false;
        root.awaitingResponse = false;
        root.markerPending = false;
        root.launching = false;
        root.statusMessage = "";
        root.errorMessage = "";
        launchDelay.stop();

        if (launchMarkerProcess.running)
            launchMarkerProcess.running = false;
        if (!root.previewMode && Greetd.user)
            Greetd.cancelSession();
    }

    // greetd joins the command list with spaces and runs it through
    // `/bin/sh -c "exec ..."`, so each argument is quoted here to keep the
    // argv boundaries the session catalogue produced (paths with spaces,
    // desktop-entry arguments with shell metacharacters).
    function shellQuote(argument) {
        const value = String(argument);
        if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(value))
            return value;
        return `'${value.replace(/'/g, `'\\''`)}'`;
    }

    function launchArguments() {
        return root.launchCommand.map(part => root.shellQuote(part));
    }

    function requestSessionLaunch() {
        if (!root.launchCommand.length) {
            root.busy = false;
            root.launching = false;
            root.errorMessage = I18n.t("auth.missingCommand");
            return;
        }

        if (!root.launchMarkerPath) {
            Greetd.launch(root.launchArguments(), [], true);
            return;
        }

        root.markerPending = true;
        launchMarkerProcess.exec(["/usr/bin/touch", root.launchMarkerPath]);
    }

    Process {
        id: launchMarkerProcess

        onExited: exitCode => {
            if (!root.markerPending)
                return;

            root.markerPending = false;
            if (exitCode !== 0) {
                root.busy = false;
                root.launching = false;
                root.statusMessage = "";
                root.errorMessage = I18n.t("auth.handoffFailed");
                return;
            }

            Greetd.launch(root.launchArguments(), [], true);
        }
    }

    Timer {
        id: launchDelay

        interval: Motion.duration(Motion.defaultSpatial)
        onTriggered: root.requestSessionLaunch()
    }

    Timer {
        id: previewTimer

        interval: 650
        onTriggered: {
            root.busy = false;
            root.statusMessage = I18n.t("auth.previewSuccess");
        }
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root.prompt = message || I18n.t("login.password");
            root.echoResponse = echoResponse;

            if (error) {
                root.errorMessage = message;
                root.statusMessage = "";
                root.busy = false;
                return;
            }
            if (!responseRequired)
                return;

            if (root.pendingResponse) {
                const response = root.pendingResponse;
                root.pendingResponse = "";
                Greetd.respond(response);
                return;
            }

            root.awaitingResponse = true;
            root.busy = false;
            root.statusMessage = root.prompt;
        }

        function onAuthFailure(message) {
            root.pendingResponse = "";
            root.launchCommand = [];
            root.busy = false;
            root.awaitingResponse = false;
            root.markerPending = false;
            root.launching = false;
            root.statusMessage = "";
            root.errorMessage = message || I18n.t("auth.failed");
        }

        function onReadyToLaunch() {
            root.statusMessage = I18n.t("auth.startingSession");
            root.launching = true;
            launchDelay.restart();
        }

        function onError(error) {
            // Drop the buffered password as soon as the session attempt fails.
            root.pendingResponse = "";
            root.launchCommand = [];
            root.busy = false;
            root.awaitingResponse = false;
            root.markerPending = false;
            root.launching = false;
            root.statusMessage = "";
            root.errorMessage = error;
        }
    }
}
