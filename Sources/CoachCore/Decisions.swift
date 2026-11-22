import Foundation

/// A hotkey counts as used if its modifiers were held this recently before the app came forward (covers cold launches).
public let graceSeconds = 3.0
/// An app coming forward this soon after the previous one quit or hid was macOS's doing, not a choice.
public let quitHideSeconds = 0.5
/// A Command-Tab press this recently before a switch made it. The switch lands when Command is released,
/// so this is how long the user may look at the switcher after the last Tab.
public let commandTabSeconds = 1.0

public struct MissInput {
    public var activated: String
    public var previousFrontmost: String?
    public var now: TimeInterval
    public var lastHeld: [Int: TimeInterval]
    public var lastQuitOrHide: (bundleID: String, at: TimeInterval)?
    /// The listener's latest key press and its time, on the same clock as `now`.
    public var lastPress: (press: KeyPress, at: TimeInterval)?

    public init(activated: String, previousFrontmost: String?, now: TimeInterval,
                lastHeld: [Int: TimeInterval] = [:],
                lastQuitOrHide: (bundleID: String, at: TimeInterval)? = nil,
                lastPress: (press: KeyPress, at: TimeInterval)? = nil) {
        self.activated = activated
        self.previousFrontmost = previousFrontmost
        self.now = now
        self.lastHeld = lastHeld
        self.lastQuitOrHide = lastQuitOrHide
        self.lastPress = lastPress
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

/// The binding that should have been used, or nil when this activation is not a miss.
public func missedBinding(_ input: MissInput, bindings: [Binding], ownBundleID: String?) -> Binding? {
    guard isUserSwitch(input, ownBundleID: ownBundleID),
          let binding = bindings.first(where: { $0.bundleID == input.activated })
    else { return nil }
    if let held = input.lastHeld[binding.modifiers], input.now - held <= graceSeconds { return nil }
    return binding
}

/// How a switch turned out, or nil when the activation is not the user switching apps.
public func switchOutcome(_ input: MissInput, bindings: [Binding], ownBundleID: String?) -> Outcome? {
    guard isUserSwitch(input, ownBundleID: ownBundleID) else { return nil }
    guard bindings.contains(where: { $0.bundleID == input.activated }) else { return .unbound }
    return missedBinding(input, bindings: bindings, ownBundleID: ownBundleID) == nil ? .hit : .miss
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
