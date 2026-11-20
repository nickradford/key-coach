# Shortcut Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar Mac app that flashes the Tinycast hotkey from the notch when Nick reaches a bound app without it, and shows the hyper bindings when he holds Caps Lock.

**Architecture:** A SwiftPM package with two targets. `CoachCore` holds every decision as pure functions (binding parsing, miss decision, hold timing, geometry) and is unit tested. `ShortcutCoach` is a thin AppKit executable that reads signals, calls `CoachCore`, and draws two overlay panels.

**Tech Stack:** Swift 6.4 (Command Line Tools, no Xcode), AppKit, CoreGraphics, Swift Testing (`import Testing`; XCTest is not installed). No third-party dependencies.

**Spec:** `shortcut-coach-design.md` (same folder as this plan). Read it first.

**Project folder:** Nick picks one before Task 0. All paths below are relative to it. `git init` there in Task 1.

## Global Constraints

- No API that triggers a permission prompt: no `CGEventTap`, no `NSEvent.addGlobalMonitorForEvents`, no Accessibility (`AX*`), no ScreenCaptureKit or window image capture, no `RegisterEventHotKey`.
- No third-party packages. `platforms: [.macOS(.v14)]`.
- Overlay panels never become key or main, ignore mouse events, and appear on every Space and over full-screen apps.
- Nothing typed is recorded or stored. Nothing is written to disk at runtime.
- Spec constants, used verbatim: guide delay `0.7` s, cold-launch grace `3.0` s, quit/hide suppression `0.5` s, flash hold `1.2` s, poll interval `1/30` s, text 13 pt or larger, white on black.
- Tinycast domain `com.abueammar.tinycast`; app bindings are keys prefixed `hotkey.app.`; hyper is Carbon modifiers `6912`; F18 is virtual key `79`.
- Tests use Swift Testing. Run with `swift test`. If it reports `no such module 'Testing'`, add `-Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks`.
- Times passed to `CoachCore` are `ProcessInfo.processInfo.systemUptime`.

## Review Focus

1. **Tinycast missing or its preferences empty.** The app runs silently with no flashes and no crash. Pinned in Task 1 (`emptyPrefsGiveNoBindings`).
2. **A shortcut is rebound in Tinycast while the coach runs.** The next activation shows the new key without a restart. Pinned in Task 4, Step 5.
3. **A display is unplugged, or the app's window is on no known screen.** The flash falls back to the pointer's screen. Pinned in Task 3 (`windowOnNoScreenGivesNil`).
4. **An activation arrives with no bundle id, or for the coach itself.** Ignored. Pinned in Task 2 (`emptyBundleIDIsNeverAMiss`, `ownAppIsNeverAMiss`).
5. **Several misses in quick succession.** One panel, content replaced, gone 1.2 s after the last. Pinned in Task 5, Step 4.

---

### Task 0: Prove the permission-free signal (throwaway, needs Nick)

**Files:**
- Create: `spike/signal.swift` (deleted at the end of this task, never committed)

- [ ] **Step 1: Write the script.** For 20 seconds, every 0.2 s, print one line with three booleans: `flags` = `CGEventSource.flagsState(.combinedSessionState)` contains all of control, option, shift, command; `hidF18` = `CGEventSource.keyState(.hidSystemState, key: 79)`; `sessF18` = `CGEventSource.keyState(.combinedSessionState, key: 79)`.

- [ ] **Step 2: Nick runs it from Terminal**, holding and releasing Caps Lock a few times, once per keyboard he uses.

Run: `swift spike/signal.swift`
Expected: at least one column reads `true` while Caps Lock is held and `false` otherwise, on every keyboard.

- [ ] **Step 3: Record the winner** (prefer `flags`, then `hidF18`, then `sessF18`) in a one-line comment at the top of this plan's Task 4. Delete `spike/`.

**Gate:** if no column tracks the key, or it works on one keyboard only, or it flickers while held, stop. Report to Nick; the fallback (Input Monitoring) is his decision.

---

