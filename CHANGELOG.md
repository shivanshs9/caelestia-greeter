# Changelog

## 1.1.0 — 2026-10-08

### Security

- `caelestia-greeter-profile-sync` reads every user-named file as that user (`setpriv`) instead of as root, so a path in `wallpaper/path.txt`, `shell.json` or AccountsService can no longer make root publish a file the user could not read.
- Cached copies are type-checked (image / JSON / sfnt font), size-capped and written `root:greeter` `0640` inside a `0750` cache instead of world-readable `0644`.
- Session arguments are shell-quoted before `Greetd.launch`; greetd joins them with spaces and runs `sh -c`.
- Keyboard options from `/etc/vconsole.conf` are sanitised before being embedded in the generated Hyprland Lua config.
- Compositor cache fallback is a `mktemp -d` directory instead of the fixed `/tmp/caelestia-greeter-cache-<uid>`, which another local account could pre-create and then swap the Lua config Hyprland executes.
- Launch marker moved from a fixed name under `/tmp` to a private `mktemp -d` directory handed to the greeter via `CAELESTIA_GREETER_LAUNCH_MARKER`.
- Wallpaper and avatar copies are limited to PNG, JPEG and WebP; SVG, AVIF, GIF and BMP are rejected to keep those decoders out of the greeter process. `catalog.py` applies the same magic-number check before handing `~/.face` or AccountsService icons to `Image`.
- User- and PAM-derived strings (display names from GECOS/AccountsService, session names, PAM prompts and messages) render as `Text.PlainText`; Qt's `AutoText` default would interpret HTML in a `chfn` full name.
- Hyprland update-news and donation windows are disabled in the greeter compositor; the generated config defines no keybinds and disables config autoreload.
- Buffered password is cleared on greetd `error`, not only on `authFailure`.
- Password field sets `Qt.ImhHiddenText` so input methods do not record it.
- `systemctl` is called by absolute path.

### Availability

- greetd drop-in uses `ExecStartPre=-…`: a failing profile synchroniser costs the wallpaper, never the login screen.
- Installer offers to harden a pre-existing `greeter` account (Arch's sysusers entry gives it `/bin/bash` and `HOME=/`): switch the shell to `nologin` and give it `/var/lib/greeter`. Interactive only, never applied silently; previous values are recorded in the backup and reverted by `caelestia-greeter-restore`.

### greetd integration

- Installer writes `/etc/greetd/greetd.conf`, the file greetd reads first and that package upgrades do not overwrite. 1.0.0 wrote `config.toml`, which greetd ignores when `greetd.conf` exists.
- Installer creates `/etc/pam.d/greetd-greeter` (unless present) so greeter start-up no longer walks `system-auth`; biometric modules there previously made greetd fail with `pam_setcred: PERM_DENIED`.
- systemd drop-in pins `CAELESTIA_GREETER_USER` to the account chosen at install time instead of re-detecting the lowest UID on every boot.
- `greeter` account is added to `video`.
- On an unexpected greeter exit the compositor restarts after 10 s instead of sleeping forever.

### Sessions

- Default Caelestia session starts Hyprland through `uwsm start -e -D Hyprland hyprland.desktop` when `uwsm` is installed; `CAELESTIA_SESSION_UWSM=0` in `/etc/caelestia-greeter/session.env` opts out.
- `caelestia-session --print-command` reports the resolved command; the catalogue hides discovered desktop entries that run the same thing, so Caelestia and `Hyprland (uwsm-managed)` no longer appear twice.
- New `hiddenSessions` config key hides discovered entries by desktop file or display name.
- Greeter keyboard layout follows `/etc/vconsole.conf` instead of a hardcoded `br`.
- `%%` in desktop-entry `Exec` lines is unescaped after field-code removal, per the specification.

### Tooling

- Session/user discovery moved from a QML string literal to `services/catalog.py`.
- `tests/run.sh`: unprivileged syntax and behaviour tests for the profile synchroniser, catalogue and compositor wrapper.
- Removed the stale `packaging/greetd/lumina-greeter-profile.conf`.

## 1.0.0 — 2026-07-28

First official Caelestia Greeter release.

### Interface

- Material Expressive login screen built with QML and Quickshell.
- Clock, date, typography and password interaction aligned with the Caelestia lock screen.
- Animated Google Sans Flex clock using the variable font shipped by Caelestia Shell.
- Material password glyphs, compact-to-expanded password field and Caelestia motion curves.
- Dynamic wallpaper and Material 3 palette synchronisation.
- Brazilian Portuguese and English localisation.
- Responsive multi-monitor rendering, restart and power-off controls.

### Authentication and sessions

- greetd authentication.
- Hyprland greeter compositor session.
- Caelestia/Hyprland desktop-session handoff.
- Optional GNOME Keyring PAM integration.
- Automatic local-user, display-name and avatar detection.

### Installation and recovery

- Interactive bilingual installer.
- Automatic detection of SDDM, GDM, LightDM, greetd, Ly and LXDM.
- Backup of the previous display manager, service state and existing greeter files.
- SDDM configuration, state and active-theme backup when available.
- Safe next-boot switch to greetd without stopping the current graphical session.
- Profile cache synchronisation for wallpaper, palette, Shell configuration, avatar and font.
- `caelestia-greeter-restore` command for restoring the previous display manager.
