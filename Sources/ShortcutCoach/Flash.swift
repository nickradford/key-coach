import AppKit
import CoachCore

/// The quiet flash: the island drops from the notch, shows the shortcut that should have been
/// used, and retracts.
@MainActor
final class Flash {
    private static let hold = 1.6  // from the start of the drop to the start of the retract
    private static let height: CGFloat = 52

    private let island = Island()
    private var generation = 0

    func show(_ binding: Binding, app: NSRunningApplication) {
        guard let screen = screen(for: app) else { return }
        generation += 1
        let mine = generation
        let (row, size) = content(binding, app: app, scale: screen.backingScaleFactor)
        island.show(row, size: size, sidePadding: 16, on: screen)
        Task {
            try? await Task.sleep(for: .seconds(Self.hold))
            if mine == generation { island.hide() }  // a newer flash restarts the hold
        }
    }

    /// Icon, app name, then one keycap per modifier glyph ("⇪", or "⇧" and "⌘") and the key.
    private func content(_ binding: Binding, app: NSRunningApplication, scale: CGFloat) -> (CALayer, CGSize) {
        let row = CALayer()
        var x: CGFloat = 0
        func place(_ layer: CALayer, gap: CGFloat) {
            layer.frame.origin = CGPoint(x: x, y: (Self.height - layer.frame.height) / 2)
            row.addSublayer(layer)
            x += layer.frame.width + gap
        }
        place(iconLayer(app.icon, side: 26, scale: scale), gap: 8)
        place(textLayer(app.localizedName ?? binding.bundleID, weight: .medium, scale: scale, maxWidth: 180), gap: 12)
        let glyphs = binding.display.prefix(while: { $0 != " " }).map(String.init)
        for label in glyphs + [binding.keyName] { place(keycapLayer(label, scale: scale), gap: 4) }
        return (row, CGSize(width: x - 4, height: Self.height))
    }
}
