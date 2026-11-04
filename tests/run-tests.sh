#!/usr/bin/env bash
# Offline tests: fake adb (a directory standing in for the phone), no real phone, no windows.
HERE=$(dirname "$(readlink -f "$0")"); PROJECT=$(dirname "$HERE")
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export FAKE_PHONE=$W/phone FAKE_ADB_LOG=$W/adb.log FAKE_SCRCPY_ARGS=$W/scrcpy.args
export PATH=$HERE/fakebin:$PATH PHONE_CONFIG=$W/config
printf 'ROOT=%s/data/phone\nCLIPS=%s/data/clips\nLOG=%s/phone.log\nSCRCPY_MONITOR_SERIAL=NOPE\nSCRCPY_FALLBACK_CONNECTOR=eDP-1\n' "$W" "$W" "$W" > "$W/config"
SYNC=$W/data/phone/sync; MAN=$W/data/phone/.sync-manifest
mkdir -p "$FAKE_PHONE"/{Audiobooks,Music/x,DCIM/Camera,Download}
pass=0 fail=0
ok()  { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1   [$2]"; fi; }
run() { local in=$1; shift; bash "$PROJECT/actions/20-audio" "$@" <<<"$in" >"$W/out" 2>&1; echo $? >"$W/rc"; }
mk() { mkdir -p "$(dirname "$1")"; head -c "${3:-1000}" /dev/urandom > "$1"; }   # mk path _ size
tree_sum() { (cd "$FAKE_PHONE" && find DCIM Download -type f -exec md5sum {} + | sort | md5sum); }

mk "$FAKE_PHONE/Audiobooks/a.mp3" _ 3000
mk "$FAKE_PHONE/Music/x/y.mp3" _ 2000
mk "$FAKE_PHONE/Music/it's here.mp3" _ 1500
mk "$FAKE_PHONE/DCIM/Camera/pic.jpg" _ 500
mk "$FAKE_PHONE/Download/z.bin" _ 700
OTHER=$(tree_sum)

echo "T1 first run imports the phone into the laptop folders"
run ""
check "exit 0" '[[ $(cat $W/rc) == 0 ]]'
for f in Audiobooks/a.mp3 Music/x/y.mp3 "Music/it's here.mp3"; do
  check "imported $f identical" 'cmp -s "$SYNC/$f" "$FAKE_PHONE/$f"'
  check "$f in manifest" 'grep -qF "$f" "$MAN"'
done
check "phone files all still there" '[[ -e $FAKE_PHONE/Audiobooks/a.mp3 && -e "$FAKE_PHONE/Music/it'"'"'s here.mp3" ]]'
check "nothing offered for deletion on first run" '! grep -q "Type yes" "$W/out"'
check "summary printed with 3 to pull" 'grep -q "to pull (phone -> laptop): 3" "$W/out"'

echo "T2 second run is a no-op"
: > "$FAKE_ADB_LOG"; run ""
check "0 pushed/pulled/deleted" 'grep -q "Audio: 0 pushed, 0 pulled, 0 deleted" "$W/out"'
check "no push/pull/rm issued" '! grep -qE "^(push|pull)|rm " "$FAKE_ADB_LOG"'

echo "T3 new file on laptop is pushed (md5 verified)"
mk "$SYNC/Music/new song.mp3" _ 4000; mk "$SYNC/Audiobooks/sub/b.m4b" _ 5000
run ""
check "pushed 2" 'grep -q "Audio: 2 pushed" "$W/out"'
check "phone copy identical" 'cmp -s "$SYNC/Music/new song.mp3" "$FAKE_PHONE/Music/new song.mp3" && cmp -s "$SYNC/Audiobooks/sub/b.m4b" "$FAKE_PHONE/Audiobooks/sub/b.m4b"'
check "in manifest" 'grep -qF "Music/new song.mp3" "$MAN"'

echo "T4 new file on phone is pulled, never deleted"
mk "$FAKE_PHONE/Music/fromphone.mp3" _ 2500
run ""
check "pulled 1" 'grep -q "Audio: 0 pushed, 1 pulled, 0 deleted" "$W/out"'
check "now on laptop" 'cmp -s "$SYNC/Music/fromphone.mp3" "$FAKE_PHONE/Music/fromphone.mp3"'

echo "T5 --dry-run shows the summary and changes nothing"
rm "$SYNC/Audiobooks/a.mp3"; mk "$SYNC/Music/dry.mp3" _ 100; cp "$MAN" "$W/man.before"; : > "$FAKE_ADB_LOG"
run "yes" --dry-run
check "lists the delete" 'grep -q "Audiobooks/a.mp3" "$W/out" && grep -q "to delete from phone (deleted on laptop): 1" "$W/out"'
check "lists the push" 'grep -q "to push (laptop -> phone): 1" "$W/out"'
check "phone untouched, manifest untouched" '[[ -e $FAKE_PHONE/Audiobooks/a.mp3 && ! -e $FAKE_PHONE/Music/dry.mp3 ]] && cmp -s "$MAN" "$W/man.before"'

echo "T6 laptop deletion: answer no, then yes"
run "no"
check "still on phone after no" '[[ -e $FAKE_PHONE/Audiobooks/a.mp3 ]]'
check "still in manifest after no" 'grep -qF "Audiobooks/a.mp3" "$MAN"'
check "push still happened" 'cmp -s "$SYNC/Music/dry.mp3" "$FAKE_PHONE/Music/dry.mp3"'
run "yes"
check "deleted from phone after yes" '[[ ! -e $FAKE_PHONE/Audiobooks/a.mp3 ]]'
check "other phone files kept" '[[ -e "$FAKE_PHONE/Music/it'"'"'s here.mp3" && -e $FAKE_PHONE/Music/x/y.mp3 ]]'
check "gone from manifest" '! grep -qF "Audiobooks/a.mp3" "$MAN"'
check "laptop never touched by delete" '[[ ! -e $SYNC/Audiobooks/a.mp3 && -e $SYNC/Music/x/y.mp3 ]]'
run ""
check "next run is quiet" 'grep -q "Audio: 0 pushed, 0 pulled, 0 deleted" "$W/out"'

echo "T7 same name, different size: left alone"
mk "$FAKE_PHONE/Music/x/y.mp3" _ 2222; cp "$SYNC/Music/x/y.mp3" "$W/y.laptop"
run ""
check "reported, untouched" 'grep -q "size differs" "$W/out" && cmp -s "$SYNC/Music/x/y.mp3" "$W/y.laptop" && [[ $(stat -c %s $FAKE_PHONE/Music/x/y.mp3) == 2222 ]]'

echo "T8 laptop folder missing but manifest knows it: refuses"
mv "$SYNC/Music" "$W/Music.away"; : > "$FAKE_ADB_LOG"
run "yes"
check "nonzero exit, nothing deleted" '[[ $(cat $W/rc) != 0 ]] && [[ -e $FAKE_PHONE/Music/x/y.mp3 ]] && ! grep -q "rm " "$FAKE_ADB_LOG"'
mv "$W/Music.away" "$SYNC/Music"

echo "T9 scope: nothing outside Audiobooks/Music is touched"
check "DCIM/Download unchanged" '[[ $(tree_sum) == "$OTHER" ]]'
check "every adb shell/push/pull targets /sdcard/Audiobooks or /sdcard/Music" \
  '! grep -E "^(shell|push|pull)" "$FAKE_ADB_LOG" | grep -o "/sdcard[^ \"'"'"']*" | grep -vE "^/sdcard/(Audiobooks|Music)(/|$)"'
check "adb log was non-empty (scope check not vacuous)" '[[ $(grep -cE "^(shell|push|pull)" "$FAKE_ADB_LOG") -gt 5 ]]'

echo "T10 scrcpy gets --stay-awake and never turns the screen off"
(. "$PROJECT/lib/phone-lib"; start_scrcpy) >/dev/null 2>&1
check "--stay-awake passed" 'grep -q -- "--stay-awake" "$FAKE_SCRCPY_ARGS"'
check "no screen-off flags" '! grep -qE -- "--turn-screen-off|--power-off-on-close" "$FAKE_SCRCPY_ARGS"'
check "still fullscreen on eDP-1" 'grep -q -- "--fullscreen" "$FAKE_SCRCPY_ARGS"'

echo; echo "$pass passed, $fail failed"; (( fail == 0 ))