### Task 1: Package and binding parsing

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`)
- Create: `Sources/CoachCore/Binding.swift`
- Create: `Sources/ShortcutCoach/main.swift` (one line for now: `print("ok")`)
- Test: `Tests/CoachCoreTests/BindingTests.swift`

**Interfaces:**
- Produces:

```swift
public let hyperModifiers = 6912
public struct Binding: Equatable, Sendable {
    public let bundleID: String
    public let keyCode: Int      // Carbon virtual key
    public let modifiers: Int    // Carbon modifier mask
    public init(bundleID: String, keyCode: Int, modifiers: Int)
    public var isHyper: Bool     // modifiers == hyperModifiers
    public var keyName: String   // "S", "7", "←", "Space", "F5"; otherwise "key 200"
    public var display: String   // "⇪ S" when hyper; else modifier glyphs in ⌃⌥⇧⌘ order, a space, keyName: "⇧⌘ L"
}
public func parseCombo(_ value: Any?) -> (keyCode: Int, modifiers: Int)?
public func parseBindings(_ prefs: [String: Any]) -> [Binding]   // "hotkey.app.*" only, sorted by bundleID
public func loadTinycastPrefs() -> [String: Any]
```

- [ ] **Step 1: Write `Package.swift`** with library target `CoachCore`, executable target `ShortcutCoach` depending on it, test target `CoachCoreTests`. Run `git init`.

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
@testable import CoachCore

let slack = #"{"combo":{"_0":{"carbonModifiers":6912,"carbonKeyCode":1}}}"#
let loom  = #"{"combo":{"_0":{"carbonKeyCode":37,"carbonModifiers":768}}}"#

@Test func parsesAppBindingsSortedAndIgnoresOtherKeys() {
    let b = parseBindings([
        "hotkey.app.com.tinyspeck.slackmacgap": slack,
        "hotkey.app.com.loom.desktop.native": loom,
        "hotkey.windowCommand.left-half": slack,
        "appearance": "system",
    ])
    #expect(b == [
        Binding(bundleID: "com.loom.desktop.native", keyCode: 37, modifiers: 768),
        Binding(bundleID: "com.tinyspeck.slackmacgap", keyCode: 1, modifiers: 6912),
    ])
}
@Test func displayStrings() {
    #expect(Binding(bundleID: "x", keyCode: 1, modifiers: 6912).display == "⇪ S")
    #expect(Binding(bundleID: "x", keyCode: 37, modifiers: 768).display == "⇧⌘ L")
    #expect(Binding(bundleID: "x", keyCode: 123, modifiers: 2304).display == "⌥⌘ ←")
    #expect(Binding(bundleID: "x", keyCode: 49, modifiers: 256).display == "⌘ Space")
    #expect(Binding(bundleID: "x", keyCode: 200, modifiers: 6912).display == "⇪ key 200")
}
@Test func malformedValuesAreSkipped() {
    #expect(parseBindings(["hotkey.app.a": "not json", "hotkey.app.b": 42,
                           "hotkey.app.c": #"{"combo":{}}"#]).isEmpty)
}
@Test func emptyPrefsGiveNoBindings() { #expect(parseBindings([:]).isEmpty) }
@Test func parseComboReadsEitherFieldOrder() {
    #expect(parseCombo(slack)?.keyCode == 1)
    #expect(parseCombo(loom)?.modifiers == 768)
    #expect(parseCombo(nil) == nil)
}
```

- [ ] **Step 3: Run to verify failure.** Run: `swift test`. Expected: compile failure, `cannot find 'parseBindings'`.

- [ ] **Step 4: Implement `Binding.swift`.** Key names from the `kVK_*` constants in `Carbon.HIToolbox` (ANSI letters, digits, arrows, space, F1 to F12). `loadTinycastPrefs` calls `CFPreferencesAppSynchronize` then `CFPreferencesCopyMultiple(nil, "com.abueammar.tinycast", kCFPreferencesCurrentUser, kCFPreferencesAnyHost)`; returns `[:]` when the domain is absent.

- [ ] **Step 5: Run to verify pass.** Run: `swift test`. Expected: all pass.

- [ ] **Step 6: Commit.** `git add -A && git commit -m "feat: parse Tinycast app bindings"`

---

### Task 2: Miss decision and hold timing

**Files:**
- Create: `Sources/CoachCore/Decisions.swift`
- Test: `Tests/CoachCoreTests/DecisionTests.swift`

**Interfaces:**
- Consumes: `Binding`, `hyperModifiers` (Task 1).
- Produces:

