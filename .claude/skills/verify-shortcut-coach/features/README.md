# Shortcut Coach verification map

This directory is the maintained source for verifying the user-facing behavior of Shortcut Coach. Read the index before driving the app, then use the matching feature file as the recipe. `coach.sh` below means `.claude/skills/verify-shortcut-coach/scripts/coach.sh`, run from the repo root.

## Baseline preconditions

- No other `ShortcutCoach` process is running (`pgrep -x ShortcutCoach` prints nothing). The installed copy runs as LaunchAgent `local.shortcut-coach`; the user quits it, not the agent.
- `coach.sh launch` reported `ready`, and `coach.sh doctor` prints only `ok` lines.
- Tinycast's preferences (`defaults read com.abueammar.tinycast`) contain `hotkey.app.<bundle-id>` entries with `carbonModifiers` 6912 (hyper). At the time of writing: `com.anthropic.claudefordesktop` C, `company.thebrowser.dia` D, `md.obsidian` O, `com.superlogical.rex` R, `dev.zed.Zed` Z, plus `hotkey.systemAction.hide-all-apps-except-frontmost` F. Re-read them; never edit them.
- The shell running the helper is trusted for Accessibility and Screen Recording.
- Never drive an instance this run did not start.

## Driving conventions

- Start each recipe from a launched instance with no island on screen (`coach.sh windows` shows every `layer=2147483631` line `onscreen=false`).
- Target the app by pid in every Accessibility call (`first process whose unix id is <pid>`), never by process name.
- Onboarding buttons have no accessible names. Address them by index in `group 1 of window 1` and identify the step by its title text.
- Never send keystrokes through System Events; they go to whichever app is frontmost.
- Bringing an app forward steals the user's focus. `coach.sh dock` and `coach.sh open` give it back afterwards.

## Proof and skip reporting

- Capture the action and the resulting state: `steps.txt`, the before/during/after window lists, and the strip PNG.
- Look at every PNG and say what it shows (app name, keycaps, cells).
- A window list alone proves a panel appeared, not its content.
- Record the feature ID and entry point with every artifact; evidence dirs are named after the command.
- Report an unreachable entry point with the attempted command and the unmet precondition. Do not report the physical-key path as verified by the posted-flags path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior, then exactly four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with coach.sh`, `Gotchas`.

## Features

- [Miss flash](./miss-flash.md) covers the island shown when a bound app comes forward without its hotkey, and the cases that must not flash.
- [Hold guide](./hold-guide.md) covers the binding strip and window badges shown while hyper is held, and hiding on release.
- [Onboarding](./onboarding.md) covers the first-launch panel, its six steps, the demo flash and closing.
- [Menu bar menu](./menu-bar.md) covers the keyboard icon's menu: Show Onboarding… and Quit.
