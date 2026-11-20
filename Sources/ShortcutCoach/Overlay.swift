import AppKit
import CoachCore

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A transparent panel that floats over everything, on every Space, and never takes focus or clicks.
@MainActor func makeOverlayPanel() -> NSPanel {
    let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    // Alcove's notch windows sit just below the maximum level (measured: 2147483629), so go above them.
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    let root = NSView()
    root.wantsLayer = true
    panel.contentView = root
    return panel
}

/// The hardware notch's rect in screen coordinates, or nil when the screen has none.
@MainActor func hardwareNotch(on screen: NSScreen) -> NSRect? {
    let frame = screen.frame
    let height = screen.safeAreaInsets.top
    guard height > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
    return NSRect(x: frame.minX + left.width, y: frame.maxY - height,
                  width: frame.width - left.width - right.width, height: height)
}

/// The notch the overlays grow from: the hardware notch, Alcove's fake notch on other screens,
/// or a zero-height sliver at the top centre.
@MainActor func notchRect(on screen: NSScreen) -> NSRect {
    if let notch = hardwareNotch(on: screen) { return notch }
    return notchlessStart(screenFrame: screen.frame,
                          menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                          builtInNotchWidth: NSScreen.screens.lazy.compactMap(hardwareNotch).first?.width,
                          alcoveOnAllDisplays: alcoveOnAllDisplays())
}

/// Whether Alcove is running and set to show its notch on every display.
@MainActor func alcoveOnAllDisplays() -> Bool {
    let id = "com.henrikruscon.Alcove"
    guard !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else { return false }
    return CFPreferencesCopyAppValue("showOnDisplay" as CFString, id as CFString) as? String == "allDisplays"
}

/// On-screen normal windows, front to back, in AppKit screen coordinates. Reads no titles or contents.
@MainActor func onScreenWindows() -> [WindowInfo] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
    // CoreGraphics measures from the top-left of the primary screen; AppKit from its bottom-left.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return list.compactMap { info in
        guard info[kCGWindowLayer as String] as? Int == 0,
              let pid = info[kCGWindowOwnerPID as String] as? Int32,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let cg = CGRect(dictionaryRepresentation: boundsDict)
        else { return nil }
        return WindowInfo(pid: pid, bounds: CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height))
    }
}

@MainActor func pointerScreen() -> NSScreen? {
    NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.screens.first
}

/// Screen holding the app's frontmost window; the pointer's screen when it has none or overlaps no screen.
@MainActor func screen(for app: NSRunningApplication) -> NSScreen? {
    let screens = NSScreen.screens
    if let window = onScreenWindows().first(where: { $0.pid == app.processIdentifier }),
       let index = screenIndex(forWindowBounds: window.bounds, screenFrames: screens.map(\.frame)) {
        return screens[index]
    }
    return pointerScreen()
}

/// One key drawn as a keycap: white text on a translucent rounded square.
@MainActor func keycap(_ text: String, size: CGFloat = 14) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: .semibold)
    label.textColor = .white
    label.translatesAutoresizingMaskIntoConstraints = false
    let box = NSView()
    box.wantsLayer = true
    box.layer?.backgroundColor = NSColor(white: 1, alpha: 0.2).cgColor
    box.layer?.cornerRadius = 6
    box.addSubview(label)
    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        box.widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 12),
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: size + 12),
        box.heightAnchor.constraint(equalToConstant: size + 12),
    ])
    return box
}
