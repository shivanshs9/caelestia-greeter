# shellcheck shell=bash
# Behaviour tests for services/catalog.py.
# Sourced by tests/run.sh with $ROOT and $TMP set.

CATALOG="$ROOT/services/catalog.py"
mkdir -p "$TMP/sessions" "$TMP/accounts/users" "$TMP/accounts/icons" "$TMP/bin" "$TMP/home/alice"

printf 'UID_MIN 1000\nUID_MAX 60000\n' >"$TMP/login.defs"
cat >"$TMP/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
greeter:x:967:967::/var/lib/greeter:/usr/bin/nologin
alice:x:1000:1000:Alice Liddell,,,:$TMP/home/alice:/bin/bash
bob:x:1001:1001::/home/bob:/usr/bin/nologin
svc:x:999:999:Service:/:/bin/bash
carol:x:1002:1002::/home/carol:/bin/zsh
EOF
printf '[User]\nRealName=Alice in Wonderland\nIcon=%s\n' "$TMP/home/alice/avatar.png" >"$TMP/accounts/users/alice"
printf '\x89PNG\r\n\x1a\nrest-of-a-png' >"$TMP/home/alice/avatar.png"
# carol's avatar candidates are an SVG and a text file: neither may be used.
mkdir -p "$TMP/home/carol"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>' >"$TMP/home/carol/.face.icon"
printf 'hello' >"$TMP/home/carol/.face"
sed -i "s|carol:x:1002:1002::/home/carol|carol:x:1002:1002::$TMP/home/carol|" "$TMP/passwd"

printf '#!/bin/sh\n' >"$TMP/bin/fake-wm"; chmod +x "$TMP/bin/fake-wm"
printf '#!/bin/sh\n' >"$TMP/bin/uwsm"; chmod +x "$TMP/bin/uwsm"

cat >"$TMP/sessions/a-plain.desktop" <<EOF
[Desktop Entry]
Name=Plain
Name[pt_BR]=Simples
Exec=$TMP/bin/fake-wm --flag %F "quoted arg" 100%%
Type=Application
EOF
cat >"$TMP/sessions/b-uwsm.desktop" <<'EOF'
[Desktop Entry]
Name=Managed
Exec=uwsm start -e -D Fake fake.desktop
TryExec=uwsm
Type=Application
EOF
cat >"$TMP/sessions/c-hidden.desktop" <<EOF
[Desktop Entry]
Name=Hidden
Exec=$TMP/bin/fake-wm
NoDisplay=true
Type=Application
EOF
cat >"$TMP/sessions/d-missing.desktop" <<'EOF'
[Desktop Entry]
Name=Missing binary
Exec=/nonexistent/compositor
Type=Application
EOF
cat >"$TMP/sessions/e-dup.desktop" <<'EOF'
[Desktop Entry]
Name=Duplicate of Managed
Exec=uwsm start -e -D Fake fake.desktop
Type=Application
EOF
cat >"$TMP/sessions/f-broken.desktop" <<EOF
[Desktop Entry]
Name=Broken quoting
Exec=$TMP/bin/fake-wm "unterminated
Type=Application
EOF

run_catalog() {
    PATH="$TMP/bin:$PATH" \
    CAELESTIA_GREETER_PASSWD_FILE="$TMP/passwd" \
    CAELESTIA_GREETER_LOGIN_DEFS="$TMP/login.defs" \
    CAELESTIA_GREETER_ACCOUNTS_DIR="$TMP/accounts/users" \
    CAELESTIA_GREETER_ICONS_DIR="$TMP/accounts/icons" \
    CAELESTIA_GREETER_SESSION_DIRS="$TMP/sessions" \
    LC_ALL="${1:-C}" \
    python3 "$CATALOG"
}

query() {
    python3 -c 'import json, sys; d = json.load(sys.stdin); print(eval(sys.argv[1], {"d": d}))' "$1"
}

OUT="$(run_catalog)"

assert_eq "['alice', 'carol']" "$(query 'sorted(u["username"] for u in d["users"])' <<<"$OUT")" \
    "only regular accounts with a login shell are listed"
