import CoachCore
import CoreGraphics
import Foundation
import IOKit.hid

/// The modifiers down right now, as a Carbon mask.
/// Hyper comes from the physical Caps Lock when Input Monitoring is granted. The fallback, the
/// modifier flags Tinycast posts for hyper, needs no permission but reads as released after a mouse move.
@MainActor func heldModifiers() -> Int {
    if CapsLock.shared.isDown { return hyperModifiers }
    let flags = CGEventSource.flagsState(.combinedSessionState)
    var mask = 0
    if flags.contains(.maskCommand) { mask |= 256 }
    if flags.contains(.maskShift) { mask |= 512 }
    if flags.contains(.maskAlternate) { mask |= 2048 }
    if flags.contains(.maskControl) { mask |= 4096 }
    return mask
}

@MainActor func hyperHeld() -> Bool { heldModifiers() == hyperModifiers }

/// Watches the physical Caps Lock key on every keyboard through the raw HID device, listen-only.
/// Sees only Caps Lock (and F18, which Tinycast remaps it to); every other key is ignored.
/// Needs Input Monitoring: asks once, then keeps trying to start until it is granted.
@MainActor
final class CapsLock {
    static let shared = CapsLock()

    private(set) var isDown = false
    private var manager: IOHIDManager?
    private var retry: Timer?

    func start() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)  // shows the system prompt the first time
        }
        guard !open() else { return }
        retry = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                if CapsLock.shared.open() { CapsLock.shared.retry?.invalidate() }
            }
        }
    }

    /// Opens the keyboard devices; false while Input Monitoring is not granted.
    private func open() -> Bool {
        guard manager == nil, IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            return manager != nil
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, [
            kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,
        ] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
            let element = IOHIDValueGetElement(value)
            let usage = IOHIDElementGetUsage(element)
            guard usage == kHIDUsage_KeyboardCapsLock || usage == kHIDUsage_KeyboardF18 else { return }
            let down = IOHIDValueGetIntegerValue(value) != 0
            MainActor.assumeIsolated { CapsLock.shared.isDown = down }  // scheduled on the main run loop below
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
