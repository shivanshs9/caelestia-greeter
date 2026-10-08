# shellcheck shell=bash
# Behaviour tests for scripts/caelestia-greeter-profile-sync.
# Sourced by tests/run.sh with $ROOT and $TMP set.

SYNC="$ROOT/scripts/caelestia-greeter-profile-sync"
HOME_DIR="$TMP/home"
STATE="$HOME_DIR/.local/state/caelestia"
mkdir -p "$STATE/wallpaper" "$HOME_DIR/.config/caelestia"

# A 1x1 PNG, built without external tools.
python3 - "$HOME_DIR/wallpaper.png" <<'EOF'
import struct, sys, zlib
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
raw = b"\x00\xff\x00\x00"
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
EOF
printf '%s\n' "$HOME_DIR/wallpaper.png" >"$STATE/wallpaper/path.txt"
printf '{"wallpaper":1}\n' >"$HOME_DIR/.config/caelestia/shell.json"
printf '{"scheme":1}\n' >"$STATE/scheme.json"
printf 'plain text, not an image\n' >"$HOME_DIR/not-an-image.txt"
printf '\x00\x01\x00\x00fake sfnt header\n' >"$HOME_DIR/fake.ttf"

# Service user must differ from the login user, and must exist for id -gn.
export CAELESTIA_GREETER_SERVICE_USER=nobody
export CAELESTIA_GREETER_USER="$(id -un)"
export CAELESTIA_GREETER_RUNTIME_DIR="$TMP/run"
export CAELESTIA_GREETER_CACHE_DIR="$TMP/cache"
export CAELESTIA_GREETER_SOURCE_STATE_DIR="$STATE"
export CAELESTIA_GREETER_SHELL_CONFIG_SOURCE="$HOME_DIR/.config/caelestia/shell.json"
export CAELESTIA_GREETER_GOOGLE_SANS_FLEX_SOURCE="$HOME_DIR/fake.ttf"

run_sync() {
    bash "$SYNC" 2>"$TMP/stderr" || return $?
}

profile_value() {
    sed -n "s/^$1=//p" "$TMP/run/profile.env"
}

# --- happy path -----------------------------------------------------------
run_sync
assert_eq "$(id -un)" "$(profile_value CAELESTIA_GREETER_USER)" "profile.env records the login user"
assert_eq "$TMP/cache/wallpaper.png" "$(profile_value CAELESTIA_GREETER_WALLPAPER)" "PNG wallpaper copied with png extension"
assert_eq "$TMP/cache/shell.json" "$(profile_value CAELESTIA_GREETER_SHELL_CONFIG_PATH)" "shell.json copied"
assert_eq "$TMP/cache/state/scheme.json" "$(profile_value CAELESTIA_GREETER_SCHEME_PATH)" "scheme.json copied"
assert_file_present "$TMP/cache/GoogleSansFlex-VariableFont_GRAD,ROND,opsz,slnt,wdth,wght.ttf" "font accepted by sfnt magic"
assert_eq "640" "$(stat -c %a "$TMP/cache/wallpaper.png")" "cached files are 0640"
assert_eq "750" "$(stat -c %a "$TMP/cache")" "cache directory is 0750"
assert_eq "640" "$(stat -c %a "$TMP/run/profile.env")" "profile.env is 0640"
assert_eq "0" "$(find "$TMP/cache" -name '.asset.*' | wc -l)" "no temporary files left behind"

# --- rejected inputs ------------------------------------------------------
CAELESTIA_GREETER_WALLPAPER_SOURCE="$HOME_DIR/not-an-image.txt" run_sync
assert_eq "" "$(profile_value CAELESTIA_GREETER_WALLPAPER)" "text file is not accepted as wallpaper"
assert_eq "0" "$(find "$TMP/cache" -maxdepth 1 -name 'wallpaper*' | wc -l)" "stale wallpaper copy removed"
grep -q "unexpected type 'text/plain' for image" "$TMP/stderr" && pass "rejection is logged" || fail "rejection not logged"

CAELESTIA_GREETER_WALLPAPER_SOURCE="relative/path.png" run_sync
assert_eq "" "$(profile_value CAELESTIA_GREETER_WALLPAPER)" "relative paths are rejected"

cp "$HOME_DIR/wallpaper.png" "$HOME_DIR/secret.png"
chmod 000 "$HOME_DIR/secret.png"
CAELESTIA_GREETER_WALLPAPER_SOURCE="$HOME_DIR/secret.png" run_sync
assert_eq "" "$(profile_value CAELESTIA_GREETER_WALLPAPER)" "file the user cannot read is not copied"
chmod 644 "$HOME_DIR/secret.png"

printf 'x' >"$HOME_DIR/shell.json.bad"
CAELESTIA_GREETER_SHELL_CONFIG_SOURCE="$HOME_DIR/wallpaper.png" run_sync
assert_eq "" "$(profile_value CAELESTIA_GREETER_SHELL_CONFIG_PATH)" "binary file is not accepted as shell.json"
assert_file_absent "$TMP/cache/shell.json" "previous shell.json copy removed when source is invalid"

# Oversized source: one byte over the JSON limit.
head -c $((1024 * 1024 + 1)) /dev/zero | tr '\0' 'a' >"$HOME_DIR/huge.json"
CAELESTIA_GREETER_SHELL_CONFIG_SOURCE="$HOME_DIR/huge.json" run_sync
assert_eq "" "$(profile_value CAELESTIA_GREETER_SHELL_CONFIG_PATH)" "oversized file is rejected"

# Wallpaper path file pointing at a symlink to an unreadable file.
ln -sf "$HOME_DIR/secret.png" "$HOME_DIR/link.png"
chmod 000 "$HOME_DIR/secret.png"
printf '%s\n' "$HOME_DIR/link.png" >"$STATE/wallpaper/path.txt"
run_sync
assert_eq "" "$(profile_value CAELESTIA_GREETER_WALLPAPER)" "symlink to unreadable file is not copied"
chmod 644 "$HOME_DIR/secret.png"

# Decoders outside PNG/JPEG/WebP are refused even for real images.
printf 'GIF89a\x01\x00\x01\x00\x00\x00\x00;' >"$HOME_DIR/anim.gif"
CAELESTIA_GREETER_WALLPAPER_SOURCE="$HOME_DIR/anim.gif" run_sync
assert_eq "" "$(profile_value CAELESTIA_GREETER_WALLPAPER)" "GIF wallpaper is rejected"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>' >"$HOME_DIR/vector.svg"
CAELESTIA_GREETER_WALLPAPER_SOURCE="$HOME_DIR/vector.svg" run_sync
assert_eq "" "$(profile_value CAELESTIA_GREETER_WALLPAPER)" "SVG wallpaper is rejected"

# --- account guards -------------------------------------------------------
CAELESTIA_GREETER_USER=root run_sync
assert_eq "" "$(sed -n 's/^CAELESTIA_GREETER_USER=//p' "$TMP/run/profile.env" | grep -x root || true)" "root is never synchronised"

CAELESTIA_GREETER_USER=no-such-user-$$ run_sync
assert_file_absent "$TMP/run/profile.env" "unknown user removes profile.env"
