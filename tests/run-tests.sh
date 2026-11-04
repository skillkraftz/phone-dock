#!/usr/bin/env bash
# Offline tests: fake adb (a directory standing in for the phone), no real phone, no windows.
HERE=$(dirname "$(readlink -f "$0")"); PROJECT=$(dirname "$HERE")
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export FAKE_PHONE=$W/phone FAKE_ADB_LOG=$W/adb.log FAKE_SCRCPY_ARGS=$W/scrcpy.args
export PATH=$HERE/fakebin:$PATH PHONE_CONFIG=$W/config
printf 'ROOT=%s/data/phone\nCLIPS=%s/data/clips\nLOG=%s/phone.log\nSCRCPY_MONITOR_SERIAL=NOPE\nSCRCPY_FALLBACK_CONNECTOR=eDP-1\n' "$W" "$W" "$W" > "$W/config"
R=$W/data/phone; MUS=$R/music; AUD=$R/audiobooks; MAN=$R/.sync-manifest
PM=$FAKE_PHONE/SdCardBackUp/Music            # phone music root; PM/Audiobooks is the audiobooks side
mkdir -p "$PM/The Strokes" "$PM/Audiobooks/Series" "$FAKE_PHONE"/{DCIM/Camera,Download,Music,Audiobooks,SdCardBackUp/Pictures}
pass=0 fail=0
ok()  { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1   [$2]"; fi; }
run()  { local in=$1; shift; : > "$FAKE_ADB_LOG"; bash "$PROJECT/actions/20-audio" "$@" <<<"$in" >"$W/out" 2>&1; echo $? >"$W/rc"; cat "$FAKE_ADB_LOG" >> "$W/all-adb.log"; }
runm() { local in=$1; shift; : > "$FAKE_ADB_LOG"; ( . "$PROJECT/lib/phone-lib"; SYNC_NAMES=(music); sync_audio "$@" ) <<<"$in" >"$W/out" 2>&1; echo $? >"$W/rc"; cat "$FAKE_ADB_LOG" >> "$W/all-adb.log"; }
mk() { mkdir -p "$(dirname "$1")"; head -c "${2:-1000}" /dev/urandom > "$1"; }
# everything on the phone that the sync must never change
outside_sum() { (cd "$FAKE_PHONE" && find DCIM Download Music Audiobooks SdCardBackUp/Pictures -type f -exec md5sum {} + | sort | md5sum); }

mk "$PM/The Strokes/x.mp3" 3000
mk "$PM/it's here.mp3" 1500
mk "$PM/Audiobooks/book.m4b" 6000
mk "$PM/Audiobooks/Series/b2.m4b" 5000
mk "$FAKE_PHONE/DCIM/Camera/pic.jpg" 500
mk "$FAKE_PHONE/Download/z.bin" 700
mk "$FAKE_PHONE/Music/old-decoy.mp3" 800            # /sdcard/Music: must never be touched
mk "$FAKE_PHONE/Audiobooks/old-decoy.m4b" 900       # /sdcard/Audiobooks: must never be touched
mk "$FAKE_PHONE/SdCardBackUp/Pictures/p.jpg" 400    # sibling of SdCardBackUp/Music: must never be touched
OTHER=$(outside_sum)

echo "T1 first run imports the phone into the two laptop folders, structure preserved"
run ""
check "exit 0" '[[ $(cat $W/rc) == 0 ]]'
check "music imported with structure" 'cmp -s "$MUS/The Strokes/x.mp3" "$PM/The Strokes/x.mp3" && cmp -s "$MUS/it'"'"'s here.mp3" "$PM/it'"'"'s here.mp3"'
check "audiobooks imported with structure" 'cmp -s "$AUD/book.m4b" "$PM/Audiobooks/book.m4b" && cmp -s "$AUD/Series/b2.m4b" "$PM/Audiobooks/Series/b2.m4b"'
check "audiobooks NOT in the music folder" '[[ ! -e $MUS/Audiobooks && ! -e $MUS/book.m4b ]]'
check "no /data/phone/sync folder" '[[ ! -e $R/sync ]]'
check "manifest has all 4 with prefixes" '[[ $(grep -c . "$MAN") == 4 ]] && grep -q "^music/The Strokes/x.mp3" "$MAN" && grep -q "^audiobooks/Series/b2.m4b" "$MAN"'
check "nothing offered for deletion" '! grep -q "Type yes" "$W/out"'
check "4 to pull" 'grep -q "to pull (phone -> laptop): 4" "$W/out"'
check "phone files all still there" '[[ -e "$PM/it'"'"'s here.mp3" && -e $PM/Audiobooks/book.m4b ]]'

echo "T2 second run is a no-op"
run ""
check "0 pushed/pulled/deleted" 'grep -q "Audio: 0 pushed, 0 pulled, 0 deleted" "$W/out"'
check "no push/pull/rm issued" '! grep -qE "^(push|pull)|rm " "$FAKE_ADB_LOG"'

echo "T3 new laptop files are pushed to the matching phone folder"
mk "$MUS/The Strokes/new song.mp3" 4000; mk "$MUS/Fresh Artist/Album/t1.mp3" 2100; mk "$AUD/Series/b3.m4b" 5200
run ""
check "pushed 3" 'grep -q "Audio: 3 pushed" "$W/out"'
check "music landed in SdCardBackUp/Music/<same path>" 'cmp -s "$MUS/The Strokes/new song.mp3" "$PM/The Strokes/new song.mp3" && cmp -s "$MUS/Fresh Artist/Album/t1.mp3" "$PM/Fresh Artist/Album/t1.mp3"'
check "audiobook landed in Music/Audiobooks/<same path>" 'cmp -s "$AUD/Series/b3.m4b" "$PM/Audiobooks/Series/b3.m4b"'
check "in manifest" 'grep -qF "music/Fresh Artist/Album/t1.mp3" "$MAN" && grep -qF "audiobooks/Series/b3.m4b" "$MAN"'

echo "T4 new files on the phone are pulled to the right side, never deleted"
mk "$PM/fromphone.mp3" 2500; mk "$PM/Audiobooks/fromphone.m4b" 2600
run ""
check "pulled 2" 'grep -q "Audio: 0 pushed, 2 pulled, 0 deleted" "$W/out"'
check "each on its own side" 'cmp -s "$MUS/fromphone.mp3" "$PM/fromphone.mp3" && cmp -s "$AUD/fromphone.m4b" "$PM/Audiobooks/fromphone.m4b" && [[ ! -e $MUS/fromphone.m4b && ! -e $MUS/Audiobooks ]]'

echo "T5 --dry-run shows the summary and changes nothing"
rm "$MUS/The Strokes/x.mp3" "$AUD/book.m4b"; mk "$MUS/dry.mp3" 100; cp "$MAN" "$W/man.before"
run "yes" --dry-run
check "lists both deletes" 'grep -q "to delete from phone (deleted on laptop): 2" "$W/out" && grep -q "music/The Strokes/x.mp3" "$W/out" && grep -q "audiobooks/book.m4b" "$W/out"'
check "lists the push" 'grep -q "to push (laptop -> phone): 1" "$W/out"'
check "phone and manifest untouched" '[[ -e $PM/The\ Strokes/x.mp3 && -e $PM/Audiobooks/book.m4b && ! -e $PM/dry.mp3 ]] && cmp -s "$MAN" "$W/man.before"'

echo "T6 laptop deletion: answer no, then yes"
run "no"
check "still on phone and in manifest after no" '[[ -e "$PM/The Strokes/x.mp3" && -e $PM/Audiobooks/book.m4b ]] && grep -qF "music/The Strokes/x.mp3" "$MAN" && grep -qF "audiobooks/book.m4b" "$MAN"'
check "push still happened" 'cmp -s "$MUS/dry.mp3" "$PM/dry.mp3"'
run "yes"
check "both deleted from phone" '[[ ! -e "$PM/The Strokes/x.mp3" && ! -e $PM/Audiobooks/book.m4b ]]'
check "siblings kept" '[[ -e "$PM/it'"'"'s here.mp3" && -e $PM/Audiobooks/Series/b2.m4b && -e $PM/Audiobooks/fromphone.m4b ]]'
check "gone from manifest" '! grep -qE "x.mp3|audiobooks/book.m4b" "$MAN"'
check "laptop untouched by delete" '[[ -e $AUD/Series/b2.m4b && -e "$MUS/it'"'"'s here.mp3" ]]'
run ""
check "next run is quiet" 'grep -q "Audio: 0 pushed, 0 pulled, 0 deleted" "$W/out"'

echo "T7 same name, different size: left alone"
mk "$PM/Audiobooks/Series/b2.m4b" 5555; cp "$AUD/Series/b2.m4b" "$W/b2.laptop"
run ""
check "reported, untouched" 'grep -q "size differs" "$W/out" && cmp -s "$AUD/Series/b2.m4b" "$W/b2.laptop" && [[ $(stat -c %s "$PM/Audiobooks/Series/b2.m4b") == 5555 ]]'

echo "T8 laptop folder missing but manifest knows it: refuses"
mv "$MUS" "$W/music.away"
run "yes"
check "nonzero exit, nothing deleted" '[[ $(cat $W/rc) != 0 ]] && [[ -e "$PM/it'"'"'s here.mp3" ]] && ! grep -q "rm " "$FAKE_ADB_LOG"'
mv "$W/music.away" "$MUS"

echo "T9 the music side never touches SdCardBackUp/Music/Audiobooks/"
mk "$MUS/Audiobooks/stray.mp3" 321            # stray folder on the laptop's music side
runm ""
check "stray not pushed into phone Music/Audiobooks" '[[ ! -e $PM/Audiobooks/stray.mp3 && ! -e $PM/stray.mp3 ]]'
check "music-only run: phone listing prunes Audiobooks" 'grep -q -- "-prune" "$FAKE_ADB_LOG"'
check "music-only run: no adb command mentions Music/Audiobooks outside the prune" '! grep -v -- "-prune" "$FAKE_ADB_LOG" | grep -q "Music/Audiobooks"'
check "music-only run: audiobook files not in summary" '! grep -q "audiobooks/" "$W/out"'
rm -rf "$MUS/Audiobooks"
# music-side delete never removes an audiobook, even if the laptop music folder is emptied of that name
mv "$MUS/fromphone.mp3" "$W/fp.mp3"
runm "yes"
check "music delete removed only the music file" '[[ ! -e $PM/fromphone.mp3 && -e $PM/Audiobooks/fromphone.m4b && -e $PM/Audiobooks/Series/b2.m4b ]]'
check "no rm touched Music/Audiobooks" '! grep "rm " "$FAKE_ADB_LOG" | grep -q "Music/Audiobooks"'
mv "$W/fp.mp3" "$MUS/fromphone.mp3"; run ""

echo "T10 scope: nothing outside SdCardBackUp/Music/ is touched"
check "DCIM, Download, /sdcard/Music, /sdcard/Audiobooks, SdCardBackUp/Pictures unchanged" '[[ $(outside_sum) == "$OTHER" ]]'
check "every adb shell/push/pull path is under /sdcard/SdCardBackUp/Music" \
  '! grep -E "^(shell|push|pull)" "$W/all-adb.log" | grep -o "/sdcard[^ \"'"'"']*" | grep -vE "^/sdcard/SdCardBackUp/Music(/|$)"'
check "no /sdcard/Music or /sdcard/Audiobooks anywhere in the log" '! grep -qE "/sdcard/(Music|Audiobooks)" "$W/all-adb.log"'
check "adb log is substantial (scope check not vacuous)" '[[ $(grep -cE "^(shell|push|pull)" "$W/all-adb.log") -gt 30 ]]'
check "nothing created under /data/phone/sync or /data/audio" '[[ ! -e $R/sync ]] && ! grep -rq "/data/audio" "$PROJECT/lib" "$PROJECT/actions" "$PROJECT/bin"'

echo "T11 scrcpy gets --stay-awake and never turns the screen off"
(. "$PROJECT/lib/phone-lib"; start_scrcpy) >/dev/null 2>&1
check "--stay-awake passed" 'grep -q -- "--stay-awake" "$FAKE_SCRCPY_ARGS"'
check "no screen-off flags" '! grep -qE -- "--turn-screen-off|--power-off-on-close" "$FAKE_SCRCPY_ARGS"'
check "still fullscreen" 'grep -q -- "--fullscreen" "$FAKE_SCRCPY_ARGS"'

echo; echo "$pass passed, $fail failed"; (( fail == 0 ))
