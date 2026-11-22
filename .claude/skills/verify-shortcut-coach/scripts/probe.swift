// Verification probe for Shortcut Coach. Compiled by coach.sh; not part of the app.
//   probe windows <pid>     one line per window of <pid>: layer, on-screen flag, bounds (CG coords, top-left origin)
//   probe hyper <seconds>   posts hyper (ctrl+opt+shift+cmd) as modifier flags, holds, then releases
//   probe front             bundle id of the frontmost app
//   probe dock <bundle-id>  a real left click on that app's Dock icon, then the cursor goes back
//   probe listen            whether this shell's app has Input Monitoring (the coach inherits it)
//   probe keyago            seconds since any key last went down, as the coach reads it
import AppKit
import IOKit.hid

func postFlags(_ flags: CGEventFlags) {
    let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: 0x3B, keyDown: !flags.isEmpty)!  // left control
    e.type = .flagsChanged
    e.flags = flags
    e.post(tap: .cghidEventTap)
}

func postMouse(_ type: CGEventType, at point: CGPoint) {
    CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
            mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
}

func requireAccessibility() {
    guard AXIsProcessTrusted() else {
        FileHandle.standardError.write("probe: not trusted for Accessibility; posted events would be dropped\n".data(using: .utf8)!)
        exit(3)
    }
}

/// The Dock icon of the app with this bundle id: its frame in CG coordinates, read again on each call.
func dockIcon(_ id: String) -> (() -> CGRect)? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    let lists = value(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute) as? [AXUIElement] ?? []
    let items = lists.flatMap { value($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    guard let icon = items.first(where: { (value($0, kAXURLAttribute) as? URL).flatMap { Bundle(url: $0)?.bundleIdentifier } == id })
    else { return nil }
    return {
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(value(icon, kAXPositionAttribute) as! AXValue, .cgPoint, &origin)
        AXValueGetValue(value(icon, kAXSizeAttribute) as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
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
    requireAccessibility()
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
case "dock":
    guard let id = args.dropFirst().first else { exit(2) }
    requireAccessibility()
    guard let frame = dockIcon(id) else {
        FileHandle.standardError.write("probe: \(id) has no Dock icon\n".data(using: .utf8)!)
        exit(5)
    }
    // shortcut: assumes the Dock is on the main display; look up the icon's screen when that changes.
    let screen = CGDisplayBounds(CGMainDisplayID()).insetBy(dx: 1, dy: 1)
    let back = CGEvent(source: nil)!.location
    var icon = frame()
    if !screen.contains(CGPoint(x: icon.midX, y: icon.midY)) {
        // A hidden Dock lists its icons off screen. Rest the cursor on the screen edge nearest them to show it.
        postMouse(.mouseMoved, at: CGPoint(x: min(max(icon.midX, screen.minX), screen.maxX),
                                           y: min(max(icon.midY, screen.minY), screen.maxY)))
        for _ in 0..<30 where !screen.contains(CGPoint(x: icon.midX, y: icon.midY)) {
            Thread.sleep(forTimeInterval: 0.1)
            icon = frame()
        }
    }
    let target = CGPoint(x: icon.midX, y: icon.midY)
    postMouse(.leftMouseDown, at: target)
    Thread.sleep(forTimeInterval: 0.05)
    postMouse(.leftMouseUp, at: target)
    Thread.sleep(forTimeInterval: 0.05)
    postMouse(.mouseMoved, at: back)  // a posted move, not a warp, so a hidden Dock sees the cursor leave
    print("clicked \(id) Dock icon at \(Int(target.x)),\(Int(target.y)); cursor back at \(Int(back.x)),\(Int(back.y))")
case "keyago":
    print(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown))
case "listen":
    print(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted ? "granted" : "not granted")
default:
    FileHandle.standardError.write("usage: probe windows <pid> | hyper <seconds> | strip | front | dock <bundle-id> | listen | keyago\n".data(using: .utf8)!)
    exit(2)
}
