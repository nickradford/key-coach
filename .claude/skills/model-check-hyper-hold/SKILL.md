---
name: model-check-hyper-hold
description: "TLA+ model check of the hyper-key path in Shortcut Coach: HyperKeyListener key events, the 30 Hz Coach poll, HoldTracker (hold guide) and the miss decision in Coach.appActivated. Use when a change touches Signal.swift (heldModifiers, hyperHeld, HyperKeyListener), Coach.swift (poll, sampleModifiers, appActivated), or HoldTracker / missedBinding in Decisions.swift, or when asked whether the guide or the miss flash can misfire."
---

# Model-check the hyper hold

`HyperHold.tla` (next to this file) is a small TLA+ model of how the hyper key's events, the poll timer and app-activation notifications interleave on the main run loop. TLC checks every order of those events, up to the bounds below, against three promises:

| Property | Plain sentence | Harm if broken |
| --- | --- | --- |
| `HotkeyNeverFlashes` | A switch made with the hyper hotkey never flashes a miss. | The coach scolds you for doing the right thing. |
| `GuideHidesAfterRelease` | Once the key is up and a poll has seen that, the guide is hidden. | The guide sticks on screen over your work. |
| `GuideShowsOnLongHold` | Holding hyper past the delay shows the guide, unless a bound app activated during this hold. | You hesitate, hold the key, and get no help. |

`TypeOK` is a sanity check on the model itself.

## Run

```sh
.claude/skills/model-check-hyper-hold/check.sh            # all properties, about 3 s
.claude/skills/model-check-hyper-hold/check.sh GuideHidesAfterRelease   # one property
```

Needs Java 11+ (`java -version`) and the TLA+ tools 1.7.4 jar at `~/.local/share/tlaplus/tla2tools-1.7.4.jar` (sha256 `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`). If missing, the script prints this one-time install:

```sh
mkdir -p ~/.local/share/tlaplus && curl -fsSL -o ~/.local/share/tlaplus/tla2tools-1.7.4.jar https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
```

Set `TLA2TOOLS=/path/to/tla2tools.jar` to use another copy.

Output is one `== Property: result` line each. Exit 0 means every result matches the baseline: the properties in `known=` in `check.sh` fail (the findings below), the rest pass. `FAIL (NEW)` or `known finding no longer reproduces` exits 1.

