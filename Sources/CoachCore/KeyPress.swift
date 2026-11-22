import Carbon.HIToolbox

/// A key-down kept by the listener. A key that is not a binding's key is reported without its identity.
public enum KeyPress: Equatable, Sendable {
    case bound(Binding)
    case unbound
    case commandTab
}

/// The Carbon virtual keycode (`kVK_*`, as in `Binding.keyCode`) for a HID keyboard usage (page 7),
/// or nil for a key outside the table (modifiers, keypad, navigation), which the listener drops.
public func carbonKeyCode(hidUsage: UInt32) -> Int? { carbonKeyCodes[hidUsage] }

/// What a key-down means while `held` (a Carbon modifier mask) is down, or nil to drop it.
/// Drops every key unless `held` is exactly some binding's modifiers, so typing never gets past here.
/// The one exception is Tab with Command, or Command-Shift: the app switcher.
public func classifyKey(keyCode: Int, held: Int, bindings: [Binding]) -> KeyPress? {
    guard held != 0 else { return nil }  // even if a binding has no modifiers, plain typing is never read
    let candidates = bindings.filter { $0.modifiers == held }
    if let binding = candidates.first(where: { $0.keyCode == keyCode }) { return .bound(binding) }
    // Before .unbound, so a binding on Command-Shift (768) does not hide a backwards app-switcher press.
    if keyCode == kVK_Tab, held & ~shiftKey == cmdKey { return .commandTab }
    return candidates.isEmpty ? nil : .unbound
}

private let carbonKeyCodes: [UInt32: Int] = [
    0x04: kVK_ANSI_A, 0x05: kVK_ANSI_B, 0x06: kVK_ANSI_C, 0x07: kVK_ANSI_D, 0x08: kVK_ANSI_E,
    0x09: kVK_ANSI_F, 0x0A: kVK_ANSI_G, 0x0B: kVK_ANSI_H, 0x0C: kVK_ANSI_I, 0x0D: kVK_ANSI_J,
    0x0E: kVK_ANSI_K, 0x0F: kVK_ANSI_L, 0x10: kVK_ANSI_M, 0x11: kVK_ANSI_N, 0x12: kVK_ANSI_O,
    0x13: kVK_ANSI_P, 0x14: kVK_ANSI_Q, 0x15: kVK_ANSI_R, 0x16: kVK_ANSI_S, 0x17: kVK_ANSI_T,
    0x18: kVK_ANSI_U, 0x19: kVK_ANSI_V, 0x1A: kVK_ANSI_W, 0x1B: kVK_ANSI_X, 0x1C: kVK_ANSI_Y,
    0x1D: kVK_ANSI_Z,
    0x1E: kVK_ANSI_1, 0x1F: kVK_ANSI_2, 0x20: kVK_ANSI_3, 0x21: kVK_ANSI_4, 0x22: kVK_ANSI_5,
    0x23: kVK_ANSI_6, 0x24: kVK_ANSI_7, 0x25: kVK_ANSI_8, 0x26: kVK_ANSI_9, 0x27: kVK_ANSI_0,
    0x28: kVK_Return, 0x29: kVK_Escape, 0x2A: kVK_Delete, 0x2B: kVK_Tab, 0x2C: kVK_Space,
    0x2D: kVK_ANSI_Minus, 0x2E: kVK_ANSI_Equal, 0x2F: kVK_ANSI_LeftBracket, 0x30: kVK_ANSI_RightBracket,
    0x31: kVK_ANSI_Backslash, 0x33: kVK_ANSI_Semicolon, 0x34: kVK_ANSI_Quote, 0x35: kVK_ANSI_Grave,
    0x36: kVK_ANSI_Comma, 0x37: kVK_ANSI_Period, 0x38: kVK_ANSI_Slash,
    0x3A: kVK_F1, 0x3B: kVK_F2, 0x3C: kVK_F3, 0x3D: kVK_F4, 0x3E: kVK_F5, 0x3F: kVK_F6,
    0x40: kVK_F7, 0x41: kVK_F8, 0x42: kVK_F9, 0x43: kVK_F10, 0x44: kVK_F11, 0x45: kVK_F12,
    0x68: kVK_F13, 0x69: kVK_F14, 0x6A: kVK_F15, 0x6B: kVK_F16, 0x6C: kVK_F17, 0x6D: kVK_F18,
    0x6E: kVK_F19, 0x6F: kVK_F20,
    0x4F: kVK_RightArrow, 0x50: kVK_LeftArrow, 0x51: kVK_DownArrow, 0x52: kVK_UpArrow,
]
