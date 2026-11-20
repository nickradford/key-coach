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
        badges.forEach { $0.orderOut(nil) }
        badges = []
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
        for (pid, point) in badgePoints(windows: onScreenWindows(), pids: Set(letters.keys)) {
            let panel = makeOverlayPanel()
            panel.setFrame(NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side), display: false)
            guard let box = panel.contentView else { continue }
            box.layer?.backgroundColor = NSColor.black.cgColor
            box.layer?.cornerRadius = 18
            box.layer?.borderColor = NSColor(white: 1, alpha: 0.3).cgColor  // keeps the badge visible on dark windows
            box.layer?.borderWidth = 1
            let label = NSTextField(labelWithString: letters[pid] ?? "")
            label.font = .systemFont(ofSize: 40, weight: .bold)
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: box.centerXAnchor), label.centerYAnchor.constraint(equalTo: box.centerYAnchor)])
            fadeIn(panel)
            badges.append(panel)
        }
    }

    private func fadeIn(_ panel: NSPanel) {
        let instant = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = instant ? 1 : 0
        panel.orderFrontRegardless()
        if !instant {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }
}
