#!/usr/bin/env python3
"""Discover local login accounts and Wayland sessions for Caelestia Greeter.

Runs as the restricted greeter account. Prints one JSON document:

    {"users": [{"username", "displayName", "avatar"}],
     "sessions": [{"name", "command", "type", "desktopFile"}]}

Environment overrides (used by tests and preview mode):

    CAELESTIA_GREETER_SERVICE_USER   greeter account to hide (default: greeter)
    CAELESTIA_GREETER_LOGIN_DEFS     path to login.defs
    CAELESTIA_GREETER_ACCOUNTS_DIR   AccountsService users directory
    CAELESTIA_GREETER_ICONS_DIR      AccountsService icons directory
    CAELESTIA_GREETER_SESSION_DIRS   colon-separated wayland-sessions dirs
    CAELESTIA_GREETER_PASSWD_FILE    passwd-format file instead of NSS
    CAELESTIA_GREETER_SESSION_SCRIPT caelestia-session wrapper to query with
                                     --print-command (default: installed path)
"""

import configparser
import json
import os
import pwd
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

FIELD_CODE = re.compile(r"%[fFuUdDnNickvm]")
DEFAULT_SESSION_DIRS = ("/usr/local/share/wayland-sessions", "/usr/share/wayland-sessions")
DEFAULT_SESSION_SCRIPT = "/usr/local/bin/caelestia-session"
NOLOGIN_SHELLS = ("/nologin", "/false")


def bool_value(value):
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def login_limits(path):
    minimum, maximum = 1000, 60000
    try:
        for line in Path(path).read_text(encoding="utf-8", errors="ignore").splitlines():
            fields = line.split()
            if len(fields) < 2:
                continue
            if fields[0] == "UID_MIN":
                minimum = int(fields[1])
            elif fields[0] == "UID_MAX":
                maximum = int(fields[1])
    except (OSError, ValueError):
        pass
    return minimum, maximum


def accounts_service_values(accounts_dir, username):
    values = {}
    path = Path(accounts_dir) / username
    try:
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key in {"RealName", "Icon"}:
                values[key] = value.strip()
    except OSError:
        pass
    return values


def readable_file(path):
    try:
        candidate = Path(path)
        return candidate.is_file() and os.access(candidate, os.R_OK)
    except (OSError, TypeError):
        return False


MAX_AVATAR_BYTES = 16 * 1024 * 1024


def safe_avatar(path):
    """True if the file is a PNG, JPEG or WebP of sane size.

    Avatar candidates include files from the user's home. They are decoded by
    the greeter process, so only mature raster decoders are allowed and SVG,
    GIF, BMP and AVIF are rejected regardless of extension.
    """
    if not path or not path.startswith("/") or not readable_file(path):
        return False
    try:
        if os.path.getsize(path) > MAX_AVATAR_BYTES:
            return False
        with open(path, "rb") as handle:
            head = handle.read(16)
    except OSError:
        return False
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return True
    if head.startswith(b"\xff\xd8\xff"):
        return True
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return True
    return False


def passwd_entries():
    passwd_file = os.environ.get("CAELESTIA_GREETER_PASSWD_FILE")
    if not passwd_file:
        return list(pwd.getpwall())

    entries = []
    for line in Path(passwd_file).read_text(encoding="utf-8", errors="ignore").splitlines():
        fields = line.split(":")
        if len(fields) != 7:
            continue
        try:
            entries.append(pwd.struct_passwd((fields[0], fields[1], int(fields[2]), int(fields[3]), fields[4], fields[5], fields[6])))
        except ValueError:
            continue
    return entries


