---
name: model-check-hyper-hold
description: "TLA+ model check of the hyper-key path in Shortcut Coach: HyperKeyListener key events, the 30 Hz Coach poll, HoldTracker (hold guide) and the miss decision in Coach.appActivated. Use when a change touches Signal.swift (heldModifiers, hyperHeld, HyperKeyListener, lastKeyDownAt), Coach.swift (poll, sampleModifiers, appActivated, the click monitor), or HoldTracker / missedBinding / switchOutcome in Decisions.swift, or when asked whether the guide or the miss flash can misfire."
---

# Model-check the hyper hold

`HyperHold.tla` (next to this file) is a small TLA+ model of how the hyper key's and the hotkey letter's events, the poll timer and app-activation notifications interleave on the main run loop. TLC checks every order of those events, up to the bounds below, against five promises:

| Property | Plain sentence | Harm if broken |
| --- | --- | --- |
| `HotkeyNeverFlashes` | A switch made with the hyper hotkey never flashes a miss. | The coach scolds you for doing the right thing. |
| `SystemSwitchNeverFlashes` | A switch the system made (a link, a notification), with no key or click of yours before it, never flashes a miss. | The coach scolds you for something you did not do. |
| `GuideHidesAfterRelease` | Once the key is up and a poll has seen that, the guide is hidden. | The guide sticks on screen over your work. |
| `GuideShowsOnLongHold` | Holding hyper past the delay shows the guide, unless a bound app activated during this hold. | You hesitate, hold the key, and get no help. |
| `GuideStaysHiddenAfterActivation` | After a bound app activates during a hold, the guide stays hidden until release, from the first poll once the listener has caught up. | The guide pops up over the app you just switched to. |

`TypeOK` is a sanity check on the model itself.

## Run

```sh
.claude/skills/model-check-hyper-hold/check.sh            # all properties, about 5 s
.claude/skills/model-check-hyper-hold/check.sh GuideHidesAfterRelease   # one property
```

Needs Java 11+ (`java -version`) and the TLA+ tools 1.7.4 jar at `~/.local/share/tlaplus/tla2tools-1.7.4.jar` (sha256 `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`). If missing, the script prints this one-time install:

```sh
mkdir -p ~/.local/share/tlaplus && curl -fsSL -o ~/.local/share/tlaplus/tla2tools-1.7.4.jar https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
```

Set `TLA2TOOLS=/path/to/tla2tools.jar` to use another copy.

Output is one `== Property: result` line each. Exit 0 means every result matches the baseline: the properties in `known=` in `check.sh` fail (the findings below), the rest pass. `FAIL (NEW)` or `known finding no longer reproduces` exits 1.

