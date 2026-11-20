# Shortcut Coach — design

Date: 2026-11-20. Working name; rename freely.

## Intent

Nick has app-switching hotkeys set up in Tinycast (a Raycast-style launcher) on a Caps Lock hyper key, but still reaches apps by mouse click, Dock, Cmd+Tab or the launcher. He wants a small Mac app that works alongside him to build the habit: it notices the miss as it happens and quietly shows the shortcut he should have used, and it shows him the bindings when he holds the hyper key and hesitates.

## Goals

1. **Miss flash.** When a bound app comes to the front without its hotkey, the notch appears to grow (in the style of the Alcove notch app), shows the app icon and its shortcut for about a second, then shrinks back.
2. **Hold guide.** When Caps Lock is held for about 0.7 s without a hotkey firing, show the hyper bindings; hide on release.
3. **Always in sync with Tinycast.** Bindings are read from Tinycast's preferences, never typed in twice.
4. **No macOS permission prompts** (no Input Monitoring, Accessibility or Screen Recording), provided the step-zero test below passes.

## Non-goals

- Window-management shortcuts. Nick resizes by mouse rarely and deliberately; no coaching, and they are not listed in the hold guide.
- Tinycast's non-app shortcuts (clipboard history, emoji, palette toggle).
- Live captures of window contents in the hold guide (needs Screen Recording).
- Labels inside Mission Control. An app can only restyle its own windows there.
- Stats, streaks, sounds, quizzes, a settings window.

## Anti-goals

It has failed, even if it works, if it:

- takes keyboard focus, intercepts a click, or needs dismissing;
- registers any hotkey of its own or otherwise interferes with Tinycast;
- records or stores what is typed;
- flashes so often for non-misses that Nick turns it off.

## What is on the machine (verified 2026-11-20)

- Tinycast preferences domain: `com.abueammar.tinycast`. Each app binding is a key `hotkey.app.<bundle id>` whose value is a JSON string: `{"combo":{"_0":{"carbonKeyCode":<int>,"carbonModifiers":<int>}}}`. Carbon modifier bits: cmd 256, shift 512, option 2048, control 4096. Hyper is all four (6912).
- Current app bindings:

  | Shortcut | App | Bundle id |
  |---|---|---|
  | Hyper+C | Claude | com.anthropic.claudefordesktop |
  | Hyper+G | Chrome | com.google.Chrome |
  | Hyper+L | Linear | com.linear |
  | Hyper+E | Slashy (email) | com.slashy.email |
  | Hyper+S | Slack | com.tinyspeck.slackmacgap |
  | Hyper+D | Dia | company.thebrowser.dia |
  | Hyper+Z | Zed | dev.zed.Zed |
  | Hyper+N | Notion | notion.id |
  | Cmd+Shift+L | Loom | com.loom.desktop.native |

  Also on hyper: `hotkey.systemAction.hide-all-apps-except-frontmost` = Hyper+F.
- **Caps Lock is remapped to F18 at the HID level** (`hidutil` shows `0x700000039 → 0x70000006D` on the active keyboards; Tinycast pref `hyperKeyPhysicalKey = capsLock`). Tinycast then treats F18 as hyper. So "hyper is held" may or may not show up as the four modifier flags; see step zero.
- Displays: built-in notched MacBook screen (3024×1964) plus an external 2560×1440 with no notch.
- Alcove is installed and also draws from the notch.
- Toolchain: Swift 6.4.2 from Command Line Tools. No Xcode.app.

## Approaches

| | A. Swift app, no permissions | B. Swift app, key watching | C. Hammerspoon script |
|---|---|---|---|
| Knows the hotkey was used by | Checking whether hyper was held around the moment the app came forward | Seeing the key press through an event tap | Seeing the key press |
| Permissions | None | Input Monitoring | Accessibility, for Hammerspoon |
| Notch animation | Native | Native | Rougher (canvas) |
| Weak spot | Guesswork around cold launches and system-initiated switches | Permission prompt | The look, which is the point |

Dropped earlier: a Tinycast extension (cannot watch in the background or draw over the notch) and posting into Alcove (no known route in).

**Nick picked A.** The notch look is most of the value and Swift does it natively; B is the same app with the detection part swapped, so A loses nothing if it has to be upgraded.

## Step zero: prove the permission-free signal (throwaway)

Before anything else, a throwaway script prints these three readings a few times a second while Nick holds Caps Lock, with no permissions granted:

1. `CGEventSource.flagsState(.combinedSessionState)` — do the four modifier flags appear?
2. `CGEventSource.keyState(.hidSystemState, key: 79)` — is F18 (virtual key 0x4F) reported down?
3. `CGEventSource.keyState(.combinedSessionState, key: 79)`.

Pick whichever reads true while Caps Lock is held, preferring 1, and hard-code that one in the app; the app does not choose between readings at runtime. Test on both the built-in keyboard and any external one Nick uses. Loom's Cmd+Shift is ordinary modifiers and uses reading 1 regardless. **If none works, or the result is partial or inconsistent (one keyboard only, readings that flicker), stop and go back to Nick**: the fallback is approach B (a listen-only event tap with Input Monitoring), which is his call.

## How it behaves

### Bindings

