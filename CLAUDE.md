# phone-dock

Bash (plus small python helpers) that drives an Android phone over adb: on plug-in it pulls new camera files
(md5-verified), mirrors the screen with scrcpy, and shows a menu for clips, audio sync and trimming.

## Layout
| Path | What it is |
|---|---|
| `bin/phone-pull` | CLI: pull new files (`--no-clips`, `--redo-clips`, `--trim [days]`) |
| `bin/phone-session` | Started by systemd on plug-in: scrcpy + menu window |
| `bin/phone` | The menu; pulls first, then lists `actions/*` |
| `lib/phone-lib` | All shared logic and defaults (pull, clips, trim, audio sync, scrcpy). Sourced, never run |
| `lib/xplace` | X11 window helper |
| `actions/NN-name` | One executable per menu entry; `# menu:` line is the title |
| `tests/` | `run-tests.sh`; fakes in `fakebin/` (adb, systemd-run, ...) and `fakebin-ff/` (ffmpeg, ffprobe) |
| `systemd/`, `udev/` | Session unit and the udev rule that starts it |

## Tests
`bash tests/run-tests.sh` (offline, takes seconds, ~75 checks). Add a section per behaviour; new checks must
fail on the code they guard (run them against the previous commit in a `git worktree`).
Set fake mtimes through epoch (`settime`), not `touch -d "local time"`: uutils touch reads that as UTC.

## Hard rules
- Tests never touch the real phone, `/data/phone` or `/data/footage`. Everything goes through the fakes and a temp dir.
- Phone files are deleted only after the user types `yes` (trim and audio sync). Local files are never deleted by the code.
- Audio sync scope is `/sdcard/SdCardBackUp/Music` only (Audiobooks is a subfolder with its own mapping). The laptop is the source of truth.
- Phone paths in `adb shell` strings go through `shq`.
- Clip dates come from `clip_path`/`clip_stamp` only; don't re-derive them from mtime elsewhere.
- `pull_new` is a subshell function so its lock on fd 9 is released on return; keep it that way.

## Style and commits
Terse bash, comments say why not what. Commit subjects are imperative and descriptive; body explains the
reason and what was verified. Don't commit unless asked.
