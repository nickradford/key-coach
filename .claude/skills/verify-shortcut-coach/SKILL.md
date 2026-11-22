---
name: verify-shortcut-coach
description: Launch and drive the real Shortcut Coach macOS menu-bar app (Swift package, executable ShortcutCoach) to prove user-visible behavior - the miss flash island, the Caps Lock hold guide with window badges, onboarding, and the menu bar menu - with screenshots and window-list evidence. Use when a change touches Sources/ShortcutCoach or Sources/CoachCore and you need proof beyond `swift test`, or when asked to run, screenshot, or verify the app.
---

# Verify Shortcut Coach

Shortcut Coach is an `LSUIElement`-style menu-bar app (no Dock icon, no main window). Users touch four things: an island that drops from the notch when they bring a Tinycast-bound app forward without its hotkey (miss flash), an island plus window badges while they hold the hyper key (hold guide), a first-launch onboarding panel, and a keyboard icon in the menu bar. `swift test` covers only the decision logic in `CoachCore`; this skill drives the built binary.

Everything goes through one helper, run from the repo root:

    .claude/skills/verify-shortcut-coach/scripts/coach.sh <command>

| Command | Does |
| --- | --- |
| `launch [--onboarding]` | `swift build`, compiles `scripts/probe.swift`, starts `.build/debug/ShortcutCoach` in the background, waits until ready. `--onboarding` shows the onboarding panel; default suppresses it. |
| `doctor` | Read-only health check (below). Exit 0 only when every line is `ok`; the `info` line does not count. |
| `windows` | The instance's windows: `layer=… onscreen=… x y w h` (CG coordinates, top-left origin, points). |
| `dock <bundle-id>` | Clicks that app's Dock icon with real mouse events, captures window lists, the notch strip and the switch the app recorded, gives focus back. Prints the evidence dir. |
| `open <bundle-id>` | Same, but brings the app forward with `open -b`, a switch with no click or key (like a link), after waiting for the keyboard to rest. |
| `guide [seconds]` | Holds hyper (posted modifier flags) for `seconds` (default 3), captures the guide. Prints the evidence dir. |
| `shot <name>` | Captures the top-centre 900x220 pt strip of the primary screen. Prints the file. |
| `stop` | Kills our instance (only if the pid still runs our binary) and removes `state/`. Keeps evidence. |

Paths: `SC_VERIFY_ROOT` (default `/tmp/shortcut-coach-verify`) holds `state/` (pid, rev, source hash, compiled probe, stdout log; removed by `stop`) and `evidence/<timestamp>-<name>/` (never removed by the helper).

## Launch

    .claude/skills/verify-shortcut-coach/scripts/coach.sh launch
    # -> ready pid=<pid> rev=<sha> onboarding=suppressed state=/tmp/shortcut-coach-verify/state

- Ready means the menu bar item's menu (`Show Onboarding…`, `Quit Shortcut Coach`) is readable through Accessibility. On this macOS the status item has no window of its own in `CGWindowList`, so a window check cannot be the ready signal. If not ready in 10 s, launch stops the instance itself and fails.
- `launch` refuses when any `ShortcutCoach` process is already running (the installed copy from `scripts/install.sh` runs as LaunchAgent `local.shortcut-coach`, or a `swift run`). Two instances both draw islands and both flash, so evidence would be ambiguous. Never stop someone else's instance: ask the user to quit it from its menu bar icon (or `launchctl bootout gui/$UID/local.shortcut-coach` with their consent).
- State isolation: the unbundled debug binary reads defaults domain `ShortcutCoach` (the installed app uses `local.shortcut-coach`). `launch` passes `-onboardingCompleted YES|NO` on the command line, which lands in the argument domain and overrides the stored value for this process only. Finishing onboarding still writes `onboardingCompleted = 1` to the `ShortcutCoach` domain; that is the app's real behavior and is harmless.
- There is no "empty data dir": the app's inputs are Tinycast's preferences (`com.abueammar.tinycast`, read live) and the user's running apps and windows. The skill reads them; it never writes Tinycast's preferences.
- Teardown: `coach.sh stop`.

## Doctor

    .claude/skills/verify-shortcut-coach/scripts/coach.sh doctor

Checks, each printed as `ok` or `FAIL`: our pid is alive and runs `.build/debug/ShortcutCoach`; it is the only `ShortcutCoach` process; `HEAD` is the commit it was launched at and the content of `Sources/**/*.swift` is unchanged since the launch build (content hash, since other tools touch mtimes); the menu bar menu is readable; exactly two island panels exist and are hidden (flash + guide, at window layer 2147483631); Tinycast has `hotkey.app.*` bindings; this shell is trusted for Accessibility (needed by `guide` and the onboarding/menu recipes); screen capture returns pixels. An `info` line says whether this shell's app has Input Monitoring, which the instance inherits: with it, only an app's own hotkey is a hit. Run it first, and again whenever anything looks off. A stale-build `FAIL` means rerun `stop` then `launch`.

