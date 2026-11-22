/// The physical key used as hyper. Tinycast always posts all four modifiers for it
/// (`hyperModifiers`); only which key the user holds varies.
public enum HyperKey: String, CaseIterable, Sendable {
    case capsLock, rightCommand, rightOption, rightControl, rightShift

    /// HID keyboard usages that mean this key is down. Caps Lock includes F18, which Tinycast remaps it to.
    public var hidUsages: Set<UInt32> {
        switch self {
        case .capsLock: [0x39, 0x6D]
        case .rightControl: [0xE4]
        case .rightShift: [0xE5]
        case .rightOption: [0xE6]
        case .rightCommand: [0xE7]
        }
    }

    public var glyph: String {
        switch self {
        case .capsLock: "⇪"
        case .rightCommand: "⌘"
        case .rightOption: "⌥"
        case .rightControl: "⌃"
        case .rightShift: "⇧"
        }
    }

    public var name: String {
        switch self {
        case .capsLock: "Caps Lock"
        case .rightCommand: "Right Command"
        case .rightOption: "Right Option"
        case .rightControl: "Right Control"
        case .rightShift: "Right Shift"
        }
    }

    public init?(hidUsage: UInt32) {
        guard let key = Self.allCases.first(where: { $0.hidUsages.contains(hidUsage) }) else { return nil }
        self = key
    }
}

/// Tinycast's `hyperKeyPhysicalKey` value (seen: "capsLock"), or nil when absent or unrecognised.
public func tinycastHyperKey(_ prefs: [String: Any]) -> HyperKey? {
    (prefs["hyperKeyPhysicalKey"] as? String).flatMap(HyperKey.init(rawValue:))
}

/// Tinycast's setting wins; then the user's stored choice; then Caps Lock.
public func resolveHyperKey(tinycast: HyperKey?, stored: String?) -> HyperKey {
    tinycast ?? stored.flatMap(HyperKey.init(rawValue:)) ?? .capsLock
}
