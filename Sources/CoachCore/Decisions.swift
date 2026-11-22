import Foundation

/// A hotkey counts as used if it was pressed this recently before the app came forward (covers cold launches).
/// Also how recent a key or click must be for the switch to be the user's doing.
public let graceSeconds = 3.0
/// An app coming forward this soon after the previous one quit or hid was macOS's doing, not a choice.
public let quitHideSeconds = 0.5
/// A Command-Tab press this recently before a switch made it. The switch lands when Command is released,
/// so this is how long the user may look at the switcher after the last Tab.
public let commandTabSeconds = 1.0
/// Apps whose windows a click lands on to bring another app forward: the Dock (which also draws
/// Launchpad, Mission Control and the Command-Tab switcher) and Stage Manager.
private let switcherApps: Set<String> = ["com.apple.dock", "com.apple.WindowManager"]

public struct MissInput {
    public var activated: String
    public var previousFrontmost: String?
    public var now: TimeInterval
    public var lastHeld: [Int: TimeInterval]
    public var lastQuitOrHide: (bundleID: String, at: TimeInterval)?
    /// The listener's latest key press and its time, on the same clock as `now`.
    public var lastPress: (press: KeyPress, at: TimeInterval)?
    /// The listener is open (Input Monitoring granted), so `lastPress` sees every hotkey press.
    public var listening: Bool
    /// The latest key-down of any key, which key unknown.
    public var lastKeyAt: TimeInterval?
    /// The latest left mouse-down and the app that owns the window it landed on.
    public var lastClick: (bundleID: String?, at: TimeInterval)?

    public init(activated: String, previousFrontmost: String?, now: TimeInterval,
                lastHeld: [Int: TimeInterval] = [:],
                lastQuitOrHide: (bundleID: String, at: TimeInterval)? = nil,
                lastPress: (press: KeyPress, at: TimeInterval)? = nil,
                listening: Bool = false,
                lastKeyAt: TimeInterval? = nil,
                lastClick: (bundleID: String?, at: TimeInterval)? = nil) {
        self.activated = activated
        self.previousFrontmost = previousFrontmost
        self.now = now
        self.lastHeld = lastHeld
        self.lastQuitOrHide = lastQuitOrHide
        self.lastPress = lastPress
        self.listening = listening
        self.lastKeyAt = lastKeyAt
        self.lastClick = lastClick
    }
}

/// False for an activation that is not the user switching apps: this app, the app already in front,
/// or macOS picking the next app after the front one quit or hid.
private func isUserSwitch(_ input: MissInput, ownBundleID: String?) -> Bool {
    guard !input.activated.isEmpty, input.activated != ownBundleID, input.activated != input.previousFrontmost
    else { return false }
    if let gone = input.lastQuitOrHide, gone.bundleID == input.previousFrontmost,
       input.now - gone.at <= quitHideSeconds { return false }
    return true
}

/// With Input Monitoring, the app's own key was pressed; without it, the binding's modifiers were held.
private func usedHotkey(_ binding: Binding, _ input: MissInput) -> Bool {
    // shortcut: a binding on a key outside carbonKeyCodes (keypad, Home) never reads as pressed, so it is
    // always a miss with Input Monitoring; add the key to that table when such a binding shows up.
    if input.listening { return switchMethod(input) == .hotkey }
    guard let held = input.lastHeld[binding.modifiers] else { return false }
    return input.now - held <= graceSeconds
}

/// The user made the switch: a key went down, or a click landed on the Dock, Stage Manager or the app
/// itself, shortly before. A link or a notification is a click on another app, so it does not count.
private func userChose(_ input: MissInput) -> Bool {
    let recent = { (at: TimeInterval) in (0...graceSeconds).contains(input.now - at) }
    if let key = input.lastKeyAt, recent(key) { return true }
    guard let click = input.lastClick, recent(click.at), let target = click.bundleID else { return false }
    return target == input.activated || switcherApps.contains(target)
}

/// How a switch turned out, or nil when the activation is not the user switching apps.
public func switchOutcome(_ input: MissInput, bindings: [Binding], ownBundleID: String?) -> Outcome? {
    guard isUserSwitch(input, ownBundleID: ownBundleID) else { return nil }
    let binding = bindings.first { $0.bundleID == input.activated }
    if let binding, usedHotkey(binding, input) { return .hit }
    guard userChose(input) else { return .system }
    return binding == nil ? .unbound : .miss
}

/// The binding that should have been used, or nil when this activation is not a miss.
public func missedBinding(_ input: MissInput, bindings: [Binding], ownBundleID: String?) -> Binding? {
    guard switchOutcome(input, bindings: bindings, ownBundleID: ownBundleID) == .miss else { return nil }
    return bindings.first { $0.bundleID == input.activated }
}

/// How the user reached the app, from the latest key press at or before the activation.
public func switchMethod(_ input: MissInput) -> Method {
    guard let last = input.lastPress else { return .other }
    let age = input.now - last.at
    switch last.press {
    case .bound(let binding) where binding.bundleID == input.activated && (0...graceSeconds).contains(age): return .hotkey
    case .commandTab where (0...commandTabSeconds).contains(age): return .commandTab
    default: return .other
    }
}

/// Decides when the hold guide is visible from a stream of "is hyper held" samples.
public struct HoldTracker {
    public static let delay = 0.7
    private var heldSince: TimeInterval?
    private var activatedAt: TimeInterval?

    public init() {}

    /// `pressedAt`: when the hyper key went down, if known. It starts the hold even when no sample saw the key up.
    public mutating func update(hyperHeld: Bool, pressedAt: TimeInterval? = nil, now: TimeInterval) -> Bool {
        guard hyperHeld else {
            heldSince = nil
            return false
        }
        let since = pressedAt ?? heldSince ?? now
        heldSince = since
        if let activatedAt, activatedAt >= since { return false }
        return now - since >= Self.delay
    }

    public mutating func boundAppActivated(now: TimeInterval) { activatedAt = now }
}
