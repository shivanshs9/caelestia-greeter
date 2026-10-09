# Caelestia Greeter

A Material Expressive login screen for Caelestia Shell, built with QML, Quickshell, Hyprland and greetd.

## Features

- Caelestia wallpaper and Material 3 colour scheme.
- Clock, date, motion and password glyphs matching the Caelestia lock screen.
- Dynamic Google Sans Flex loading from the installed Caelestia Shell.
- Brazilian Portuguese and English.
- Automatic local-user, display-name and avatar discovery.
- Automatic discovery and selection of installed Wayland sessions.
- Manual username entry through the **Other user** option.
- greetd authentication and session launch.
- Multi-monitor rendering and local preview mode.
- Restart and power-off actions.
- Interactive installer with display-manager backup and recovery.

## Requirements

- Hyprland (hosts the login screen; started bare as the `greeter` account)
- Quickshell 0.3 or newer with the `Quickshell.Services.Greetd` module
- greetd
- systemd
- Python 3, used by the runtime user and session catalogue
- `util-linux` (`setpriv`) and `file`, used by the root profile synchroniser

Optional:

- Caelestia Shell, for the Google Sans Flex font and `M3Shapes`; the clock falls back to the system font and the password glyphs to simple circles
- `uwsm`; when installed, the default Caelestia session starts Hyprland as a systemd user unit (see [UWSM](#uwsm))

The installer is intended for systemd-based Caelestia/Hyprland systems and has been validated on CachyOS.

## Security model

The greeter never sees a password outside greetd's protocol: the QML sends the response to greetd over `$GREETD_SOCK`, clears the field, and greetd performs PAM authentication and starts the session. Nothing in this repository is setuid or runs PAM itself.

The only root code is `caelestia-greeter-profile-sync`, run by greetd's `ExecStartPre`. It copies the chosen user's wallpaper, palette, avatar, Shell configuration and font for the restricted `greeter` account, and:

- reads every user-named file **as that user** (`setpriv`), so it cannot expose anything the user could not already open;
- accepts only PNG/JPEG/WebP for wallpaper and avatar (no SVG, AVIF, GIF or BMP decoders in the greeter process), JSON for configuration and sfnt fonts, with size caps;
- writes copies as `root:greeter` `0640` inside a `0750` cache, so other local accounts cannot read them.

Session commands come from `.desktop` files or `config/defaults.json` as argument lists. greetd joins them with spaces and runs `sh -c`, so the greeter shell-quotes each argument before handing it over.

The installer creates `/etc/pam.d/greetd-greeter`, the PAM service greetd uses to start the greeter process itself. It is independent from `system-auth`, so face or fingerprint modules configured there (`pam_visage`, `pam_howdy`, `pam_fprintd`) cannot prevent the login screen from appearing. User logins keep using `/etc/pam.d/greetd`.

## Tests

```bash
./tests/run.sh
```

Runs without root and never touches the system: syntax checks for every script and QML file, and behaviour tests for the profile synchroniser (type, size and permission rejection), the session catalogue and the compositor configuration generator.

## Preview

Always test the interface before replacing a working display manager:

```bash
./scripts/run-preview.sh
```

Preview mode reads the current user's Caelestia state:

```text
~/.config/caelestia/shell.json
~/.local/state/caelestia/scheme.json
~/.local/state/caelestia/wallpaper/path.txt
```

Useful overrides:

```bash
CAELESTIA_GREETER_LANGUAGE=pt-BR ./scripts/run-preview.sh
CAELESTIA_GREETER_USER=user ./scripts/run-preview.sh
CAELESTIA_GREETER_AVATAR=/path/to/avatar.png ./scripts/run-preview.sh
CAELESTIA_GREETER_WALLPAPER=/path/to/wallpaper.jpg ./scripts/run-preview.sh
CAELESTIA_GREETER_SCHEME_PATH=/path/to/scheme.json ./scripts/run-preview.sh
```

## User and session selection

The greeter discovers regular local accounts using the system UID range from `/etc/login.defs`. System accounts, `root`, `nobody`, the restricted greetd account and users with `nologin` or `false` shells are ignored.

Display names and avatars are read from AccountsService when available. The user's `.face.icon` and `.face` files are also considered when they are readable by the greeter account. When no avatar is accessible, the interface displays the user's initial.

Wayland sessions are discovered from:

```text
/usr/local/share/wayland-sessions
/usr/share/wayland-sessions
```

Configured sessions from `config/defaults.json` are shown first, so the Caelestia session remains the default. The last successfully selected session is remembered.

Duplicates are removed: a discovered entry whose command equals another entry, or equals what `/usr/local/bin/caelestia-session --print-command` resolves to, is dropped. With `uwsm` installed this hides `Hyprland (uwsm-managed)`, because **Caelestia** runs the same command. Other installed compositors you never want on the login screen can be hidden by desktop file name or display name:

```json
"hiddenSessions": ["sway.desktop", "hyprland.desktop"]
```

The **Other user** option keeps manual username entry available for accounts that are intentionally hidden from the catalogue.

## UWSM

The login screen itself is **not** run under UWSM, and should not be: UWSM needs a user systemd manager, a session bus and `graphical-session.target` for the account it manages, which only adds failure modes to a screen that has to come up on every boot. This matches nwg-hello, tuigreet, GDM and SDDM, which all start the greeter compositor bare.

Your own session is where UWSM belongs. The default **Caelestia** session (`/usr/local/bin/caelestia-session`) runs

```text
uwsm start -e -D Hyprland hyprland.desktop
```

when `uwsm` is installed, and plain `start-hyprland` otherwise. To force the plain path with `uwsm` installed, create `/etc/caelestia-greeter/session.env` containing `CAELESTIA_SESSION_UWSM=0`. The `Hyprland (uwsm-managed)` entry from `/usr/share/wayland-sessions` is also listed when present.

## Installation

Run the interactive installer from the repository root:

```bash
./install.sh
```

The language is detected from the system locale. It can also be selected explicitly:

```bash
./install.sh --lang pt-BR
./install.sh --lang en
```

Before changing the system, the installer displays the complete plan and waits for an explicit confirmation. It then:

1. detects the local user whose Caelestia profile will be used;
2. detects the current display manager through `display-manager.service` and active systemd services;
3. validates Hyprland, Quickshell, greetd and the project files;
4. backs up the current display manager, its service state and any existing Caelestia Greeter installation;
5. installs the QML interface, session scripts, Hyprland greeter wrapper and `/etc/greetd/greetd.conf`;
6. copies the user's avatar, wallpaper, Material palette, Shell configuration and Google Sans Flex file into `/var/cache/caelestia-greeter` for the restricted `greeter` account, and pins that user in the greetd systemd drop-in;
7. installs `/etc/pam.d/greetd-greeter` unless one already exists, and configures GNOME Keyring PAM integration when the module is available;
8. disables the previous display manager and enables greetd for the next boot;
9. installs the `caelestia-greeter-restore` recovery command.

The currently running display manager is **not stopped** during installation. The change takes effect only after a reboot.

greetd reads `/etc/greetd/greetd.conf` before `/etc/greetd/config.toml`, and package upgrades only replace `config.toml`. The installer therefore writes `greetd.conf`; an existing `config.toml` is left alone (it is ignored by greetd while `greetd.conf` exists) and is part of the backup.

### Display-manager backups

The installer recognises SDDM, GDM, LightDM, greetd, Ly and LXDM. Backups are stored under:

```text
/var/backups/caelestia-greeter/YYYYmmdd-HHMMSS/
```

For SDDM, the backup includes its configuration, state file and the configured theme directory when one can be identified. The systemd `display-manager.service` link and the previous service state are recorded for every supported manager.

### Installer options

```text
--user USER       Select the user profile to synchronise
--yes             Skip the confirmation prompt
--no-keyring      Do not modify greetd's PAM file for GNOME Keyring
--lang pt-BR|en   Select the installer language
```

## Restore the previous display manager

From a TTY, run:

```bash
sudo caelestia-greeter-restore
```

The command displays the recovery plan, disables greetd for the next boot, restores the backed-up files and re-enables the previous display manager. A specific backup can be selected:

```bash
sudo caelestia-greeter-restore /var/backups/caelestia-greeter/YYYYmmdd-HHMMSS
```

The current graphical session is not stopped by the restore command; reboot to apply the restored configuration.

## Configuration

Defaults live in `config/defaults.json`:

```json
{
  "defaultUser": "",
  "displayName": "",
  "avatar": "",
  "language": "system",
  "loginStartsOpen": false,
  "wallpaper": "caelestia",
  "hiddenSessions": [],
  "sessions": [
    {
      "name": "Caelestia",
      "command": ["/usr/local/bin/caelestia-session"],
      "type": "wayland"
    }
  ]
}
```

Use `"wallpaper": "caelestia"` to follow the active Caelestia wallpaper. Set `"loginStartsOpen": true` to skip the initial user/session selection view and open the password surface immediately; pressing Escape returns to the selector view.

## Runtime data

The profile synchroniser creates root-owned, greeter-group-readable copies of the selected user's visual state. It writes cached assets to `/var/cache/caelestia-greeter` (`root:greeter`, `0750`) and the resolved environment to `/run/caelestia-greeter/profile.env`.

The runtime catalogue reads account and session metadata only. The user's original wallpaper, avatar, Shell configuration and palette are never modified.

The greeter's keyboard layout follows `/etc/vconsole.conf` (`XKBLAYOUT`, `XKBVARIANT`, `XKBMODEL`, `XKBOPTIONS`, as written by `localectl`), falling back to `us`.

## Structure

- `components/`: interface components.
- `config/`: defaults and environment overrides.
- `design/`: dynamic theme and motion tokens.
- `i18n/`: translation catalogues.
- `services/`: authentication, catalogue (`catalog.py`) and power actions.
- `packaging/`: greetd, PAM and systemd configuration.
- `scripts/`: preview, synchronisation, session and recovery commands.
- `tests/`: unprivileged test runner and behaviour tests.
- `install.sh`: interactive system installer.
