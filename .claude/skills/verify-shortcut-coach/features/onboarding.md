# Onboarding

On first launch (and from the menu's `Show Onboarding…`) a floating card walks through six steps: `Shortcut Coach` (welcome), `Tinycast` (bindings found), `Input Monitoring` (permission), `Hyper key` (which key is hyper), `Try it` (hold the key, or `Show Me` a sample miss), and `You're set`. Closing at any step marks onboarding done.

## Sub-features

- `onb-first-launch` the card appears when `onboardingCompleted` is false.
- `onb-steps` the primary button advances through all six steps; `Back` returns.
- `onb-tinycast` the Tinycast step reports the number of app shortcuts found.
- `onb-permission` the Input Monitoring step shows `Allowed` when granted, else `Allow` and `Skip`.
- `onb-hyper` the Hyper key step names Tinycast's key when Tinycast sets one, else lets the user press their key.
- `onb-demo` `Show Me` on the Try it step shows a sample miss flash.
- `onb-close` `Done` (or Esc) closes the card and writes `onboardingCompleted = 1`.

## How to get to it (user POV)

- Launch the app for the first time.
- Choose `Show Onboarding…` from the keyboard icon's menu.

## Driving it with coach.sh

Preconditions:

- Baseline preconditions hold, launched with `coach.sh launch --onboarding`.
- `Q="tell application \"System Events\" to tell (first process whose unix id is $(cat /tmp/shortcut-coach-verify/state/pid)) to"`.

- **First launch.** After `launch --onboarding`, run `coach.sh windows`. A `layer=3 onscreen=true` window about 560x620 is present. `osascript -e "$Q get value of static text 1 of group 1 of window 1"` prints `Shortcut Coach`.
- **Advance.** Click the last button: `osascript -e "$Q click button (count buttons of group 1 of window 1) of group 1 of window 1"`. Repeat, reading the title after each click. Titles in order: `Shortcut Coach`, `Tinycast`, `Input Monitoring`, `Hyper key`, `Try it`, `You're set`.
- **Tinycast step.** `osascript -e "$Q get value of static texts of group 1 of window 1"` includes `Found <n> app shortcuts in Tinycast.` where `<n>` is the count of `hotkey.app.*` keys.
- **Permission step.** The texts include `Allowed` and there are 2 buttons when granted. With 3 buttons it is not granted: click button 2 (`Skip`), never the last (`Allow` opens the system prompt).
- **Hyper key step.** With Tinycast's `hyperKeyPhysicalKey = capsLock`, texts include `Tinycast uses Caps Lock as your hyper key.` and `⇪`.
- **Try it step.** The step has 3 buttons: 1 `Show Me`, 2 `Back`, 3 `Continue`. Click button 1 (`osascript -e "$Q click button 1 of group 1 of window 1"`), wait 0.6 s and run `coach.sh shot onboarding-demo`: the strip shows a sample island for the first hyper binding by bundle id (here `Claude` with keycaps `⇪` `C`), and `coach.sh windows` shows the flash panel `onscreen=true`. Running `coach.sh guide` while this step shows should tick off `Hold ⇪ for a moment` (not yet verified by a run).
- **Close.** On `You're set`, click the last button (`Done`). `coach.sh windows` shows the `layer=3` window `onscreen=false` (or no longer lists it) and `defaults read ShortcutCoach onboardingCompleted` prints `1`.
- **Proof.** Save the title sequence and the before/after `coach.sh windows` output into the run's evidence dir (`coach.sh shot onboarding` creates one).

## Gotchas

- Buttons have no accessible names (`name` is `missing value`), so indexes are the only handle. Order is step-content buttons first (only `Show Me` on Try it), then `Back` (absent on the welcome step), then the step's actions (`Skip` before `Allow`/`Open System Settings` on an ungranted permission step, else the single primary). The primary is always last. Re-read the count before clicking.
- Never press Esc through `System Events key code 53`: the app is an accessory app and usually not frontmost, so Esc goes to the user's front app. Close with `Done`.
- The card lives on the active Space at `.floating` level; screenshots of it would include the user's screen around it, so prefer AX text for proof.
- The `ShortcutCoach` defaults domain is shared with `swift run`. `launch --onboarding` overrides it through the argument domain; it does not reset it.
- The step changes are animated; wait about 1 s after each click before reading.