## Drive

Harnesses, in order of preference:

1. **A real Dock click** for the miss flash: `probe dock <bundle-id>` finds the icon through Accessibility on the Dock process, posts a left mouse down and up at it, then moves the cursor back. Needs Accessibility. `open -b <bundle-id>` brings an app forward with no click or key, which the app treats as a switch the system made: the negative case.
2. **Posted modifier flags** for the hold guide: `probe hyper <s>` posts `flagsChanged` with Control+Option+Shift+Command at the HID tap, exactly what Tinycast posts for hyper, re-posting every 100 ms and always releasing on exit (also on SIGINT/SIGTERM). Needs Accessibility for the calling process.
3. **Accessibility (System Events)** for the menu bar menu and onboarding. Target the process by pid, never by name, so a second copy cannot be clicked by mistake:

       Q="tell application \"System Events\" to tell (first process whose unix id is $(cat /tmp/shortcut-coach-verify/state/pid)) to"
       osascript -e "$Q get name of menu items of menu 1 of menu bar item 1 of menu bar 1"
       # -> Show Onboarding…, missing value, Quit Shortcut Coach

   Onboarding's SwiftUI buttons have **no accessible name** (`PrimaryButton` and `QuietButtonStyle` drop it; AX reports `name = missing value`, `description = button`). Address them by index within `group 1 of window 1`; the primary action is always the last button. Identify the step by `value of static text 1 of group 1 of window 1` (the step title). Do not send keystrokes with `System Events key code`: the accessory app usually is not frontmost, so the key goes to whatever app the user has in front.

Per-feature recipes live in [features/](features/README.md).

## Evidence

Each `dock`/`open`/`guide` run writes `steps.txt` (action, front app before/after, timing), `windows-before.txt`, `windows-during.txt`, `windows-after.txt`, and a PNG of the notch strip into `/tmp/shortcut-coach-verify/evidence/<timestamp>-<name>/`. `dock` and `open` also write `history-last.txt`, the newest switch record, and log `last key-down` in `steps.txt`.

Proof standards:

- Exercise the real user path: click the real Dock icon, post the hyper flags the way Tinycast does, click the real menu and buttons. Never call internal setters, `Flash.demo`, or edit `UserDefaults` to fake a state.
- Capture the action and the resulting state: the before/during/after window lists show the island panel going `onscreen=false -> true -> false` with real bounds; the PNG shows its content (app icon, name, keycaps).
- Read the PNG yourself and state what it shows. A window list without a picture proves a panel appeared, not what it said.
- Screenshots are cropped to the notch strip on purpose: the rest of the user's screen is private. Do not take full-screen captures for evidence unless the feature needs them (badges sit on app windows; their window-list entries are the evidence).
- Side effects: the app writes `onboardingCompleted` (and `hyperKey` when chosen in onboarding) in its defaults domain, and every switch to `~/Library/Application Support/ShortcutCoach/history.json`. Check with `defaults read ShortcutCoach` when a recipe touches onboarding.

## Cleanup

    .claude/skills/verify-shortcut-coach/scripts/coach.sh stop
    ls /tmp/shortcut-coach-verify/evidence   # proof survives

`stop` kills only the pid in `state/pid`, and only if that pid still runs our binary; it never kills by name. It removes `state/` and leaves `evidence/`. Run it after every failed attempt too. If `probe hyper` was interrupted with SIGKILL the modifiers could stay logically down: press and release Control, Option, Shift and Command once to clear them.

## Helpers

- `scripts/coach.sh` (executable) - the commands above.
- `scripts/probe.swift` - compiled by `launch` to `state/probe`. Direct use: `state/probe windows <pid>`, `state/probe hyper <seconds>`, `state/probe strip`, `state/probe front`, `state/probe dock <bundle-id>`, `state/probe listen`, `state/probe keyago`.

## Permissions this skill relies on (never grant them yourself)

- **Accessibility** for the process running the shell (in Claude Code, the responsible app). Without it, `guide` and `dock` exit 3 (`probe: not trusted for Accessibility`) and the AX recipes fail. Ask the user to grant it.
- **Screen Recording** for the same process, for the PNGs. Without it `screencapture` returns only the wallpaper and menu bar; doctor's capture check cannot tell that apart, so look at the image.
- **Input Monitoring**: the debug binary started from a shell inherits the responsible app's grant. When granted, onboarding's permission step reads `Allowed` and the app watches the physical hyper key through IOHID. Posted flags do not pass through IOHID, so `guide` always exercises the modifier-flags path; the physical-key path (including "mouse move while holding hyper does not close the guide") needs a human pressing Caps Lock.
