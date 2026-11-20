import CoachCore
import CoreGraphics

/// The modifiers down right now, as a Carbon mask. Needs no permission.
/// Tinycast's hyper (Caps Lock) shows up here as all four modifiers; verified in the plan's Task 0.
func heldModifiers() -> Int {
    let flags = CGEventSource.flagsState(.combinedSessionState)
    var mask = 0
    if flags.contains(.maskCommand) { mask |= 256 }
    if flags.contains(.maskShift) { mask |= 512 }
    if flags.contains(.maskAlternate) { mask |= 2048 }
    if flags.contains(.maskControl) { mask |= 4096 }
    return mask
}

func hyperHeld() -> Bool { heldModifiers() == hyperModifiers }
