# shellcheck shell=bash
# Behaviour tests for scripts/caelestia-greeter-run (greeter/compositor
# handoff). The greeter and hyprctl are replaced by stubs.
# Sourced by tests/run.sh with $ROOT and $TMP set.

RUN="$ROOT/scripts/caelestia-greeter-run"
mkdir -p "$TMP/bin" "$TMP/rt"

# The script calls binaries by absolute path; stage a copy with those paths
# redirected into the temp dir so nothing real is touched.
sed -e "s|/usr/local/bin/caelestia-greeter-session|$TMP/bin/greeter|g" \
    -e "s|/usr/bin/hyprctl|$TMP/bin/hyprctl|g" \
    -e "s|/usr/bin/sleep|$TMP/bin/sleep|g" \
    "$RUN" >"$TMP/run.sh"

printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/hyprctl.log"\n' "$TMP" >"$TMP/bin/hyprctl"
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/sleep"
chmod +x "$TMP/bin/hyprctl" "$TMP/bin/sleep"

# Greeter that behaves like a successful login: touches the marker it was
# given and exits 0.
cat >"$TMP/bin/greeter" <<'EOF'
#!/bin/sh
printf '%s\n' "$CAELESTIA_GREETER_LAUNCH_MARKER" > "$MARKER_SEEN"
case "$MODE" in
    handoff) touch "$CAELESTIA_GREETER_LAUNCH_MARKER"; exit 0 ;;
    crash) exit 3 ;;
esac
EOF
chmod +x "$TMP/bin/greeter"

: >"$TMP/hyprctl.log"
if MODE=handoff MARKER_SEEN="$TMP/seen" XDG_RUNTIME_DIR="$TMP/rt" bash "$TMP/run.sh" 2>/dev/null; then
    pass "handoff exits 0"
else
    fail "handoff exits 0"
fi
marker_path="$(cat "$TMP/seen")"
case "$marker_path" in
    "$TMP/rt/caelestia-greeter."*/launch-requested) pass "marker lives in a private mktemp dir under XDG_RUNTIME_DIR" ;;
    *) fail "marker lives in a private mktemp dir under XDG_RUNTIME_DIR (got $marker_path)" ;;
esac
assert_file_absent "$(dirname "$marker_path")" "marker directory removed after handoff"
assert_eq "dispatch exit" "$(tr '\n' ' ' <"$TMP/hyprctl.log" | sed 's/ $//')" "compositor asked to exit after handoff"

: >"$TMP/hyprctl.log"
if MODE=crash MARKER_SEEN="$TMP/seen" XDG_RUNTIME_DIR="$TMP/rt" bash "$TMP/run.sh" 2>"$TMP/err"; then
    fail "crash exits non-zero"
else
    pass "crash exits non-zero"
fi
grep -q 'status 3' "$TMP/err" && pass "crash status is logged" || fail "crash status is logged"
assert_eq "dispatch exit" "$(tr '\n' ' ' <"$TMP/hyprctl.log" | sed 's/ $//')" "compositor asked to exit after crash (paced restart)"
assert_eq "0" "$(find "$TMP/rt" -mindepth 1 -maxdepth 1 -type d | wc -l)" "no marker directories leak"
