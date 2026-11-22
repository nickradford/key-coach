# Menu bar menu

A keyboard icon in the menu bar (accessibility description `Shortcut Coach`) opens a menu with `Show Onboarding…`, a separator, and `Quit Shortcut Coach` (Cmd+Q).

## Sub-features

- `menu-items` the menu lists `Show Onboarding…`, a separator, `Quit Shortcut Coach`.
- `menu-onboarding` `Show Onboarding…` opens the onboarding card, or brings an open one forward.
- `menu-quit` `Quit Shortcut Coach` ends the process.

## How to get to it (user POV)

- Click the keyboard icon in the menu bar and choose an item.

## Driving it with coach.sh

Preconditions:

- Baseline preconditions hold.
- `Q="tell application \"System Events\" to tell (first process whose unix id is $(cat /tmp/shortcut-coach-verify/state/pid)) to"`.

- **List items.** Run `osascript -e "$Q get name of menu items of menu 1 of menu bar item 1 of menu bar 1"`. Output is `Show Onboarding…, missing value, Quit Shortcut Coach`.
- **Show Onboarding.** Run `osascript -e "$Q click menu item \"Show Onboarding…\" of menu 1 of menu bar item 1 of menu bar 1"`, wait 1.5 s, then `coach.sh windows`. A `layer=3 onscreen=true` 560x620 window appears and `osascript -e "$Q get value of static text 1 of group 1 of window 1"` prints `Shortcut Coach`. Close it with `Done` as in [Onboarding](./onboarding.md).
- **Quit.** Run `osascript -e "$Q click menu item \"Quit Shortcut Coach\" of menu 1 of menu bar item 1 of menu bar 1"`, then `ps -p $(cat /tmp/shortcut-coach-verify/state/pid)`. The process is gone. Run `coach.sh stop` afterwards to clear `state/`.
- **Proof.** Save the command output into an evidence dir (`coach.sh shot menu` creates one).

## Gotchas

- The status item has no window in `CGWindowList` on this macOS; it is reachable only through Accessibility (`menu bar 1` of the app's process, not `menu bar 2`).
- Clicking the menu item through AX does not open the menu visually; a screenshot of the menu bar proves nothing. Use the resulting window or process state.
- Quit leaves `state/pid` pointing at a dead pid; `coach.sh doctor` will fail until `stop` and `launch`.
