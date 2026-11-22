# Miss flash

When the user brings a Tinycast-bound app to the front any way other than its hotkey (a click on the Dock or the app's window, Cmd+Tab, a launcher), a black island drops from the notch for about 1.6 s showing the app's icon, its name and the hotkey as keycaps (`⇪` then the letter for hyper bindings), then retracts. A switch the system made (a link, a notification) never flashes. Each switch is also recorded in the history file with its outcome.

## Sub-features

- `miss-show` a bound app the user brought forward without its hotkey shows the island on the screen holding that app's window, and records `miss`.
- `miss-content` the island shows the app icon, display name, the hyper key glyph and the key letter.
- `miss-retract` the island retracts after about 1.6 s; a newer flash restarts the hold.
- `miss-exact` with Input Monitoring, only the app's own hotkey in the last 3 s is a hit: hyper alone, or another app's hotkey, then a click still flashes.
- `miss-grace` without Input Monitoring, no flash when the binding's modifiers were held in the last 3 s.
- `miss-system` no flash when, in the 3 s before, no key went down and no click landed on the Dock, Stage Manager or the app: a link, a notification, `open -b`. Recorded as `system`.
- `miss-quit-hide` no flash when the previous front app quit or hid less than 0.5 s before (macOS chose the next app).
- `miss-unbound` no flash for an app with no Tinycast binding (recorded `unbound`), or for the app already in front.

## How to get to it (user POV)

- Click a bound app's Dock icon or window, or pick it in Cmd+Tab or a launcher.
- Press another app's hotkey, then click the bound app (must flash with Input Monitoring).
- Open a link or click a notification that brings a bound app forward (must not flash).
- Quit or hide the front app (must not flash).
- Press the app's hyper hotkey in Tinycast (must not flash).

## Driving it with coach.sh

Preconditions:

- Baseline preconditions hold and a bound app (for example `md.obsidian`) is running and has a Dock icon.
- The front app is not that bound app.
- `coach.sh doctor` prints the `info Input Monitoring` line. The expected results below say where they depend on it.

- **Bring a bound app forward.** Run `coach.sh dock md.obsidian`: a real left click on its Dock icon, then the cursor goes back. It prints the evidence dir. `steps.txt` shows `front after: md.obsidian`; `windows-during.txt` has one `layer=2147483631 onscreen=true` panel about 296x118 at `y=0`; `island.png` shows the Obsidian icon, `Obsidian`, and keycaps `⇪` and `O` under the notch; `history-last.txt` has `"outcome":"miss"` for `md.obsidian`.
- **Retract.** Same run. `windows-after.txt` (3.2 s after activation) shows every `layer=2147483631` panel `onscreen=false`.
- **System-made switch.** Run `coach.sh open md.obsidian` (`open -b`: no click, no key, like a link). It first waits for 4 s with no key down. `steps.txt` shows `last key-down` above 3 s; `windows-during.txt` shows no `onscreen=true` panel; `history-last.txt` has `"outcome":"system"`.
- **Unbound app.** Run `coach.sh dock com.apple.finder` (no Tinycast binding, always running). `windows-during.txt` shows no `onscreen=true` panel; `history-last.txt` has `"outcome":"unbound"`. With no Finder window open, the click opens one; close it afterwards.
- **Hyper alone is not the hotkey.** Run `/tmp/shortcut-coach-verify/state/probe hyper 0.3; coach.sh dock md.obsidian`. Call the probe directly: `coach.sh guide 0.3` waits about 4 s for a guide that never shows, which puts the click outside the 3 s window. With Input Monitoring granted, it flashes and records `miss`. Without it, the posted hyper flags count (`miss-grace`): no flash, and `hit`.
- **Quit or hide.** With a bound app in front of another bound app, hide it from its app menu (Cmd+H by the user, or `osascript -e 'tell application "System Events" to set visible of (first process whose bundle identifier is "<front-id>") to false'`), then run `coach.sh shot after-hide` within 0.5 s. The strip shows no island.
- **Proof.** Keep the `dock-md.obsidian` and `open-md.obsidian` evidence dirs, read `island.png` and `history-last.txt`.

## Gotchas

- A real hyper + letter cannot be posted at HID level, so `miss-exact`'s hit side (the app's own hotkey does not flash) needs a human pressing it. The posted hyper flags never reach the listener.
- Any key the user types in the 3 s before an `open` makes that switch theirs, so it flashes and records `miss`. `steps.txt` records `last key-down`; rerun when it is under 3 s.
- `dock` posts real mouse events and needs Accessibility for the shell. With an auto-hidden Dock it first rests the cursor on the screen edge, then clicks once the icon is on screen. It assumes the Dock is on the main display.
- Both commands give focus back with `open -b <previous front app>`. That is a system-made switch, so it does not flash unless the user typed in the 3 s before.
- The flash lands on the screen holding the activated app's frontmost window. On a multi-display setup it may be outside the strip `shot` captures, which is the primary screen's top centre; check `windows-during.txt` coordinates.
- `history-last.txt` is the newest record in `~/Library/Application Support/ShortcutCoach/history.json` (the debug binary's folder). A switch the user makes during the run lands there too; check its `bundleID`.
- The island panel keeps its last bounds after retracting; judge by `onscreen`, not by size.
- The flash decision is deferred 150 ms after activation; sample at least 0.5 s after the action.
