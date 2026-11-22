import Foundation

/// A hotkey counts as used if its modifiers were held this recently before the app came forward (covers cold launches).
public let graceSeconds = 3.0
/// An app coming forward this soon after the previous one quit or hid was macOS's doing, not a choice.
public let quitHideSeconds = 0.5

public struct MissInput {
    public var activated: String
    public var previousFrontmost: String?
    public var now: TimeInterval
    public var lastHeld: [Int: TimeInterval]
    public var lastQuitOrHide: (bundleID: String, at: TimeInterval)?

    public init(activated: String, previousFrontmost: String?, now: TimeInterval,
                lastHeld: [Int: TimeInterval] = [:],
                lastQuitOrHide: (bundleID: String, at: TimeInterval)? = nil) {
        self.activated = activated
        self.previousFrontmost = previousFrontmost
        self.now = now
        self.lastHeld = lastHeld
        self.lastQuitOrHide = lastQuitOrHide
    }
}

/// The binding that should have been used, or nil when this activation is not a miss.
public func missedBinding(_ input: MissInput, bindings: [Binding], ownBundleID: String?) -> Binding? {
    guard !input.activated.isEmpty,
          input.activated != ownBundleID,
          input.activated != input.previousFrontmost,
          let binding = bindings.first(where: { $0.bundleID == input.activated })
    else { return nil }
    if let held = input.lastHeld[binding.modifiers], input.now - held <= graceSeconds { return nil }
    if let gone = input.lastQuitOrHide, gone.bundleID == input.previousFrontmost,
       input.now - gone.at <= quitHideSeconds { return nil }
    return binding
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