```swift
public let graceSeconds = 3.0
public let quitHideSeconds = 0.5
public struct MissInput {
    public var activated: String                 // bundle id; "" when unknown
    public var previousFrontmost: String?
    public var now: TimeInterval
    public var lastHeld: [Int: TimeInterval]     // Carbon modifier mask -> last time it read as held
    public var lastQuitOrHide: (bundleID: String, at: TimeInterval)?
    public init(activated: String, previousFrontmost: String?, now: TimeInterval,
                lastHeld: [Int: TimeInterval] = [:],
                lastQuitOrHide: (bundleID: String, at: TimeInterval)? = nil)
}
/// The binding Nick should have used, or nil when this activation is not a miss.
public func missedBinding(_ input: MissInput, bindings: [Binding], ownBundleID: String?) -> Binding?

public struct HoldTracker {
    public static let delay = 0.7
    public init()
    /// Call every poll. Returns whether the guide should be visible.
    public mutating func update(hyperHeld: Bool, now: TimeInterval) -> Bool
    /// Hides the guide and keeps it hidden until hyper is released.
    public mutating func boundAppActivated()
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import CoachCore

let slackB = Binding(bundleID: "slack", keyCode: 1, modifiers: 6912)
let loomB  = Binding(bundleID: "loom", keyCode: 37, modifiers: 768)
let all = [slackB, loomB]
func miss(_ i: MissInput) -> Binding? { missedBinding(i, bindings: all, ownBundleID: "coach") }

@Test func boundAppWithoutHotkeyIsAMiss() {
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100)) == slackB)
}
@Test func hyperHeldWithinGraceIsNotAMiss() {
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastHeld: [6912: 97.1])) == nil)
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastHeld: [6912: 100])) == nil)
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastHeld: [6912: 96.9])) == slackB)
}
@Test func eachBindingNeedsItsOwnModifiers() {
    #expect(miss(MissInput(activated: "loom", previousFrontmost: "zed", now: 100, lastHeld: [6912: 99])) == loomB)
    #expect(miss(MissInput(activated: "loom", previousFrontmost: "zed", now: 100, lastHeld: [768: 99])) == nil)
}
@Test func unboundAppIsNeverAMiss() {
    #expect(miss(MissInput(activated: "finder", previousFrontmost: "zed", now: 100)) == nil)
}
@Test func alreadyFrontmostIsNeverAMiss() {
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "slack", now: 100)) == nil)
}
@Test func ownAppIsNeverAMiss() {
    #expect(missedBinding(MissInput(activated: "slack", previousFrontmost: "zed", now: 100),
                          bindings: all, ownBundleID: "slack") == nil)
}
@Test func emptyBundleIDIsNeverAMiss() {
    #expect(miss(MissInput(activated: "", previousFrontmost: "zed", now: 100)) == nil)
}
@Test func previousAppQuittingOrHidingSuppresses() {
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastQuitOrHide: ("zed", 99.6))) == nil)
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastQuitOrHide: ("zed", 99.4))) == slackB)
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastQuitOrHide: ("dia", 99.9))) == slackB)
}

@Test func guideOpensAfterDelayAndClosesOnRelease() {
    var t = HoldTracker()
    #expect(t.update(hyperHeld: true, now: 10.0) == false)
    #expect(t.update(hyperHeld: true, now: 10.65) == false)
    #expect(t.update(hyperHeld: true, now: 10.75) == true)   // not 10.7: 10.7 - 10.0 < 0.7 in floating point
    #expect(t.update(hyperHeld: false, now: 10.8) == false)
    #expect(t.update(hyperHeld: true, now: 10.9) == false)   // delay restarts
}
@Test func activationKeepsGuideClosedUntilRelease() {
    var t = HoldTracker()
    _ = t.update(hyperHeld: true, now: 10.0)
    t.boundAppActivated()
    #expect(t.update(hyperHeld: true, now: 11.0) == false)
    _ = t.update(hyperHeld: false, now: 11.1)
    _ = t.update(hyperHeld: true, now: 11.2)
    #expect(t.update(hyperHeld: true, now: 12.0) == true)
}
@Test func activationClosesAnOpenGuide() {
    var t = HoldTracker()
    _ = t.update(hyperHeld: true, now: 10.0)
    #expect(t.update(hyperHeld: true, now: 10.8) == true)
    t.boundAppActivated()
    #expect(t.update(hyperHeld: true, now: 10.9) == false)
}
```

- [ ] **Step 2: Run to verify failure.** Run: `swift test`. Expected: compile failure, `cannot find 'missedBinding'`.

