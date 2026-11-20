import AppKit
import CoachCore

/// Shown while hyper is held: the hyper bindings in an island under the notch,
/// and a letter badge on each bound app's visible window.
@MainActor
final class Guide {
    private let island = Island()
    private var badges: [NSPanel] = []

    func show() {
        let prefs = loadTinycastPrefs()
        let bindings = parseBindings(prefs).filter(\.isHyper).sorted { $0.keyName < $1.keyName }
        showStrip(bindings, prefs: prefs)
        showBadges(bindings)
    }

    func hide() {
        island.hide()
        hideBadges()
    }

    /// One cell per installed hyper-bound app (icon over keycap), plus "Hide others" when it is on hyper.
    private func showStrip(_ bindings: [Binding], prefs: [String: Any]) {
        guard let screen = pointerScreen() else { return }
        let scale = screen.backingScaleFactor
        var cells: [(top: CALayer, key: String)] = bindings.compactMap { binding in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID) else { return nil }
            return (iconLayer(NSWorkspace.shared.icon(forFile: url.path), side: 36, scale: scale), binding.keyName)
        }
        if let combo = parseCombo(prefs["hotkey.systemAction.hide-all-apps-except-frontmost"]), combo.modifiers == hyperModifiers {
            let key = Binding(bundleID: "", keyCode: combo.keyCode, modifiers: combo.modifiers).keyName
            cells.append((textLayer("Hide others", size: 13, weight: .regular, scale: scale), key))
        }
        guard !cells.isEmpty else { return }

        let padding: CGFloat = 12, iconSlot: CGFloat = 36, gap: CGFloat = 6, spacing: CGFloat = 16
        let height = padding + 26 + gap + iconSlot + padding
        let row = CALayer()
        var x: CGFloat = 0
        for cell in cells {
            let cap = keycapLayer(cell.key, scale: scale)
            let width = max(cell.top.frame.width, cap.frame.width)
            cap.frame.origin = CGPoint(x: x + (width - cap.frame.width) / 2, y: padding)
            cell.top.frame.origin = CGPoint(x: x + (width - cell.top.frame.width) / 2,
                                            y: padding + 26 + gap + (iconSlot - cell.top.frame.height) / 2)
            row.addSublayer(cap)
            row.addSublayer(cell.top)
            x += width + spacing
        }
        island.show(row, size: CGSize(width: x - spacing, height: height), sidePadding: 20, on: screen)
    }

    private func showBadges(_ bindings: [Binding]) {
        var letters: [Int32: String] = [:]
        for binding in bindings {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: binding.bundleID) {
                letters[app.processIdentifier] = binding.keyName
            }
        }
        let side: CGFloat = 76
        let margin: CGFloat = 20  // spare window so the spring's overshoot and the blur are not clipped
        let window = side + 2 * margin
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (pid, point) in badgePoints(windows: onScreenWindows(), pids: Set(letters.keys)) {
            let scale = NSScreen.screens.first { $0.frame.contains(point) }?.backingScaleFactor ?? 2
            let panel = makeOverlayPanel()
            panel.setFrame(NSRect(x: point.x - window / 2, y: point.y - window / 2, width: window, height: window), display: false)
            let root = CALayer()
            let host = NSView()
            host.layer = root  // layer-hosting, so the badge layer can blur
            host.wantsLayer = true
            host.layerUsesCoreImageFilters = true
            panel.contentView = host

            let badge = CALayer()
            badge.frame = CGRect(x: margin, y: margin, width: side, height: side)
            badge.backgroundColor = NSColor.black.cgColor
            badge.cornerRadius = 18
            badge.borderColor = NSColor(white: 1, alpha: 0.3).cgColor  // keeps the badge visible on dark windows
            badge.borderWidth = 1
            let letter = textLayer(letters[pid] ?? "", size: 40, weight: .bold, scale: scale)
            letter.frame.origin = CGPoint(x: (side - letter.frame.width) / 2, y: (side - letter.frame.height) / 2)
            badge.addSublayer(letter)
            addBlurFilter(badge)
            root.addSublayer(badge)

            panel.orderFrontRegardless()
            if animate { materialize(badge) }
            badges.append(panel)
        }
    }

    /// Plays the exit on each badge, then takes its window off screen.
    private func hideBadges() {
        let leaving = badges
        badges = []
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            leaving.forEach { $0.orderOut(nil) }
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { leaving.forEach { $0.orderOut(nil) } }
        for panel in leaving {
            if let badge = panel.contentView?.layer?.sublayers?.first { dematerialize(badge) }
        }
        CATransaction.commit()
    }
}