Read every result, pass or fail, with the pstack `/statechart` skill (in Claude Code, read the pstack plugin's `skills/statechart/SKILL.md`): give it `HyperHold.tla` and a config listing the properties as INVARIANTs with `MaxPresses = 2` and `DelayPolls = 2`. It tells each violation as its shortest path in plain words, and charts the states when the check passes. Point it at the jar above with the `TLA2TOOLS` environment variable.

## Bounds and assumptions

- `MaxPresses = 2` (two presses of the hyper key), one bound-app activation per run (by hotkey, by a click on the Dock or the app, or by the system), `DelayPolls = 2` stands in for `HoldTracker.delay` (21 ticks of the 1/30 s timer in the app; only "at least one tick" matters to the logic). About 6,800 states.
- The code compares times and never counts them, so the model keeps only their order: whether the activation came at or after `pressedAt`, and at or after `HoldTracker.heldSince`; whether `lastPress`, the last key-down and the last click came at or before the activation.
- No timing: a poll can run between any two events, or not at all. That matches the code, which does nothing to force a poll between two run-loop callbacks; in the app a gap with no poll needs a hold shorter than one tick (33 ms) or a main-thread stall that queues the events, since IOHIDManager drains its queued values in one run-loop pass.
- `DecideMiss` runs only after every HID value that was already waiting when `appActivated` ran (`hidAhead`), the hotkey letter included, and after the click monitor's callback for a click before the activation. The run loop handles those well inside the Task's 150 ms sleep. A main-thread stall of more than 150 ms right after `appActivated` breaks this. Without this assumption the model finds the hotkey flash again.
- Input Monitoring is granted and the listener is open, so `missedBinding` takes a hit only from `lastPress` (exact mode) and never reads `lastHeld`. One physical hyper key; the hyper key choice does not change. No quit or hide; the bound app was not already in front. No input ages past `graceSeconds`. The hyper key alone is not a key-down (Caps Lock is a modifier event; with F18 it would be, which only makes a switch look chosen).

## What each model step is in the code

Each main-thread action is one main-actor callback, so it is indivisible in the code as in the model.

| Model action | Code |
| --- | --- |
| `HidCallback` | For the hyper key, `HyperKeyListener.handle(_:down:at:)`: sets `isDown`, and on a key-down `pressedAt` = the HID value's own timestamp (`IOHIDValueGetTimeStamp`, mach absolute time, the same clock as `systemUptime`), so a value that was waiting when `appActivated` ran counts as pressed before it. For the letter, `HyperKeyListener.handleKeyDown(_:at:)`: `classifyKey` against `heldModifiers()` as it is when the callback runs, and `lastPress` keeps the value's own timestamp. Both run on the main run loop from the callback in `HyperKeyListener.open()` (`Sources/ShortcutCoach/Signal.swift`) |
| `Poll` | `Coach.poll()`: `sampleModifiers()`, which also folds `pressedAt` into `lastHeld`, then `HoldTracker.update(hyperHeld:pressedAt:now:)` with `pressedAt` only while `isDown` (`Coach.swift`, `Sources/CoachCore/Decisions.swift`); `guideVisible` is `Coach.guideVisible`, which drives `Guide.show/hide` in `main.swift` |
| `Held` | `heldModifiers() == hyperModifiers`: `isDown`, else the posted flags (`Signal.swift`) |
| `AppActivated` | the synchronous part of `Coach.appActivated`: `tracker.boundAppActivated(now:)`, with `now` the activation time the decision compares against |
| `DecideMiss` | the `Task` in `Coach.appActivated`, 150 ms later: `missedBinding` (through `switchOutcome`) with `listening`, `lastPress`, `lastKeyDownAt()` and `Coach.lastClick` as they are then: a hit is `lastPress` on the app's own key at or before the activation; otherwise it flashes only if a key went down, or a click landed on the Dock or the app, at or before it (`Sources/CoachCore/Decisions.swift`) |
| `UserPressesHyper`, `UserReleasesHyper`, `UserMovesMouse`, `UserUsesHotkey`, `UserClicksBoundApp`, `SystemBringsBoundApp` | outside the app: the key, Tinycast's posted flags (a mouse move clears them), the letter (its HID value, and its key-down in the HID system state that `lastKeyDownAt` reads) with Tinycast switching on hyper + letter, a click on the Dock or the app (kept by the click monitor), a link or notification |

## Findings (current code)

None. Both earlier findings are fixed:

1. `HotkeyNeverFlashes`: a hotkey switch flashed a miss when the key-down callback ran after `appActivated` and the posted flags were already clear. The fix then was `pressedAt` folded into `lastHeld`, read when the decision runs. With Input Monitoring the hit now comes from the letter instead: `lastPress` keeps the letter's own HID timestamp, `classifyKey` reads `isDown` before the flags, and the decision reads `lastPress` when it runs.
2. `GuideShowsOnLongHold`: a bound app activating while hyper was up, or a release and press between two polls, kept the guide hidden for a whole hold. `HoldTracker` now keeps the activation time and blocks only when the activation is at or after the hold's start, which is `pressedAt` while the listener sees the key down.

`GuideHidesAfterRelease` holds: the listener is event-driven, so the last key event always wins.

## Is a failure a bug or a modeling error?

Before you trust a new counterexample, replay it against the real code, one model step per code step. For `HoldTracker` and `missedBinding`, a throwaway Swift Testing test in `Tests/CoachCoreTests` does it (`swift test --filter <name>`); delete it after. If the path cannot happen in the code (the model allows an event the code rules out, or merges two callbacks the code runs separately), the model is wrong: fix the model, never the property. If it can happen, it is a finding: report it with the path in code terms and do not change product code unless asked.

## When the covered code changes

1. Check whether the change touches anything in the Coverage list. If not, nothing to do.
2. Change `HyperHold.tla` so each action still matches its code in the table above (for example, a new reset in `HoldTracker.update` goes into `Poll`; a new queue or timer becomes a new action).
3. Run `check.sh`. A property that newly fails is a finding until a replay says otherwise. If a change fixes a finding, take the property out of `known=` in `check.sh` and out of Findings here, together.
4. Only after you have confirmed the model describes the code at the new commit, move the sync commit below to it.

## Coverage

Last confirmed in step with the code at commit `bc7b324649715592f039aace2b2504a5b68e7d0f`.

- `Sources/ShortcutCoach/Signal.swift`: `heldModifiers`, `hyperHeld`, `lastKeyDownAt`, `HyperKeyListener.handle`, `HyperKeyListener.handleKeyDown`, `isListening`, the input-value callback and main run-loop scheduling in `HyperKeyListener.open`.
- `Sources/ShortcutCoach/Coach.swift`: `start` (the 1/30 s timer, the click monitor), `sampleModifiers`, `poll`, `appActivated` (synchronous part and the 150 ms `Task`).
- `Sources/CoachCore/Decisions.swift`: `HoldTracker` (all), `missedBinding` and `switchOutcome` with Input Monitoring (the exact hit through `switchMethod`, and `userChose`).
- `Sources/ShortcutCoach/main.swift`: `coach.onGuide` wiring to `Guide.show/hide`.

`git diff bc7b324649715592f039aace2b2504a5b68e7d0f -- Sources/ShortcutCoach/Signal.swift Sources/ShortcutCoach/Coach.swift Sources/CoachCore/Decisions.swift Sources/ShortcutCoach/main.swift` shows what changed since.

## Not covered

Key presses other than the hotkey letter (another binding, Command-Tab, "not a hotkey") and the switch history (`HistoryFile`, recorded in the same `Task` as the miss decision). Which app a click landed on (`windowOwner`) and when, beyond "on the Dock or the app, before the activation". The modifier-only rule without Input Monitoring (`lastHeld`). Changing the hyper key (`refreshHyperKey`, onboarding `capture`), lost key-ups (keyboard unplugged or sleep while held, Input Monitoring revoked), two keyboards or Caps Lock and F18 both reporting, the no-permission path beyond the flags reset by a mouse move, quit/hide suppression and `previousFrontmost`, binding parsing, real timing (grace expiry, the 0.7 s delay as time), and everything the guide and flash draw.

The miss promises are checked in one direction only. No property says that a real miss flashes, and by design another hotkey pressed in the 150 ms before the decision replaces `lastPress`. `GuideStaysHiddenAfterActivation` fails if `pressedAt` is stamped when the callback runs instead of from the HID value (replace `actSincePress' = (hidAhead > 0)` with `FALSE` in `HidCallback` to see it). `HotkeyNeverFlashes` fails if the letter is stamped when its callback runs (replace `pressBound' = Held` with `pressBound' = (Held /\ activation \in {"none", "queued"})`), if it is classified against the posted flags alone (`pressBound' = flagsHyper`), or if the decision does not wait for queued HID values (drop `/\ hidAhead = 0` from `DecideMiss`). `SystemSwitchNeverFlashes` fails without the user-chose condition (`flashed' = ~pressBound`).
