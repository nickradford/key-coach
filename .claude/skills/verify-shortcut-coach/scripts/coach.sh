#!/bin/bash
# Launch, inspect, drive and tear down one verification instance of Shortcut Coach.
# Usage: coach.sh launch [--onboarding] | doctor | windows | miss <bundle-id> | guide [seconds]
#                 | shot <name> | stop
set -euo pipefail
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
root="${SC_VERIFY_ROOT:-/tmp/shortcut-coach-verify}"
state="$root/state"          # removed by stop
evidence_root="$root/evidence"  # never removed by this script
bin="$repo/.build/debug/ShortcutCoach"
probe="$state/probe"

die() { echo "coach: $*" >&2; exit 1; }
pid() { cat "$state/pid" 2>/dev/null || die "no instance; run: coach.sh launch"; }
ours() { local p; p=$(pid); [ "$(ps -o comm= -p "$p" 2>/dev/null)" = "$bin" ]; }
# Every ShortcutCoach process, ours or not (the installed LaunchAgent copy, a swift run).
all_coaches() { pgrep -x ShortcutCoach || true; }
evdir() { local d; d="$evidence_root/$(date +%Y%m%d-%H%M%S)-$1"; mkdir -p "$d"; echo "$d"; }
# The menu bar item's menu, read through Accessibility. On this macOS the status item has no
# window of its own in the window list, so this is the readiness signal.
menu_ready() { [ "$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $(pid)) to exists menu item \"Show Onboarding…\" of menu 1 of menu bar item 1 of menu bar 1" 2>/dev/null)" = true ]; }
src_hash() { find "$repo/Sources" -name '*.swift' -print0 | sort -z | xargs -0 shasum | shasum | cut -d' ' -f1; }
shot_to() { screencapture -x -R "$("$probe" strip)" "$1"; }

cmd="${1:-}"; shift || true
case "$cmd" in
launch)
    onboarding=YES
    [ "${1:-}" = "--onboarding" ] && onboarding=NO
    [ -z "$(all_coaches)" ] || die "a ShortcutCoach is already running (pids: $(all_coaches | xargs)); two instances both draw islands. Quit it from its menu bar icon, or run coach.sh stop if it is ours."
    mkdir -p "$state" "$evidence_root"
    (cd "$repo" && swift build 2>&1 | tail -1)
    swiftc -O -o "$probe" "$repo/.claude/skills/verify-shortcut-coach/scripts/probe.swift"
    git -C "$repo" rev-parse --short HEAD > "$state/rev"
    src_hash > "$state/src"  # content, not mtime: other tools touch files without changing them
    # -key value args land in the argument domain: they override the dev binary's defaults
    # (domain "ShortcutCoach") for this process without rewriting them.
    nohup "$bin" -onboardingCompleted "$onboarding" > "$state/stdout.log" 2>&1 &
    echo $! > "$state/pid"
    for _ in $(seq 50); do
        menu_ready && { echo "ready pid=$(pid) rev=$(cat "$state/rev") onboarding=$([ $onboarding = NO ] && echo shown || echo suppressed) state=$state"; exit 0; }
        sleep 0.2
    done
    "$0" stop >/dev/null  # do not strand a half-started instance
    die "no menu bar item after 10 s; instance stopped. Its log was in $state/stdout.log (removed); rerun to inspect."
    ;;
doctor)
    ok=1
    check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; ok=0; fi; }
    check "instance pid $(pid) is alive and runs $bin" ours
    check "only one ShortcutCoach process" '[ "$(all_coaches | xargs)" = "$(pid)" ]'
    check "launched at HEAD ($(cat "$state/rev")) and Sources/ unchanged since the launch build" '[ "$(cat "$state/rev")" = "$(git -C "$repo" rev-parse --short HEAD)" ] && [ "$(cat "$state/src")" = "$(src_hash)" ]'
    check "menu bar item has Show Onboarding… and Quit (via Accessibility)" menu_ready
    check "two island panels exist (flash + guide), both hidden" '[ "$("$probe" windows "$(pid)" | grep -c "^layer=2147483631 onscreen=false")" = 2 ]'
    check "Tinycast has app bindings" 'defaults read com.abueammar.tinycast 2>/dev/null | grep -c hotkey.app. >/dev/null'
    check "this shell is trusted for Accessibility (needed by: guide)" 'osascript -l JavaScript -e "ObjC.import(\"ApplicationServices\"); \$.AXIsProcessTrusted()" | grep -c true >/dev/null'
    check "screen capture returns pixels" '(f=$(mktemp -t sc).png; screencapture -x -R 0,0,10,10 "$f" && [ -s "$f" ]; r=$?; rm -f "$f"; exit $r)'
    [ $ok = 1 ]
    ;;
windows)
    "$probe" windows "$(pid)"
    ;;
miss)
    id="${1:?bundle id of a Tinycast-bound app}"
    ours || die "instance is not ours or not running"
    d=$(evdir "miss-$id")
    prev=$("$probe" front)
    echo "front before: $prev" > "$d/steps.txt"
    "$probe" windows "$(pid)" > "$d/windows-before.txt"
    open -b "$id"; echo "action: open -b $id (Launch Services activation, like a Dock click)" >> "$d/steps.txt"
    sleep 0.7
    echo "front after: $("$probe" front)" >> "$d/steps.txt"
    "$probe" windows "$(pid)" > "$d/windows-during.txt"
    shot_to "$d/island.png"
    sleep 2.5
    "$probe" windows "$(pid)" > "$d/windows-after.txt"
    [ -n "$prev" ] && open -b "$prev"  # give focus back; if $prev is bound this flashes once more
    echo "$d"
    ;;
guide)
    secs="${1:-3}"
    ours || die "instance is not ours or not running"
    sleep 2  # let any earlier flash retract, so "during" shows only the guide
    d=$(evdir guide)
    "$probe" windows "$(pid)" > "$d/windows-before.txt"
    "$probe" hyper "$secs" & hp=$!
    echo "action: probe hyper $secs (ctrl+opt+shift+cmd posted as modifier flags, as Tinycast does)" > "$d/steps.txt"
    # Wait for the guide rather than a fixed sleep: the 0.7 s hold delay plus a freshly built
    # probe's first-run launch delay. Island + one badge per visible bound window = 1+ on screen.
    for i in $(seq 20); do
        sleep 0.2
        # grep -c, not grep -q: an early-exiting grep SIGPIPEs the writer and pipefail reports failure.
        [ "$("$probe" windows "$(pid)" | grep -c "onscreen=true")" -gt 0 ] && { echo "guide on screen after ~$((i * 200)) ms" >> "$d/steps.txt"; break; }
    done
    sleep 0.4  # entrance animation
    "$probe" windows "$(pid)" > "$d/windows-during.txt"
    shot_to "$d/guide.png"
    wait $hp || die "probe hyper failed (exit $?); see stderr above"
    sleep 1
    "$probe" windows "$(pid)" > "$d/windows-after.txt"
    echo "$d"
    ;;
shot)
    d=$(evdir "shot-${1:?name}"); shot_to "$d/strip.png"; echo "$d/strip.png"
    ;;
stop)
    if [ -f "$state/pid" ]; then
        if ours; then kill "$(pid)"; echo "stopped pid $(pid)"; else echo "pid $(pid) is not ours; left alone"; fi
    fi
    rm -rf "$state"
    echo "evidence kept in $evidence_root"
    ;;
*)
    sed -n '2,4p' "$0"; exit 2
    ;;
esac