Read every result, pass or fail, with the pstack `/statechart` skill (in Claude Code, read the pstack plugin's `skills/statechart/SKILL.md`): give it `HyperHold.tla` and a config listing the three properties as INVARIANTs with `MaxPresses = 2` and `DelayPolls = 2`. It tells each violation as its shortest path in plain words, and charts the states when the check passes. Point it at the jar above with the `TLA2TOOLS` environment variable.

## Bounds and assumptions

- `MaxPresses = 2` (two presses of the hyper key), one bound-app activation per run (by hotkey or by click), `DelayPolls = 2` stands in for `HoldTracker.delay` (21 ticks of the 1/30 s timer in the app; only "at least one tick" matters to the logic). About 5,200 states.
- No timing: a poll can run between any two events, or not at all. That matches the code, which does nothing to force a poll between two run-loop callbacks; in the app a gap with no poll needs a hold shorter than one tick (33 ms) or a main-thread stall that queues the events, since IOHIDManager drains its queued values in one run-loop pass.
- Input Monitoring is granted and the listener is open. One physical hyper key; the hyper key choice does not change. No quit or hide; the bound app was not already in front. `lastHeld` never ages past `graceSeconds` (this only makes a false miss harder to find).

## What each model step is in the code

Each main-thread action is one main-actor callback, so it is indivisible in the code as in the model.

| Model action | Code |
| --- | --- |
| `HidCallback` | `HyperKeyListener.handle(_:down:)`, run on the main run loop by the callback in `HyperKeyListener.open()` (`Sources/ShortcutCoach/Signal.swift`) |
| `Poll` | `Coach.poll()`: `sampleModifiers()` then `HoldTracker.update(hyperHeld:now:)` (`Coach.swift`, `Sources/CoachCore/Decisions.swift`); `guideVisible` is `Coach.guideVisible`, which drives `Guide.show/hide` in `main.swift` |
| `Held` | `heldModifiers() == hyperModifiers`: `isDown`, else the posted flags (`Signal.swift`) |
| `AppActivated` | the synchronous part of `Coach.appActivated`: `sampleModifiers()`, `MissInput` built with `lastHeld` as it is now, `tracker.boundAppActivated()` |
| `DecideMiss` | the `Task` in `Coach.appActivated` that calls `missedBinding` 150 ms later on the captured input |
| `UserPressesHyper`, `UserReleasesHyper`, `UserMovesMouse`, `UserUsesHotkey`, `UserClicksBoundApp` | outside the app: the key, Tinycast's posted flags (a mouse move clears them), Tinycast switching on hyper + letter, a click / Dock / Cmd+Tab |

## Findings (current code)

Both are real at the sync commit; `HoldTracker`'s part was replayed in a Swift test.

1. **`HotkeyNeverFlashes` breaks: a hotkey switch can flash a miss.** You press hyper, press the letter, and release; Tinycast switches apps. The main run loop has not yet run the key-down callback or a poll (a stall, or a very quick chord), and the posted flags are already clear (released, or reset by a mouse move). `appActivated` runs first: `heldModifiers()` reads nothing, `lastHeld` has no hyper entry, the captured `MissInput` says the hotkey was not used, and 150 ms later `missedBinding` flashes. The design doc already says the activation-time sample catches a tap between polls only "usually"; the root cause is that `isDown` and the flags are sampled as levels, so a press that comes and goes between samples is lost.
2. **`GuideShowsOnLongHold` breaks: the guide can stay hidden for a whole hold.** A bound app activates while hyper is up, so `appActivated` calls `tracker.boundAppActivated()` and sets `blocked` outside any hold. If you press hyper before the next poll (within 33 ms, or during a stall), no `update(hyperHeld: false, ...)` runs to clear `blocked`, so the hold that follows never shows the guide. The same happens when you release and press again between two polls after a hotkey switch. Replay: `HoldTracker()`, `update(false, 9.98)`, `boundAppActivated()`, `update(true, 10.0)`, `update(true, 11.0)` returns false.

`GuideHidesAfterRelease` holds: the listener is event-driven, so the last key event always wins.

## Is a failure a bug or a modeling error?

Before you trust a new counterexample, replay it against the real code, one model step per code step. For `HoldTracker` and `missedBinding`, a throwaway Swift Testing test in `Tests/CoachCoreTests` does it (`swift test --filter <name>`); delete it after. If the path cannot happen in the code (the model allows an event the code rules out, or merges two callbacks the code runs separately), the model is wrong: fix the model, never the property. If it can happen, it is a finding: report it with the path in code terms and do not change product code unless asked.

## When the covered code changes

1. Check whether the change touches anything in the Coverage list. If not, nothing to do.
2. Change `HyperHold.tla` so each action still matches its code in the table above (for example, a new reset in `HoldTracker.update` goes into `Poll`; a new queue or timer becomes a new action).
3. Run `check.sh`. A property that newly fails is a finding until a replay says otherwise. If a change fixes a finding, take the property out of `known=` in `check.sh` and out of Findings here, together.
4. Only after you have confirmed the model describes the code at the new commit, move the sync commit below to it.

## Coverage

Last confirmed in step with the code at commit `886d0e65f1904b914d0f150a3c888d99e53f6f69`.

- `Sources/ShortcutCoach/Signal.swift`: `heldModifiers`, `hyperHeld`, `HyperKeyListener.handle`, the input-value callback and main run-loop scheduling in `HyperKeyListener.open`.
- `Sources/ShortcutCoach/Coach.swift`: `start` (the 1/30 s timer), `sampleModifiers`, `poll`, `appActivated` (synchronous part and the 150 ms `Task`).
- `Sources/CoachCore/Decisions.swift`: `HoldTracker` (all), `missedBinding` (only the `lastHeld` / `graceSeconds` branch).
- `Sources/ShortcutCoach/main.swift`: `coach.onGuide` wiring to `Guide.show/hide`.

`git diff 886d0e65f1904b914d0f150a3c888d99e53f6f69 -- Sources/ShortcutCoach/Signal.swift Sources/ShortcutCoach/Coach.swift Sources/CoachCore/Decisions.swift Sources/ShortcutCoach/main.swift` shows what changed since.

## Not covered

Changing the hyper key (`refreshHyperKey`, onboarding `capture`), lost key-ups (keyboard unplugged or sleep while held, Input Monitoring revoked), two keyboards or Caps Lock and F18 both reporting, the no-permission path beyond the flags reset by a mouse move, quit/hide suppression and `previousFrontmost`, binding parsing, real timing (grace expiry, the 0.7 s delay as time), and everything the guide and flash draw.
