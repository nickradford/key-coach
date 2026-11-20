import AppKit
import CoachCore

/// Shown while hyper is held: a strip of the hyper bindings under the notch,
/// and a letter badge on each bound app's visible window.
@MainActor
final class Guide {
    private let strip = makeOverlayPanel()
    private let pill = NSView()
    private var row = NSStackView()
    private var badges: [NSPanel] = []

    init() {
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.cgColor
        pill.layer?.cornerRadius = 18
        pill.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // bottom corners
        strip.contentView?.addSubview(pill)
    }

    func show() {
        let prefs = loadTinycastPrefs()
        let bindings = parseBindings(prefs).filter(\.isHyper).sorted { $0.keyName < $1.keyName }
        showStrip(bindings, prefs: prefs)
        showBadges(bindings)
    }

    func hide() {
        strip.orderOut(nil)
        badges.forEach { $0.orderOut(nil) }
        badges = []
    }

    private func showStrip(_ bindings: [Binding], prefs: [String: Any]) {
        guard let screen = pointerScreen() else { return }
        var cells: [NSView] = bindings.compactMap { binding in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID) else { return nil }
            let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 36), icon.heightAnchor.constraint(equalToConstant: 36)])
            return cell(top: icon, key: binding.keyName)
        }
        if let combo = parseCombo(prefs["hotkey.systemAction.hide-all-apps-except-frontmost"]), combo.modifiers == hyperModifiers {
            let label = NSTextField(labelWithString: "Hide others")
            label.font = .systemFont(ofSize: 13)
            label.textColor = .white
            cells.append(cell(top: label, key: Binding(bundleID: "", keyCode: combo.keyCode, modifiers: combo.modifiers).keyName))
        }
        guard !cells.isEmpty else { return }

        row.removeFromSuperview()
        row = NSStackView(views: cells)
        row.spacing = 16
        row.alignment = .bottom
        let content = row.fittingSize
        let notch = notchRect(on: screen)
        let size = NSSize(width: max(content.width + 40, notch.width + 60), height: notch.height + content.height + 24)
        strip.setFrame(NSRect(x: notch.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: false)
        pill.frame = NSRect(origin: .zero, size: size)
        row.frame = NSRect(x: (size.width - content.width) / 2, y: 12, width: content.width, height: content.height)
        strip.contentView?.addSubview(row)
        fadeIn(strip)
    }

    private func cell(top: NSView, key: String) -> NSView {
        let cell = NSStackView(views: [top, keycap(key)])
        cell.orientation = .vertical
        cell.spacing = 6
        return cell
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