- [ ] **Step 3: Implement `Decisions.swift`.** Grace and suppression comparisons are inclusive (`now - t <= limit`).

- [ ] **Step 4: Run to verify pass.** Run: `swift test`. Expected: all pass.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat: miss decision and hold timing"`

---

### Task 3: Screen and badge geometry

**Files:**
- Create: `Sources/CoachCore/Geometry.swift`
- Test: `Tests/CoachCoreTests/GeometryTests.swift`

**Interfaces:**
- Produces:

```swift
public struct WindowInfo: Equatable, Sendable {
    public let pid: Int32
    public let bounds: CGRect
    public init(pid: Int32, bounds: CGRect)
}
/// Index of the screen frame overlapping `bounds` the most; nil when it overlaps none.
public func screenIndex(forWindowBounds bounds: CGRect, screenFrames: [CGRect]) -> Int?
/// `windows` is front to back. For each pid in `pids`, the centre of its frontmost window,
/// omitted when a window nearer the front contains that point.
public func badgePoints(windows: [WindowInfo], pids: Set<Int32>) -> [Int32: CGPoint]
```

All rectangles in this file are in one coordinate space; the caller converts.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import CoachCore

let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)]

@Test func windowGoesToScreenWithMostOverlap() {
    #expect(screenIndex(forWindowBounds: CGRect(x: 100, y: 100, width: 800, height: 600), screenFrames: screens) == 0)
    #expect(screenIndex(forWindowBounds: CGRect(x: 2000, y: 100, width: 800, height: 600), screenFrames: screens) == 1)
    #expect(screenIndex(forWindowBounds: CGRect(x: 1400, y: 100, width: 800, height: 600), screenFrames: screens) == 1)
}
@Test func windowOnNoScreenGivesNil() {
    #expect(screenIndex(forWindowBounds: CGRect(x: 9000, y: 9000, width: 10, height: 10), screenFrames: screens) == nil)
    #expect(screenIndex(forWindowBounds: CGRect(x: 0, y: 0, width: 10, height: 10), screenFrames: []) == nil)
}
@Test func badgeSitsAtCentreOfFrontmostWindowPerApp() {
    let w = [WindowInfo(pid: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
             WindowInfo(pid: 1, bounds: CGRect(x: 500, y: 500, width: 100, height: 100)),
             WindowInfo(pid: 2, bounds: CGRect(x: 200, y: 0, width: 100, height: 100))]
    #expect(badgePoints(windows: w, pids: [1, 2]) == [1: CGPoint(x: 50, y: 50), 2: CGPoint(x: 250, y: 50)])
}
@Test func coveredCentreAndUnlistedAppsGetNoBadge() {
    let w = [WindowInfo(pid: 9, bounds: CGRect(x: 0, y: 0, width: 300, height: 300)),
             WindowInfo(pid: 1, bounds: CGRect(x: 100, y: 100, width: 100, height: 100))]
    #expect(badgePoints(windows: w, pids: [1, 3]).isEmpty)
}
```

- [ ] **Step 2: Run to verify failure.** Run: `swift test`. Expected: compile failure.
- [ ] **Step 3: Implement `Geometry.swift`.**
- [ ] **Step 4: Run to verify pass.** Run: `swift test`. Expected: all pass.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat: screen and badge geometry"`

---

### Task 4: App shell and live detection (prints misses, no drawing yet)

<!-- Task 0 winner: flags (flagsState shows all four modifiers while Caps Lock is held; F18 keyState never read true) -->

**Files:**
- Modify: `Sources/ShortcutCoach/main.swift`
- Create: `Sources/ShortcutCoach/Signal.swift`
- Create: `Sources/ShortcutCoach/Coach.swift`

**Interfaces:**
- Consumes: everything `CoachCore` produces in Tasks 1 to 3.
- Produces:

```swift
// Signal.swift
func hyperHeld() -> Bool                       // the single reading Task 0 chose, hard-coded
func modifiersHeld(_ carbonMask: Int) -> Bool  // hyperModifiers -> hyperHeld(); otherwise the device-independent
                                               // ⌃⌥⇧⌘ subset of flagsState equals the mask exactly

// Coach.swift
@MainActor final class Coach {
    var onMiss: (Binding, NSRunningApplication) -> Void   // default: print("MISS \(name) \(binding.display)")
    var onGuide: (Bool) -> Void                           // default: print("GUIDE \(visible)"), called on change only
    func start()
}
```

- [ ] **Step 1: `main.swift`.** `NSApplication` with activation policy `.accessory`; an `NSStatusItem` with SF Symbol `keyboard` and a menu holding only Quit; create a `Coach` and call `start()`.

- [ ] **Step 2: `Signal.swift`** as specified above.

- [ ] **Step 3: `Coach.start()`.**
  - A `Timer` every `1/30` s: for each distinct modifier mask among the current bindings, if `modifiersHeld(mask)` then `lastHeld[mask] = now`; feed `hyperHeld()` to a `HoldTracker` and call `onGuide` when its result changes.
  - `NSWorkspace` notifications: `didActivateApplicationNotification`, `didTerminateApplicationNotification`, `didHideApplicationNotification`. Terminate and hide set `lastQuitOrHide`.
  - On activate: bindings = `parseBindings(loadTinycastPrefs())`; sample every mask once more; build `MissInput` (`activated` is the bundle id or `""`); if `missedBinding` returns a binding call `onMiss`; if the activated app is bound call `tracker.boundAppActivated()`; then set `previousFrontmost`.
  - `previousFrontmost` starts as the app frontmost at launch, so launching the coach never flashes.

- [ ] **Step 4: Verify by hand.** Run: `swift run ShortcutCoach`.
  Expected: clicking Slack's Dock icon prints `MISS Slack ⇪ S`; Hyper+S prints nothing; Cmd+Tab to Zed prints `MISS Zed ⇪ Z`; quitting an app so that Slack comes forward prints nothing; holding Caps Lock for a second prints `GUIDE true`, releasing prints `GUIDE false`; a quick Hyper+C prints neither. No permission dialog appears at any point.

- [ ] **Step 5: Verify rebinding (Review Focus 2).** With the coach running, change Slack's hotkey in Tinycast, click Slack. Expected: the printed shortcut is the new one. Change it back.

- [ ] **Step 6: Commit.** `git add -A && git commit -m "feat: detect misses and hyper hold"`

---

### Task 5: The notch flash

**Files:**
- Create: `Sources/ShortcutCoach/Overlay.swift`
- Create: `Sources/ShortcutCoach/Flash.swift`
- Modify: `Sources/ShortcutCoach/main.swift` (set `coach.onMiss`)

**Interfaces:**
- Consumes: `Binding.display`, `screenIndex(forWindowBounds:screenFrames:)`, `WindowInfo`.
- Produces:

```swift
// Overlay.swift
@MainActor func makeOverlayPanel() -> NSPanel
/// The notch's rect in screen coordinates; on a notchless screen, a zero-height rect 180 pt wide at top centre.
@MainActor func notchRect(on screen: NSScreen) -> NSRect
/// On-screen layer-0 windows, front to back, bounds converted to AppKit screen coordinates.
func onScreenWindows() -> [WindowInfo]
/// Screen holding the app's frontmost window; the pointer's screen when it has none or overlaps no screen.
@MainActor func screen(for app: NSRunningApplication) -> NSScreen

// Flash.swift
@MainActor final class Flash {
    func show(_ binding: Binding, app: NSRunningApplication)
}
```

- [ ] **Step 1: `Overlay.swift`.** `makeOverlayPanel`: borderless `.nonactivatingPanel`, clear background, no shadow, `ignoresMouseEvents = true`, `canBecomeKey` and `canBecomeMain` false (subclass), level above the main menu, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`. `notchRect` from `safeAreaInsets.top`, `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. `onScreenWindows` from `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`, reading only `kCGWindowOwnerPID`, `kCGWindowBounds`, `kCGWindowLayer`.

- [ ] **Step 2: `Flash.swift`.** One reused panel. A black shape with rounded bottom corners starts at `notchRect`, grows to about 320 × 76 pt hanging from the top edge, shows app icon, app name and `binding.display` as keycaps, holds `1.2` s, then shrinks back and orders out. A call during a flash swaps the content and restarts the 1.2 s. When `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is true, fade with no size change. Exact sizes and easing are the builder's.

- [ ] **Step 3: Wire `coach.onMiss = { flash.show($0, app: $1) }`.**

- [ ] **Step 4: Verify by hand.** Run: `swift run ShortcutCoach`.
  Expected, each checked:
  - Click Slack on the MacBook screen: the notch grows, shows Slack's icon and `⇪ S`, shrinks after about a second.
  - Click an app whose window is on the external display: the pill drops from that display's top centre.
  - Click Slack, Zed, Dia within one second: one panel, content changes, gone about 1.2 s after the last (Review Focus 5).
  - While the flash shows, typing still goes to the app just clicked, and clicking where the flash is reaches what is underneath.
  - Switch by mouse to a full-screen app: the flash shows there.
  - Turn on Reduce Motion in System Settings: the flash fades instead of growing. Turn it off again.
  - With Alcove showing music: the flash covers it and Alcove is intact afterwards.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat: notch flash on a missed hotkey"`

---

### Task 6: The hold guide

**Files:**
- Create: `Sources/ShortcutCoach/Guide.swift`
- Modify: `Sources/ShortcutCoach/main.swift` (set `coach.onGuide`)

**Interfaces:**
- Consumes: `makeOverlayPanel`, `notchRect`, `onScreenWindows`, `badgePoints(windows:pids:)`, `parseBindings`, `parseCombo`, `loadTinycastPrefs`.
- Produces:

```swift
@MainActor final class Guide {
    func show()   // reads bindings itself
    func hide()
}
```

- [ ] **Step 1: Strip.** On the pointer's screen, a black strip hanging from the notch (or top centre): one cell per hyper binding with the app's icon (`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`, skip the cell if the app is not installed) and `keyName`. One more cell, text only, `F  Hide others`, taking its letter from `parseCombo(prefs["hotkey.systemAction.hide-all-apps-except-frontmost"])` and omitted when that key is absent or not on hyper. Non-hyper bindings are not shown.

- [ ] **Step 2: Badges.** One overlay panel per screen. `badgePoints(windows: onScreenWindows(), pids:)` with the pids of running hyper-bound apps; draw each app's `keyName` as a large white letter on a black rounded square centred on its point.

- [ ] **Step 3: Wire `coach.onGuide = { $0 ? guide.show() : guide.hide() }`.** Appear and disappear with a fast fade (or instantly under Reduce Motion).

- [ ] **Step 4: Verify by hand.** Run: `swift run ShortcutCoach`.
  Expected, each checked:
  - Hold Caps Lock: after about 0.7 s the strip lists eight apps and `F  Hide others`; every visible bound app's window carries its letter; Loom is absent.
  - Release: everything disappears at once.
  - Quick Hyper+S: the guide never appears.
  - Hold until the guide shows, then press S: Slack comes forward and the guide closes.
  - A bound app whose window is mostly covered has no badge but is in the strip.
  - Badges appear on both displays.
  - While the guide shows, typing and clicks reach the app underneath.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat: hold-hyper guide"`

---

### Task 7: Install and start at login

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/uninstall.sh`
- Create: `README.md` (what it is, install, uninstall, the known limit on system-made switches; under 30 lines)

- [ ] **Step 1: `install.sh`.** `set -euo pipefail`. `swift build -c release`; assemble `~/Applications/Shortcut Coach.app` with the binary at `Contents/MacOS/ShortcutCoach` and an `Info.plist` (`CFBundleIdentifier` `local.shortcut-coach`, `CFBundleExecutable` `ShortcutCoach`, `LSUIElement` true, `LSMinimumSystemVersion` 14.0); `codesign --force --sign - "<app>"`; write `~/Library/LaunchAgents/local.shortcut-coach.plist` (`Label` `local.shortcut-coach`, `ProgramArguments` the binary's full path, `RunAtLoad` true, no `KeepAlive`); `launchctl bootout gui/$UID/local.shortcut-coach 2>/dev/null || true`; `launchctl bootstrap gui/$UID <plist>`.

- [ ] **Step 2: `uninstall.sh`.** Boot out the agent, remove the plist and the app. Removes only those two paths.

- [ ] **Step 3: Verify.** Run: `scripts/install.sh && launchctl print gui/$UID/local.shortcut-coach | grep state`
  Expected: `state = running`; the keyboard icon is in the menu bar; no Dock icon; clicking Slack flashes. Quit from the menu, then log out and in: it is running again.

- [ ] **Step 4: Verify uninstall.** Run: `scripts/uninstall.sh; launchctl print gui/$UID/local.shortcut-coach`
  Expected: `Could not find service`; the app is gone from `~/Applications`. Run `scripts/install.sh` again to leave it installed.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat: install script and start at login"`
