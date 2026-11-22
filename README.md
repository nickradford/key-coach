<p align="center">
  <img src="assets/header.png" alt="Shortcut Coach: a hint drops from the notch showing the Caps Lock and M keys" width="800">
</p>

# Shortcut Coach

A menu-bar app for macOS that helps you build the habit of using the app-switching hotkeys
you set up in Tinycast.

- **Miss flash.** Bring a bound app forward any other way (a click, the Dock, Cmd+Tab, a
  launcher) and a black island drops from the notch, showing the app and the hotkey you could
  have used. The flash gets shorter as you learn the hotkey and stops once you know it. See
  [How the flash fades](#how-the-flash-fades).
- **Hold guide.** Hold the hyper key (Caps Lock unless you chose another) for 0.7 s and an island lists every
  hyper binding, with a letter badge on each bound app's visible window. Release to hide it.

Bindings are read from Tinycast's preferences each time they are needed, so changes in
Tinycast apply immediately.

## Requirements

- macOS 14 or later.
- Tinycast, with hotkeys bound to apps. Without Tinycast the app runs but shows nothing.
- The Swift toolchain from the Xcode Command Line Tools (`xcode-select --install`). Xcode
  itself is not needed.

A notch is optional. On a screen without one, the island drops from the top centre, or from
Alcove's fake notch when Alcove is set to show on all displays.

## Install

    scripts/install.sh

This builds a release binary, installs `~/Applications/Shortcut Coach.app`, and adds a
LaunchAgent (`~/Library/LaunchAgents/local.shortcut-coach.plist`) so it starts now and at
every login. macOS shows a one-time "background item added" notice. Run it again after
changing the code.

On first launch a short onboarding window walks through Tinycast, the permission, the hyper
key and a try-out. The app then lives in the menu bar (keyboard icon): **Show Onboarding…**
opens that window again, and Quit stops the app until the next login.

## Permission

The onboarding's third step asks for **Input Monitoring** so the app can see the physical
hyper key and which hotkey you press; nothing is asked at launch. Turn it on in System
Settings > Privacy & Security > Input Monitoring, or reopen the step with **Show
Onboarding…**. The app picks it up within a second, with no restart.

With the permission, the app reads only:

- the keys that can be hyper (Caps Lock, F18 and the right-hand modifiers);
- a key pressed while a hotkey's modifiers are held (hyper, or for example Cmd+Shift), to
  tell whether it is one of your hotkeys. Any other key pressed then is noted only as "not a
  hotkey", never which key it was;
- Tab while Command is held, to tell a Cmd+Tab switch from a click.

Every other key is dropped as it arrives: nothing you type is read or stored.

Without the permission it still works, but moving the mouse while holding the hyper key reads
as letting go, because Tinycast's hyper is posted as modifier flags and a real mouse move
resets them. It also cannot see which hotkey you pressed (see What counts as a miss).

With or without the permission, and without asking for another, the app notes where your last
click landed: which app's window, not what is in it. It also asks macOS when a key last went
down, not which key. Both stay in memory and let the app tell a switch you made from one the
system made.

Each app switch is stored: the app, whether it was a hit, a miss, an app with no hotkey or a
switch the system made, how you switched (hotkey, Cmd+Tab or other) and the time. No key or
click is stored. The history is a file on your Mac,
`~/Library/Application Support/local.shortcut-coach/history.json`, and keeps the last 30
days, at most 5,000 switches.

The app is ad-hoc signed, so macOS may ask you to approve it again after each reinstall.

## Hyper key

The hyper key is, in order: Tinycast's `hyperKeyPhysicalKey` setting when it names a key the
app knows, else the key chosen in onboarding, else Caps Lock. The choices are Caps Lock, Right
Command, Right Option, Right Control and Right Shift. Hyper itself is always Control + Option +
Shift + Command; only the physical key and its glyph in the island change.

## What counts as a miss

A bound app coming to the front is a miss unless:

- you pressed its own hotkey in the last 3 s. Pressing another app's hotkey and then clicking
  this one is a miss. Without Input Monitoring the app cannot see which key you pressed, so
  holding the hotkey's modifiers (hyper, or for example Cmd+Shift) in the last 3 s counts;
- you did not bring it forward: in the last 3 s no key went down and no click landed on the
  Dock, Stage Manager or the app itself. A link in Slack opening your browser, or a clicked
  notification, is a click on another app, so it does not flash. Neither does a trackpad swipe
  to another full-screen app;
- the app in front before it quit or hid, so macOS chose the next app, not you;
- it was already in front, or the change came from a lock screen or system prompt.

Any key counts as bringing the app forward, so a link or notification clicked within 3 s of
typing still flashes.

Window-management shortcuts are not coached.

## How the flash fades

Each app's flash depends on its last 20 attempts: switches to it that were a hit (its own
hotkey) or a miss. Other switches do not count. The first row that matches applies.

| Stage | Last 20 attempts | Flash |
| --- | --- | --- |
| Learned | all 20 made, at least 19 hits | none |
| Fluent | at least 10 made, at least 80% hits | 0.6 s |
| Practicing | at least 5 made, at least half hits | 1.0 s |
| Learning | anything else | 1.6 s |

When a hotkey press takes an app to **Learned**, the island shows the app and its hotkey once
more, marked "✓ Learned". If two of the last 20 attempts become misses, the app drops back to
**Fluent** and the flash returns.

## Uninstall

    scripts/uninstall.sh

This removes the app and its LaunchAgent and nothing else. Remove Shortcut Coach from the
Input Monitoring list, and the history in `~/Library/Application Support/local.shortcut-coach`,
yourself if you like.

## Development

    swift test                    # decision logic: bindings, key presses, misses, history,
                                  # hold timing, geometry
    swift run                     # run without installing (from Terminal it uses
                                  # Terminal's Input Monitoring permission)
    swift scripts/render-art.swift  # redraw assets/icon.png, header.png and AppIcon.icns

`Package.swift` points the tests at the Command Line Tools' Swift Testing plugin
(`/Library/Developer/CommandLineTools/...`). With Xcode installed you may need to remove that
setting.

`shortcut-coach-design.md` and `shortcut-coach-plan.md` are the original design and build
plan. Later changes (the island animation, Alcove's fake notch, Input Monitoring) are in the
commit history.
