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
| `tests/run-tests.sh` | Offline tests against a fake adb (a directory standing in for the phone) and fake ffmpeg/ffprobe (`tests/fakebin-ff`). No phone, no windows. |
| `config.example` | Copy to `~/.config/phone/config`. |

scrcpy runs as its own transient user unit, `phone-scrcpy`, so quitting the menu does not stop it. It exits
by itself when the phone is unplugged. Stop it by hand with `systemctl --user stop phone-scrcpy`.
Logs: `~/.local/state/phone-pull.log`.

## Clips

A clip is an edit-ready, constant-frame-rate h264/AAC copy of a pulled video, at `$CLIPS/<date>/<name>.mp4` (default `CLIPS=/data/footage/clips`).

**Dating.** The `<date>` is when the recording *started*: taken from the Samsung filename (`YYYYMMDD_HHMMSS`, optionally
with a `-<md5>` or `_N` suffix), because file mtime is when it *ended* (a 23:58 video would land on the next day) and
changes if the phone edits the file. Names that don't parse fall back to mtime. One function, `clip_path` in
`lib/phone-lib`, decides this for both `make_clip` and the menu, so they can't disagree.

**Menu (item 1).** Dates are listed newest first; `1` is the most recent recording date. The newest 14 are shown
(`CLIPS_MENU_DAYS` in the config), with a note of how many older dates are hidden; `a` lists all. Each line shows the number
of videos, how many clips exist and how many are `*.mp4.unverified`. Pick a number (`3`), a range (`3-5`, either order),
a date (`2026-10-01`) or a date range (`2026-10-01..2026-10-05`, either order); numbers and dates also reach hidden dates.
Bad input is rejected with a message and you are asked again; `q` quits. Within a date, videos are made in recording
order. Existing clips are skipped; the summary says how many were made, already done, and failed.

**Transcripts.** Unless `TRANSCRIBE=0` is set in the config, the menu first transcribes the selected originals with
[`stenographr`](https://github.com/skillkraftz/stenographr) (must be on `PATH`; if not, you get one notice and clips
are made as usual). It makes one `stenographr clip` call per date, so the model loads once per date, writing
`$CLIPS/<date>/<name>.md` beside the clip. Originals that already have a transcript are skipped (stenographr allows
one transcript per source file). A failed transcript never blocks the clip; the end of the run prints
`Transcripts: X made, Y already done, Z failed`, and each date line shows how many are transcribed.

## Audio sync

The laptop is the source of truth. Exactly two mappings, and nothing else on the phone is listed, pushed, pulled or deleted:

| Laptop | Phone |
|---|---|
| `$MUSIC_DIR` (default `/data/phone/music/`) | `/sdcard/SdCardBackUp/Music/`, **excluding** its `Audiobooks/` subfolder |
| `$AUDIOBOOKS_DIR` (default `/data/phone/audiobooks/`) | `/sdcard/SdCardBackUp/Music/Audiobooks/` |

Folder structure matches exactly (`music/The Strokes/x.mp3` <-> `SdCardBackUp/Music/The Strokes/x.mp3`). The music side never
touches `Music/Audiobooks/` (it is pruned from the phone listing, and a stray `music/Audiobooks/` on the laptop is ignored).
`/sdcard/Music` and `/sdcard/Audiobooks` are not used. Everything lives under `ROOT` (default `/data/phone`, set in the config).

Menu item 2 (or `actions/20-audio --dry-run` for just the summary) shows a summary first, then:

- in laptop folder, not on phone: pushed (md5-verified)
- on phone, not in laptop folder, in the manifest (`$ROOT/.sync-manifest`): you deleted it on the laptop; deleted from the phone only after you type `yes`
- on phone, not in laptop folder, not in the manifest: new on the phone, pulled (md5-verified)
- same name, different size: reported and left alone

The first run has no manifest, so everything on the phone is imported and nothing can be offered for deletion.
The manifest is rewritten after each run. If a laptop folder is missing while the manifest knows it, the run refuses.

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
sed "s/YOUR_USER/$USER/" udev/99-phone-pull.rules | sudo tee /etc/udev/rules.d/99-phone-pull.rules >/dev/null && sudo udevadm control --reload
```

The rule file holds `YOUR_USER` where the login goes; the `sed` above fills in `$USER`. It then runs `systemctl --user -M $USER@.host start phone-pull.service`.
The systemd unit expects the checkout at `~/projects/phone-dock` (edit `ExecStart` otherwise).
Needs: adb, scrcpy, kitty, ffmpeg, xwininfo, gdbus, python3 (X11 via XWayland).
