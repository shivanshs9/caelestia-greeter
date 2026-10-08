# shellcheck shell=bash
# Behaviour tests for scripts/caelestia-greeter-compositor (config generation
# only; Hyprland itself is replaced by a stub).
# Sourced by tests/run.sh with $ROOT and $TMP set.

COMPOSITOR="$ROOT/scripts/caelestia-greeter-compositor"
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/hyprland-args"\n' "$TMP" >"$TMP/bin/start-hyprland"
chmod +x "$TMP/bin/start-hyprland"

run_compositor() {
    PATH="$TMP/bin:$PATH" \
    XDG_CACHE_HOME="$TMP/cache" \
    CAELESTIA_GREETER_VCONSOLE="$TMP/vconsole.conf" \
    CAELESTIA_GREETER_HYPRLAND_CONFIG="$TMP/greeter.lua" \
    bash "$COMPOSITOR"
}

lua_value() {
    sed -n "s/^ *$1 = \"\(.*\)\",\$/\1/p" "$TMP/greeter.lua"
}

printf 'KEYMAP=jp106\nXKBLAYOUT="jp"\nXKBMODEL=jp106\nXKBOPTIONS=terminate:ctrl_alt_bksp\n' >"$TMP/vconsole.conf"
mkdir -p "$TMP/cache"
run_compositor
assert_eq "jp" "$(lua_value kb_layout)" "kb_layout follows /etc/vconsole.conf"
assert_eq "jp106" "$(lua_value kb_model)" "kb_model follows /etc/vconsole.conf"
assert_eq "terminate:ctrl_alt_bksp" "$(lua_value kb_options)" "kb_options follows /etc/vconsole.conf"
assert_eq "600" "$(stat -c %a "$TMP/greeter.lua")" "generated Lua config is private to the greeter"
assert_eq "-- -c $TMP/greeter.lua" "$(tr '\n' ' ' <"$TMP/hyprland-args" | sed 's/ $//')" "start-hyprland receives the generated config"

printf 'XKBLAYOUT=us"; os.exit()\nXKBOPTIONS=`id`\n' >"$TMP/vconsole.conf"
run_compositor
assert_eq "usosexit()" "$(lua_value kb_layout)" "Lua string delimiters are stripped from layout"
assert_eq "id" "$(lua_value kb_options)" "backticks are stripped from options"
if command -v lua >/dev/null 2>&1; then
    if lua -e "hl={monitor=function()end,config=function()end,on=function()end}; dofile('$TMP/greeter.lua')"; then
        pass "generated file is valid Lua"
    else
        fail "generated file is valid Lua"
    fi
fi

grep -q 'no_update_news = true' "$TMP/greeter.lua" && pass "Hyprland update news disabled" || fail "Hyprland update news disabled"
grep -q 'no_donation_nag = true' "$TMP/greeter.lua" && pass "Hyprland donation window disabled" || fail "Hyprland donation window disabled"
grep -q 'hl.bind' "$TMP/greeter.lua" && fail "no keybinds in greeter config" || pass "no keybinds in greeter config"

rm -f "$TMP/vconsole.conf"
run_compositor
assert_eq "us" "$(lua_value kb_layout)" "layout falls back to us without vconsole.conf"

# Unwritable cache: the fallback must be a fresh private directory, never a
# fixed name another account could have created first.
mkdir -p "$TMP/rt" "$TMP/readonly"
chmod 500 "$TMP/readonly"
PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$TMP/readonly/cache" XDG_RUNTIME_DIR="$TMP/rt" \
    CAELESTIA_GREETER_VCONSOLE=/nonexistent bash "$COMPOSITOR"
chmod 700 "$TMP/readonly"
fallback_dir="$(find "$TMP/rt" -mindepth 1 -maxdepth 1 -type d -name 'caelestia-greeter-cache.*' | head -n 1)"
[[ -n "$fallback_dir" ]] && pass "fallback cache is a mktemp directory under XDG_RUNTIME_DIR" || fail "fallback cache is a mktemp directory under XDG_RUNTIME_DIR"
if [[ -n "$fallback_dir" ]]; then
    assert_eq "700" "$(stat -c %a "$fallback_dir")" "fallback cache directory is private"
    assert_file_present "$fallback_dir/caelestia-greeter-hyprland.lua" "Lua config written inside the private fallback"
fi

CAELESTIA_GREETER_KB_LAYOUT="br" run_compositor
assert_eq "br" "$(lua_value kb_layout)" "explicit CAELESTIA_GREETER_KB_LAYOUT override wins"
