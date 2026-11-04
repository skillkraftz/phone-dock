# phone-dock

Plug in the Samsung and a session starts: new camera files are pulled over adb (md5-verified), scrcpy
mirrors the phone fullscreen on the configured monitor, and a kitty window on the laptop screen shows a menu.

## Layout

| Path | What it is |
|---|---|
| `bin/phone-pull` | CLI: pull new files (`--no-clips`, `--redo-clips`, `--trim [days]`). |
| `bin/phone-session` | Started by the systemd unit on plug-in: starts scrcpy, opens the menu window, ends when the menu quits. |
| `bin/phone` | The menu. Pulls originals first, then lists every file in `actions/`. |
| `lib/phone-lib` | Shared functions and defaults (pull, clips, trim, monitor lookup, scrcpy start/stop). Sourced, never run. |
| `lib/xplace` | X11 helper for XWayland windows: `xplace fullscreen\|move TITLE X Y`. |
| `actions/` | One executable per menu entry. |
| `systemd/phone-pull.service` | User unit; `Type=simple` so a replug can't start a second session. |
| `udev/99-phone-pull.rules` | Starts that unit when the Samsung's adb interface appears. |
| `config.example` | Copy to `~/.config/phone/config`. |

scrcpy runs as its own transient user unit, `phone-scrcpy`, so quitting the menu does not stop it. It exits
by itself when the phone is unplugged. Stop it by hand with `systemctl --user stop phone-scrcpy`.
Logs: `~/.local/state/phone-pull.log`.

## Adding an action

Create an executable file in `actions/`; the number prefix sets menu order:

```bash
#!/usr/bin/env bash
# menu: Title shown in the menu
. "$(dirname "$(readlink -f "$0")")/../lib/phone-lib"
# ...use adb -d, log, say, wait_for_phone, etc.
```

The `# menu:` line is the title. No registration needed.

## Install

```bash
git clone/cd ~/projects/phone-dock
mkdir -p ~/.config/phone && cp config.example ~/.config/phone/config   # then edit it
for n in phone phone-pull phone-session; do ln -s "$PWD/bin/$n" ~/bin/$n; done
systemctl --user link "$PWD/systemd/phone-pull.service"
sudo cp udev/99-phone-pull.rules /etc/udev/rules.d/ && sudo udevadm control --reload
```

The rule runs `systemctl --user -M YOUR_USER@.host start phone-pull.service`; edit the user name for another account.
Needs: adb, scrcpy, kitty, ffmpeg, xwininfo, gdbus, python3 (X11 via XWayland).