def discover_users():
    uid_min, uid_max = login_limits(os.environ.get("CAELESTIA_GREETER_LOGIN_DEFS", "/etc/login.defs"))
    service_user = os.environ.get("CAELESTIA_GREETER_SERVICE_USER", "greeter")
    accounts_dir = os.environ.get("CAELESTIA_GREETER_ACCOUNTS_DIR", "/var/lib/AccountsService/users")
    icons_dir = os.environ.get("CAELESTIA_GREETER_ICONS_DIR", "/var/lib/AccountsService/icons")
    result = []

    for account in sorted(passwd_entries(), key=lambda item: item.pw_uid):
        if not uid_min <= account.pw_uid <= uid_max:
            continue
        if account.pw_name in {"root", "nobody", service_user}:
            continue
        if account.pw_shell.endswith(NOLOGIN_SHELLS):
            continue

        account_values = accounts_service_values(accounts_dir, account.pw_name)
        gecos = account.pw_gecos.split(",", 1)[0].strip()
        display_name = account_values.get("RealName", "").strip() or gecos or account.pw_name
        icon = account_values.get("Icon", "").removeprefix("file://")
        candidates = [
            icon,
            f"{icons_dir}/{account.pw_name}",
            f"{account.pw_dir}/.face.icon",
            f"{account.pw_dir}/.face",
        ]
        avatar = next((str(Path(path)) for path in candidates if safe_avatar(path)), "")

        result.append({
            "username": account.pw_name,
            "displayName": display_name,
            "avatar": avatar,
        })

    return result


def localized_name(entry):
    locale_name = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG", "")
    locale_name = locale_name.split(".", 1)[0]
    candidates = []
    if locale_name:
        candidates.append(f"Name[{locale_name}]")
        language = locale_name.split("_", 1)[0]
        if language != locale_name:
            candidates.append(f"Name[{language}]")
    candidates.append("Name")
    for key in candidates:
        value = entry.get(key, "").strip()
        if value:
            return value
    return ""


def clean_exec(value):
    """Split a desktop-entry Exec line into argv and drop field codes."""
    try:
        tokens = shlex.split(value)
    except ValueError:
        return []

    cleaned = []
    for token in tokens:
        token = token.replace("%%", "\0")
        token = FIELD_CODE.sub("", token)
        token = token.replace("\0", "%")
        if token:
            cleaned.append(token)
    return cleaned


def valid_executable(command, try_exec):
    candidate = try_exec.strip() if try_exec else command[0]
    if not candidate:
        return False
    if candidate.startswith("/"):
        return os.path.isfile(candidate) and os.access(candidate, os.X_OK)
    return shutil.which(candidate) is not None


def session_dirs():
    configured = os.environ.get("CAELESTIA_GREETER_SESSION_DIRS")
    if configured:
        return [Path(item) for item in configured.split(":") if item]
    return [Path(item) for item in DEFAULT_SESSION_DIRS]


def wrapper_commands():
    """argv that the configured Caelestia wrapper would exec, if known.

    Discovered desktop entries running the identical command are hidden so
    the menu does not list the same session twice under two names.
    """
    script = os.environ.get("CAELESTIA_GREETER_SESSION_SCRIPT", DEFAULT_SESSION_SCRIPT)
    if not (os.path.isfile(script) and os.access(script, os.X_OK)):
        return set()
    try:
        output = subprocess.run(
            [script, "--print-command"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return set()
    if output.returncode != 0:
        return set()
    argv = tuple(line for line in output.stdout.split("\n") if line)
    return {argv} if argv else set()


def discover_sessions():
    result = []
    seen = set(wrapper_commands())
    for directory in session_dirs():
        if not directory.is_dir():
            continue
        for desktop_file in sorted(directory.glob("*.desktop")):
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            parser.optionxform = str
            try:
                parser.read(desktop_file, encoding="utf-8")
                entry = parser["Desktop Entry"]
            except (OSError, KeyError, configparser.Error):
                continue

            if entry.get("Type", "Application") != "Application":
                continue
            if bool_value(entry.get("Hidden")) or bool_value(entry.get("NoDisplay")):
                continue

            name = localized_name(entry)
            command = clean_exec(entry.get("Exec", ""))
            if not name or not command or not valid_executable(command, entry.get("TryExec", "")):
                continue

            identity = tuple(command)
            if identity in seen:
                continue
            seen.add(identity)
            result.append({
                "name": name,
                "command": command,
                "type": "wayland",
                "desktopFile": str(desktop_file),
            })

    return result


def main():
    json.dump({"users": discover_users(), "sessions": discover_sessions()}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