assert_eq "Alice in Wonderland" "$(query '[u for u in d["users"] if u["username"]=="alice"][0]["displayName"]' <<<"$OUT")" \
    "AccountsService RealName wins over GECOS"
assert_eq "$TMP/home/alice/avatar.png" "$(query '[u for u in d["users"] if u["username"]=="alice"][0]["avatar"]' <<<"$OUT")" \
    "AccountsService Icon is used when readable"
assert_eq "carol" "$(query '[u for u in d["users"] if u["username"]=="carol"][0]["displayName"]' <<<"$OUT")" \
    "username is the display-name fallback"
assert_eq "" "$(query '[u for u in d["users"] if u["username"]=="carol"][0]["avatar"]' <<<"$OUT")" \
    "SVG and non-image .face files are not used as avatars"

# AccountsService Icon pointing at a non-image is ignored as well.
printf '[User]\nIcon=%s\n' "$TMP/passwd" >"$TMP/accounts/users/carol"
OUT_ICON="$(run_catalog)"
assert_eq "" "$(query '[u for u in d["users"] if u["username"]=="carol"][0]["avatar"]' <<<"$OUT_ICON")" \
    "Icon= pointing at a non-image is ignored"
rm -f "$TMP/accounts/users/carol"

assert_eq "['Managed', 'Plain']" "$(query 'sorted(s["name"] for s in d["sessions"])' <<<"$OUT")" \
    "hidden, missing-binary and duplicate sessions are dropped"
assert_eq "['$TMP/bin/fake-wm', '--flag', 'quoted arg', '100%']" \
    "$(query '[s for s in d["sessions"] if s["name"]=="Plain"][0]["command"]' <<<"$OUT")" \
    "Exec is split as argv, field codes removed, %% unescaped"
assert_eq "['uwsm', 'start', '-e', '-D', 'Fake', 'fake.desktop']" \
    "$(query '[s for s in d["sessions"] if s["name"]=="Managed"][0]["command"]' <<<"$OUT")" \
    "uwsm desktop entry is kept intact"

OUT_PT="$(run_catalog pt_BR.UTF-8)"
assert_eq "Simples" "$(query '[s for s in d["sessions"] if s["desktopFile"].endswith("a-plain.desktop")][0]["name"]' <<<"$OUT_PT")" \
    "localized Name is preferred"

# Discovered entries that run the same argv as the Caelestia wrapper are hidden.
printf '#!/bin/sh\n[ "$1" = --print-command ] && printf "%%s\\n" uwsm start -e -D Fake fake.desktop\n' >"$TMP/bin/fake-caelestia-session"
chmod +x "$TMP/bin/fake-caelestia-session"
OUT_DEDUP="$(CAELESTIA_GREETER_SESSION_SCRIPT="$TMP/bin/fake-caelestia-session" run_catalog)"
assert_eq "['Plain']" "$(query 'sorted(s["name"] for s in d["sessions"])' <<<"$OUT_DEDUP")" \
    "session equal to the wrapper's resolved command is hidden"

# A wrapper that fails must not hide anything.
printf '#!/bin/sh\nexit 1\n' >"$TMP/bin/broken-session"; chmod +x "$TMP/bin/broken-session"
OUT_BROKEN="$(CAELESTIA_GREETER_SESSION_SCRIPT="$TMP/bin/broken-session" run_catalog)"
assert_eq "['Managed', 'Plain']" "$(query 'sorted(s["name"] for s in d["sessions"])' <<<"$OUT_BROKEN")" \
    "failing wrapper hides nothing"

# Session directory that does not exist must not be an error.
if PATH="$TMP/bin:$PATH" CAELESTIA_GREETER_PASSWD_FILE="$TMP/passwd" CAELESTIA_GREETER_SESSION_DIRS="$TMP/nope" python3 "$CATALOG" >/dev/null; then
    pass "missing session directory is tolerated"
else
    fail "missing session directory is tolerated"
fi
