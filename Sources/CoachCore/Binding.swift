import Carbon.HIToolbox
import Foundation

/// Carbon modifier mask for Tinycast's hyper key: control + option + shift + command.
public let hyperModifiers = 6912

public struct Binding: Equatable, Sendable {
    public let bundleID: String
    public let keyCode: Int
    public let modifiers: Int

    public init(bundleID: String, keyCode: Int, modifiers: Int) {
        self.bundleID = bundleID
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isHyper: Bool { modifiers == hyperModifiers }

    public var keyName: String { keyNames[keyCode] ?? "key \(keyCode)" }

    /// Modifier glyphs, a space, then the key; hyper shows as the hyper key's glyph.
    public func display(hyper: HyperKey) -> String {
        if isHyper { return "\(hyper.glyph) \(keyName)" }
        let glyphs = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined()
        return "\(glyphs) \(keyName)"
    }
}

/// Reads one Tinycast hotkey value: a JSON string `{"combo":{"_0":{"carbonKeyCode":1,"carbonModifiers":6912}}}`.
public func parseCombo(_ value: Any?) -> (keyCode: Int, modifiers: Int)? {
    guard let text = value as? String,
          let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
          let combo = (root["combo"] as? [String: Any])?["_0"] as? [String: Any],
          let keyCode = combo["carbonKeyCode"] as? Int,
          let modifiers = combo["carbonModifiers"] as? Int
    else { return nil }
    return (keyCode, modifiers)
}

public func parseBindings(_ prefs: [String: Any]) -> [Binding] {
    let prefix = "hotkey.app."
    return prefs.compactMap { key, value -> Binding? in
        guard key.hasPrefix(prefix), let combo = parseCombo(value) else { return nil }
        return Binding(bundleID: String(key.dropFirst(prefix.count)), keyCode: combo.keyCode, modifiers: combo.modifiers)
    }.sorted { $0.bundleID < $1.bundleID }
}

/// Tinycast's preferences, read fresh. Empty when Tinycast is not installed.
public func loadTinycastPrefs() -> [String: Any] {
    let domain = "com.abueammar.tinycast" as CFString
    CFPreferencesAppSynchronize(domain)
    return CFPreferencesCopyMultiple(nil, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
}

private let keyNames: [Int: String] = [
    kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
    kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
    kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
    kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
    kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
    kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
    kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑", kVK_Space: "Space",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
]