Read every `hotkey.app.*` key from `com.abueammar.tinycast` at the moment it is needed (each app activation, each time the guide opens), through `CFPreferences` after a synchronize. No cache of our own, no file watcher. A binding that fails to parse is skipped. The app is not sandboxed, which is what lets it read another app's preferences.

Key names for display come from a small table: letters, digits, arrows, space, F-keys. A key outside the table shows as its key code.

### Detecting a miss

- One timer polls the signal about 30 times a second and remembers when hyper, and when Cmd+Shift, were last held. The signal is also sampled once at the moment of each activation, so a tap that falls between polls is still usually caught. The same poll drives the hold guide.
- The app cannot see letters. "The binding's modifiers were held" means any hyper for the hyper apps and Cmd+Shift for Loom. So Hyper+G followed within 3 s by a click on Linear is not flagged, and neither is reaching Loom while Cmd+Shift happens to be down. Both are accepted.
- On `NSWorkspace.didActivateApplicationNotification` for a bound app, it is a **miss** unless one of these holds:
  - that binding's modifiers were held within the last 3 s (covers cold launches);
  - the previously frontmost app quit or was hidden within the last 0.5 s (macOS brought the next app forward, Nick did not choose it);
    macOS reports the quit or hide about 10 ms *after* the next app's activation (observed 2026-11-20), so the decision is made 150 ms after the activation and a quit or hide in that window also suppresses;
  - the app was already frontmost, or is this app itself.
- Every other route counts as a miss, including clicking a window that was already visible. Nick asked for mouse-click focus to count.
- Clicking a window of the app that is already frontmost, or moving between its windows, fires no activation and is not coached. That is intended: there was no switch.
- Every miss flashes. No back-off, no cooldown.

**Known limit.** Without seeing input, the app cannot tell a deliberate switch from one the system made: clicking a link in Slack that opens Dia, or clicking a notification, will flash as if it were a miss. The fix is approach B, where the click's location shows which it was. Ship A, see how often it happens.

### The flash

- A borderless, non-activating panel above the menu bar that ignores mouse events and never becomes key. It shows on every Space and over full-screen apps.
- Shown on the screen that holds the activated app's frontmost on-screen window (the first window for that pid in `CGWindowListCopyWindowInfo`, which is ordered front to back). If the app has no window yet, the screen under the pointer.
- Focus and Do Not Disturb are ignored; it is not a notification.
- On the notched screen: a black shape that starts at the notch's exact size and position (from `NSScreen` safe-area and auxiliary top areas), grows downward and outward, shows the app icon, the shortcut as keycaps (Caps Lock glyph plus the letter, or the real modifiers for Loom) and the app name, holds about 1.2 s, then shrinks back.
- On a screen with no notch: the same black pill dropping from the top-centre edge.
- It draws on top of Alcove for its duration. Briefly covering Alcove's activity is accepted.
- A new miss during a flash replaces the content and restarts the hold time.
- With Reduce Motion on, fade in and out with no growth. White text on black, 13 pt or larger.

### The hold guide

- Opens when the hyper signal has been continuously true for 0.7 s and no bound app was activated in that time. Closes the instant hyper is released or a bound app activates. The delay is a named constant, not a setting.
- **Strip under the notch** (or top-centre on the notchless screen), on the screen under the pointer: one cell per hyper binding with app icon and letter, plus "F  Hide others".
- **Badges on windows**: for each hyper-bound app with a visible window, a large letter badge drawn over that window where it sits, on every screen. Window positions come from `CGWindowListCopyWindowInfo` (owner pid and bounds need no permission).
- Loom is not on hyper, so it is not in the guide.
- The app cannot tell a held Hyper+F from hyper held alone, so holding Hyper+F past 0.7 s opens the guide. Accepted. If the guide is open and Nick then presses a letter, it closes as that app activates.
- Same panel rules as the flash: every Space, over full-screen apps, never takes focus or clicks.

### App shell

- AppKit, built with SwiftPM, wrapped into a `.app` bundle with `LSUIElement` so there is no Dock icon.
- Menu bar item with one entry: Quit. No pause toggle.
- Starts at login.
- For Nick's Mac only: ad-hoc signed, no sandbox, no notarization, installed in `~/Applications`.

## Build order

1. Step-zero script (throwaway).
2. Binding reader and miss decision, as pure functions with unit tests.
3. Flash on the notched screen, then the notchless screen.
4. Hold guide strip, then window badges.
5. Bundle and start at login.

## Testing

- Unit tests: binding JSON to key and modifiers, and to the display string; the miss decision given an activation, last-held times and a recent quit or hide.
- Everything visual is checked by hand on both screens.

## Left to the builder

- Exact sizes, timings and easing of the notch animation.
- How to tell that a window is too covered to carry a badge, and what to do then (the strip already lists the app).
- How start-at-login is wired.
- Project layout and naming.

## Calls made by Claude, not Nick

Check these while reading: 0.7 s guide delay as a constant; 3 s cold-launch grace; 0.5 s quit/hide suppression; every miss flashes with no cooldown; clicks on already-visible windows count; flash appears on the activated app's screen; drawing over Alcove; "Hide others" listed in the guide; Loom left out of the guide; Granola reference taken as a look, not Mission Control behaviour; menu has Quit only, with no pause toggle; shows over full-screen apps and during Focus; any hyper within 3 s counts as using the hotkey; personal build, ad-hoc signed in `~/Applications`; working name.
