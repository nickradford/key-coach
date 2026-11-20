import AppKit
import CoachCore

/// The quiet flash: the notch grows, shows the shortcut that should have been used, and shrinks back.
@MainActor
final class Flash {
    private static let hold = 1.2
    private static let grow = 0.28
    private static let shrink = 0.22

    private let panel = makeOverlayPanel()
    private let pill = NSView()
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let keys = NSStackView()
    private lazy var row = NSStackView(views: [icon, name, keys])
    private var generation = 0

    init() {
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.cgColor
        pill.layer?.cornerRadius = 16
        pill.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // bottom corners
        name.font = .systemFont(ofSize: 14, weight: .medium)
        name.textColor = .white
        name.lineBreakMode = .byTruncatingTail
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        keys.spacing = 4
        row.spacing = 8
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 26), icon.heightAnchor.constraint(equalToConstant: 26)])
        panel.contentView?.addSubview(pill)
        panel.contentView?.addSubview(row)
    }

    func show(_ binding: Binding, app: NSRunningApplication) {
        guard let screen = screen(for: app) else { return }
        generation += 1
        let mine = generation
        let notch = notchRect(on: screen)
        let size = NSSize(width: max(notch.width + 140, 320), height: notch.height + 52)
        let frame = NSRect(x: notch.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        let full = NSRect(origin: .zero, size: size)
        // The notch (or a sliver at the top edge) in the panel's own coordinates: where the shape grows from.
        let start = NSRect(x: (size.width - notch.width) / 2, y: size.height - notch.height, width: notch.width, height: notch.height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        icon.image = app.icon
        name.stringValue = app.localizedName ?? binding.bundleID
        keys.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for label in binding.display.split(separator: " ", maxSplits: 1).first.map({ $0.map(String.init) }) ?? [] {
            keys.addArrangedSubview(keycap(label))
        }
        keys.addArrangedSubview(keycap(binding.keyName))

        // A flash already showing here keeps its shape and just swaps content; otherwise start from the notch.
        if !(panel.isVisible && panel.frame == frame) {
            panel.setFrame(frame, display: false)
            pill.frame = reduceMotion ? full : start
            row.alphaValue = 0
            panel.alphaValue = reduceMotion ? 0 : 1
            panel.orderFrontRegardless()
        }
        row.frame = NSRect(x: 14, y: 0, width: size.width - 28, height: 52)

        Task {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.grow
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                pill.animator().frame = full
                row.animator().alphaValue = 1
                panel.animator().alphaValue = 1
            }
            try? await Task.sleep(for: .seconds(Self.hold))
            guard mine == generation else { return }  // a newer flash took over
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.shrink
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                row.animator().alphaValue = 0
                if reduceMotion { panel.animator().alphaValue = 0 } else { pill.animator().frame = start }
            }
            if mine == generation { panel.orderOut(nil) }
        }
    }
}
