// Verification probe for Shortcut Coach. Compiled by coach.sh; not part of the app.
//   probe windows <pid>     one line per window of <pid>: layer, on-screen flag, bounds (CG coords, top-left origin)
//   probe hyper <seconds>   posts hyper (ctrl+opt+shift+cmd) as modifier flags, holds, then releases
//   probe front             bundle id of the frontmost app
import AppKit
import CoreGraphics

func postFlags(_ flags: CGEventFlags) {
    let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: 0x3B, keyDown: !flags.isEmpty)!  // left control
    e.type = .flagsChanged
    e.flags = flags
    e.post(tap: .cghidEventTap)
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "windows":
    guard let pid = args.dropFirst().first.flatMap(Int32.init) else { exit(2) }
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where w[kCGWindowOwnerPID as String] as? Int32 == pid {
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let n = { (k: String) in Int(b[k] as? Double ?? 0) }
        let on = w[kCGWindowIsOnscreen as String] as? Bool ?? false
        print("layer=\(w[kCGWindowLayer as String] as? Int ?? -1) onscreen=\(on) x=\(n("X")) y=\(n("Y")) w=\(n("Width")) h=\(n("Height"))")
    }
case "hyper":
    let seconds = args.dropFirst().first.flatMap(Double.init) ?? 1.5
    guard AXIsProcessTrusted() else {
        FileHandle.standardError.write("probe: not trusted for Accessibility; posted events would be dropped\n".data(using: .utf8)!)
        exit(3)
    }
    let hyper: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    // Never leave the modifiers stuck down, even when interrupted.
    signal(SIGINT) { _ in exit(130) }
    signal(SIGTERM) { _ in exit(143) }
    atexit { postFlags([]) }
    postFlags(hyper)
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {  // re-post so a stray event cannot clear the flags mid-hold
        Thread.sleep(forTimeInterval: 0.1)
        postFlags(hyper)
    }
    // One posted release sometimes leaves the session flags at hyper, which held the guide open
    // past the hold; repost until they read clear.
    for _ in 0..<20 {
        postFlags([])
        Thread.sleep(forTimeInterval: 0.05)
        if CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: hyper) { exit(0) }
    }
    FileHandle.standardError.write("probe: hyper flags still set after release\n".data(using: .utf8)!)
    exit(4)
case "strip":  // screencapture -R rect: the top-centre 900x220 pt of the primary screen, where islands drop
    let f = NSScreen.screens.first?.frame ?? .zero
    print("\(Int(f.midX) - 450),0,900,220")
case "front":
    print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
default:
    FileHandle.standardError.write("usage: probe windows <pid> | hyper <seconds> | strip | front\n".data(using: .utf8)!)
    exit(2)
}
