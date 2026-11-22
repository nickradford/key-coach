import AppKit
import CoachCore

/// The quiet flash: the island drops from the notch, shows the shortcut that should have been
/// used, and retracts.
@MainActor
final class Flash {
    private static let height: CGFloat = 52

    private let island = Island()
    private var generation = 0

    func show(_ binding: Binding, app: NSRunningApplication, hold: TimeInterval, label: String? = nil) {
        guard let screen = screen(for: app) else { return }
        show(binding, icon: app.icon, name: app.localizedName ?? binding.bundleID, on: screen, hold: hold, label: label)
    }

    /// The app's hotkey has just been learned: the same island, marked learned and held a little longer.
    func celebrate(_ binding: Binding, app: NSRunningApplication) {
        show(binding, app: app, hold: 2, label: "✓ Learned")
    }

    /// A sample flash for `binding`, as if its app had just been brought forward the long way.
    func demo(_ binding: Binding) {
        guard let screen = NSScreen.main ?? pointerScreen() else { return }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID)
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        var name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? binding.bundleID
        if name.hasSuffix(".app") { name.removeLast(4) }  // when Finder is set to show extensions
        show(binding, icon: icon, name: name, on: screen)
    }

    /// `hold`: from the start of the drop to the start of the retract.
    func show(_ binding: Binding, icon: NSImage?, name: String, on screen: NSScreen,
              hold: TimeInterval = Fluency.learning.flashHold!, label: String? = nil) {
        generation += 1
        let mine = generation
        let (row, size) = content(binding, icon: icon, name: name, label: label, scale: screen.backingScaleFactor)
        island.show(row, size: size, sidePadding: 16, on: screen)
        Task {
            try? await Task.sleep(for: .seconds(hold))
            if mine == generation { island.hide() }  // a newer flash restarts the hold
        }
    }

    /// Icon, app name, then one keycap per modifier glyph ("⇪", or "⇧" and "⌘") and the key, then `label`.
    private func content(_ binding: Binding, icon: NSImage?, name: String, label: String?, scale: CGFloat) -> (CALayer, CGSize) {
        let row = CALayer()
        var x: CGFloat = 0
        func place(_ layer: CALayer, gap: CGFloat) {
            layer.frame.origin = CGPoint(x: x, y: (Self.height - layer.frame.height) / 2)
            row.addSublayer(layer)
            x += layer.frame.width + gap
        }
        place(iconLayer(icon, side: 26, scale: scale), gap: 8)
        place(textLayer(name, weight: .medium, scale: scale, maxWidth: 180), gap: 12)
        let display = binding.display(hyper: HyperKeyListener.shared.hyperKey)
        let glyphs = display.prefix(while: { $0 != " " }).map(String.init)
        for cap in glyphs + [binding.keyName] { place(keycapLayer(cap, scale: scale), gap: 4) }
        if let label {
            x += 8
            place(textLayer(label, weight: .semibold, scale: scale), gap: 4)
        }
        return (row, CGSize(width: x - 4, height: Self.height))
    }
}
