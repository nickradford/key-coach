import CoachCore
import CoreGraphics
import Foundation
import IOKit.hid

/// The modifiers down right now, as a Carbon mask.
/// Hyper comes from the physical hyper key when Input Monitoring is granted. The fallback, the
/// modifier flags Tinycast posts for hyper, needs no permission but reads as released after a mouse move.
@MainActor func heldModifiers() -> Int {
    if HyperKeyListener.shared.isDown { return hyperModifiers }
    let flags = CGEventSource.flagsState(.combinedSessionState)
    var mask = 0
    if flags.contains(.maskCommand) { mask |= 256 }
    if flags.contains(.maskShift) { mask |= 512 }
    if flags.contains(.maskAlternate) { mask |= 2048 }
    if flags.contains(.maskControl) { mask |= 4096 }
    return mask
}

@MainActor func hyperHeld() -> Bool { heldModifiers() == hyperModifiers }

/// The hyper key: Tinycast's setting, else the key chosen in onboarding, else Caps Lock. Read fresh.
@MainActor func currentHyperKey() -> HyperKey {
    resolveHyperKey(tinycast: tinycastHyperKey(loadTinycastPrefs()),
                    stored: UserDefaults.standard.string(forKey: "hyperKey"))
}

/// Watches the physical hyper key on every keyboard through the raw HID device, listen-only.
/// Tracks the keys that can be hyper (Caps Lock, F18 which Tinycast remaps it to, and the right-hand
/// modifiers). Any other key-down is kept only as a `KeyPress`, and only while a binding's modifiers
/// are held or for Command-Tab; every other key is dropped before anything is stored.
/// Needs Input Monitoring, which onboarding asks for; keeps trying to start until it is granted.
@MainActor
final class HyperKeyListener {
    static let shared = HyperKeyListener()

    private(set) var isDown = false
    /// When the hyper key last went down (system uptime). Kept after release, so a press between two samples still counts.
    private(set) var pressedAt: TimeInterval?
    private(set) var hyperKey: HyperKey = .capsLock
    /// The latest key press kept, with its time (system uptime). Never ordinary typing.
    private(set) var lastPress: (press: KeyPress, at: TimeInterval)?
    private var bindings: [Binding] = []
    /// Called with any hyper-candidate key pressed down, while onboarding asks the user to press theirs.
    var capture: (@MainActor (HyperKey) -> Void)?
    private var manager: IOHIDManager?
    private var timer: Timer?

    static var access: IOHIDAccessType { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) }

    /// Shows the system Input Monitoring prompt the first time, then starts listening if granted.
    static func requestAccess() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        _ = shared.open()
    }

    /// Starts listening when permitted. Once a second, re-reads the hyper key and bindings, and retries until permitted.
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { HyperKeyListener.shared.refresh() }
        }
    }

    private func refresh() {
        refreshHyperKey()
        bindings = parseBindings(loadTinycastPrefs())
        _ = open()
    }

    func refreshHyperKey() {
        let key = currentHyperKey()
        if key != hyperKey { isDown = false }
        hyperKey = key
    }

    private func handle(_ key: HyperKey, down: Bool, at time: TimeInterval) {
        if down { capture?(key) }  // first, so a newly chosen key lights on this very press
        guard key == hyperKey else { return }
        isDown = down
        if down { pressedAt = time }
    }

    private func handleKeyDown(_ keyCode: Int, at time: TimeInterval) {
        guard let press = classifyKey(keyCode: keyCode, held: heldModifiers(), bindings: bindings) else { return }
        lastPress = (press, time)
    }

    /// An IOHIDValue timestamp in seconds of system uptime: both count mach absolute time.
    private static func uptime(_ value: IOHIDValue) -> TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(IOHIDValueGetTimeStamp(value)) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }

    /// Opens the keyboard devices; false while Input Monitoring is not granted.
    private func open() -> Bool {
        guard manager == nil, Self.access == kIOHIDAccessTypeGranted else { return manager != nil }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, [
            kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,
        ] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
            let usage = IOHIDElementGetUsage(IOHIDValueGetElement(value))
            let down = IOHIDValueGetIntegerValue(value) != 0
            // The key's own time, not this callback's: the main thread may handle it after a later app switch.
            let time = HyperKeyListener.uptime(value)
            MainActor.assumeIsolated {  // scheduled on the main run loop below
                if let key = HyperKey(hidUsage: usage) {
                    HyperKeyListener.shared.handle(key, down: down, at: time)
                } else if down, let keyCode = carbonKeyCode(hidUsage: usage) {
                    HyperKeyListener.shared.handleKeyDown(keyCode, at: time)
                }
            }
        }, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }
        self.manager = manager
        return true
    }
}
