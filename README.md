# Shortcut Coach

A menu-bar app that helps build the habit of using the app-switching hotkeys set up in
Tinycast.

- **Miss flash.** Reach a bound app by mouse, Dock, Cmd+Tab or the launcher and the notch
  briefly grows to show the hotkey you could have used.
- **Hold guide.** Hold Caps Lock (the hyper key) for 0.7 s and the hyper bindings appear
  under the notch, with a letter badge on each bound app's visible window.

Bindings are read live from Tinycast's preferences. No macOS permissions are needed, and
nothing you type is recorded.

## Install

    scripts/install.sh

Builds with the Swift Command Line Tools (no Xcode), installs `~/Applications/Shortcut Coach.app`
and a LaunchAgent so it starts at login. Run it again after changing the code.

## Uninstall

    scripts/uninstall.sh

## Known limit

The app cannot see keys or clicks, only which app came forward and whether the hotkey's
modifiers were held. A switch the system made for you (a link in Slack opening the browser,
a clicked notification) flashes as if you had missed the hotkey.

## Development

    swift test          # decision logic
    swift run           # run without installing

Design and plan: `shortcut-coach-design.md`, `shortcut-coach-plan.md`.
