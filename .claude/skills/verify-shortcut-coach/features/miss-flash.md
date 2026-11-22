# Miss flash

When the user brings a Tinycast-bound app to the front any way other than its hotkey (a click, the Dock, Cmd+Tab, a launcher), a black island drops from the notch for about 1.6 s showing the app's icon, its name and the hotkey as keycaps (`⇪` then the letter for hyper bindings), then retracts.

## Sub-features

- `miss-show` an activation of a bound app with no recent modifiers shows the island on the screen holding that app's window.
- `miss-content` the island shows the app icon, display name, the hyper key glyph and the key letter.
- `miss-retract` the island retracts after about 1.6 s; a newer flash restarts the hold.
- `miss-grace` no flash when the binding's modifiers were held in the last 3 s.
- `miss-quit-hide` no flash when the previous front app quit or hid less than 0.5 s before (macOS chose the next app).
- `miss-unbound` no flash for an app with no Tinycast binding, or for the app already in front.

## How to get to it (user POV)

- Click a bound app's window or Dock icon, or pick it in Cmd+Tab or a launcher.
- Quit or hide the front app (must not flash).
- Press the app's hyper hotkey in Tinycast (must not flash).

## Driving it with coach.sh

Preconditions:

- Baseline preconditions hold and a bound app (for example `md.obsidian`) is installed; it may or may not be running.
- The front app is not that bound app.

- **Bring a bound app forward.** Run `coach.sh miss md.obsidian`. It prints the evidence dir. `steps.txt` shows `front after: md.obsidian`; `windows-during.txt` has one `layer=2147483631 onscreen=true` panel about 296x118 at `y=0`; `island.png` shows the Obsidian icon, `Obsidian`, and keycaps `⇪` and `O` under the notch.
- **Retract.** Same run. `windows-after.txt` (3.2 s after activation) shows every `layer=2147483631` panel `onscreen=false`.
- **Unbound app.** Run `coach.sh miss com.apple.finder` (no Tinycast binding, always running; an app that is not running would be launched and leave a window behind). `windows-during.txt` shows no `onscreen=true` panel.
- **Grace window.** Run `.claude/skills/verify-shortcut-coach/scripts/coach.sh guide 0.3` (holds hyper briefly, too short to show the guide), then within 3 s `coach.sh miss md.obsidian`. `windows-during.txt` of the miss shows no `onscreen=true` panel. If the front app was itself bound, the focus-restore at the end of the miss may flash; that flash is after `windows-after.txt` and not part of the assertion.
- **Quit or hide.** With a bound app in front of another bound app, hide it from its app menu (Cmd+H by the user, or `osascript -e 'tell application "System Events" to set visible of (first process whose bundle identifier is "<front-id>") to false'`), then run `coach.sh shot after-hide` within 0.5 s. The strip shows no island.
- **Proof.** Keep the `miss-md.obsidian` evidence dir and read `island.png`.

## Gotchas

- `miss` restores focus with `open -b <previous front app>`. When that app is bound too (Claude, Dia, Rex here), it flashes once more after the evidence is captured; wait 2 s before the next drive, or the next `windows-before.txt` shows it on screen.
- The flash lands on the screen holding the activated app's frontmost window. On a multi-display setup it may be outside the strip `shot` captures, which is the primary screen's top centre; check `windows-during.txt` coordinates.
- Any hyper chord in the last 3 s suppresses the flash, including one the user pressed during the run.
- The island panel keeps its last bounds after retracting; judge by `onscreen`, not by size.
- The flash decision is deferred 150 ms after activation; sample at least 0.5 s after the action.
