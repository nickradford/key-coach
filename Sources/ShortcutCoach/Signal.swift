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
/// Sees only the keys that can be hyper (Caps Lock, F18 which Tinycast remaps it to, and the right-hand
/// modifiers); every other key is dropped before anything else happens.
/// Needs Input Monitoring, which onboarding asks for; keeps trying to start until it is granted.
@MainActor
final class HyperKeyListener {
    static let shared = HyperKeyListener()

    private(set) var isDown = false
    private(set) var hyperKey: HyperKey = .capsLock
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

    /// Starts listening when permitted. Once a second, re-reads the hyper key and retries until permitted.
    func start() {
        refreshHyperKey()
        _ = open()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                HyperKeyListener.shared.refreshHyperKey()
                _ = HyperKeyListener.shared.open()
            }
        }
    }

    func refreshHyperKey() {
        let key = currentHyperKey()
        if key != hyperKey { isDown = false }
        hyperKey = key
    }

    private func handle(_ key: HyperKey, down: Bool) {
        if down { capture?(key) }  // first, so a newly chosen key lights on this very press
        if key == hyperKey { isDown = down }
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
            guard let key = HyperKey(hidUsage: IOHIDElementGetUsage(IOHIDValueGetElement(value))) else { return }
            let down = IOHIDValueGetIntegerValue(value) != 0
            MainActor.assumeIsolated { HyperKeyListener.shared.handle(key, down: down) }  // scheduled on the main run loop below
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
