# shellcheck shell=bash
# Behaviour tests for scripts/caelestia-session (command resolution only).
# Sourced by tests/run.sh with $ROOT and $TMP set.

SESSION="$ROOT/scripts/caelestia-session"
mkdir -p "$TMP/bin" "$TMP/sessions"
printf '#!/bin/sh\n' >"$TMP/bin/start-hyprland"; chmod +x "$TMP/bin/start-hyprland"

resolve() {
    # The wrapper only uses bash builtins, so PATH can be the stub dir alone;
    # this keeps the machine's real uwsm/start-hyprland out of the test.
    PATH="$TMP/bin" \
    CAELESTIA_SESSION_ENV="$TMP/session.env" \
    CAELESTIA_SESSION_WAYLAND_SESSIONS="$TMP/sessions" \
    /usr/bin/bash "$SESSION" --print-command | tr '\n' ' ' | sed 's/ $//'
}

assert_eq "start-hyprland" "$(resolve)" "without uwsm the wrapper runs start-hyprland"

printf '#!/bin/sh\n' >"$TMP/bin/uwsm"; chmod +x "$TMP/bin/uwsm"
assert_eq "uwsm start -e -D Hyprland -- start-hyprland" "$(resolve)" \
    "with uwsm but no hyprland.desktop the wrapper hardcodes start-hyprland"

touch "$TMP/sessions/hyprland.desktop"
assert_eq "uwsm start -e -D Hyprland hyprland.desktop" "$(resolve)" \
    "with uwsm and hyprland.desktop the wrapper references the entry"

printf 'CAELESTIA_SESSION_UWSM=0\n' >"$TMP/session.env"
assert_eq "start-hyprland" "$(resolve)" "CAELESTIA_SESSION_UWSM=0 in session.env opts out of uwsm"
rm -f "$TMP/session.env"

rm -f "$TMP/bin/start-hyprland" "$TMP/bin/uwsm"
assert_eq "/usr/bin/Hyprland" "$(resolve)" "last resort is /usr/bin/Hyprland"
