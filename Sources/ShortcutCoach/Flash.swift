import AppKit
import CoachCore

/// The quiet flash: like a notch island, the notch drops down on a spring, shows the shortcut
/// that should have been used, and retracts back up.
/// Drawn with plain Core Animation layers so every frame of the motion is explicit.
@MainActor
final class Flash {
    private static let hold = 1.2
    private static let retract = 0.24
    private static let rowHeight: CGFloat = 52
    private static let padding: CGFloat = 16  // between the hint and the island's sides
    private static let ear: CGFloat = 10      // radius of the inverted corners where the island meets the top edge

    private let panel = makeOverlayPanel()
    private let root = CALayer()
    private let pill = CALayer()     // black, clipped to the island shape by `shape`
    private let shape = CAShapeLayer()
    private let content = CALayer()  // icon, name and keycaps; slides down inside the pill
    private var generation = 0
    private var shownOn: NSScreen?

    init() {
        let host = NSView()
        host.layer = root  // layer-hosting: we own the geometry, AppKit does no layout
        host.wantsLayer = true
        panel.contentView = host
        pill.backgroundColor = NSColor.black.cgColor
        pill.mask = shape
        content.anchorPoint = CGPoint(x: 0.5, y: 0)
        root.addSublayer(pill)
        pill.addSublayer(content)
    }

    func show(_ binding: Binding, app: NSRunningApplication) {
        guard let screen = screen(for: app) else { return }
        generation += 1
        let mine = generation
        let notch = notchRect(on: screen)
        let row = buildContent(binding, app: app, scale: screen.backingScaleFactor)
        let islandWidth = max(row.width + 2 * Self.padding, notch.width)
        let size = CGSize(width: islandWidth + 2 * Self.ear, height: notch.height + Self.rowHeight)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Island: from the notch's own shape to one that hugs the hint. Content: from just above
        // the top edge (hidden) down into the band under the notch.
        let startPath = islandPath(width: notch.width, height: notch.height, ear: 0, in: size)
        let endPath = islandPath(width: islandWidth, height: size.height, ear: Self.ear, in: size)
        let startContent = CGPoint(x: size.width / 2, y: size.height)
        let endContent = CGPoint(x: size.width / 2, y: 0)

        let alreadyHere = panel.isVisible && shownOn == screen
        shownOn = screen
        panel.setFrame(NSRect(x: notch.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: false)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.removeAllAnimations()
        content.removeAllAnimations()
        root.frame = CGRect(origin: .zero, size: size)
        pill.frame = root.frame
        shape.frame = root.frame
        shape.path = endPath
        content.bounds = CGRect(origin: .zero, size: row)
        content.position = endContent
        content.opacity = 1
        panel.alphaValue = 1
        CATransaction.commit()

        if alreadyHere {
            // A flash is already showing on this screen: swap the content in place, no second drop.
        } else if reduceMotion {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        } else {
            panel.orderFrontRegardless()
            spring(shape, "path", from: startPath, to: endPath)
            spring(content, "position", from: startContent, to: endContent)
        }

        Task {
            try? await Task.sleep(for: .seconds(Self.hold + 0.3))
            guard mine == generation else { return }  // a newer flash took over
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, mine == generation else { return }
                panel.orderOut(nil)
            }
            if reduceMotion {
                NSAnimationContext.runAnimationGroup({ $0.duration = Self.retract; panel.animator().alphaValue = 0 }, completionHandler: nil)
                let wait = CABasicAnimation(keyPath: "opacity")  // keeps the transaction open until the fade ends
                wait.duration = Self.retract
                content.add(wait, forKey: "wait")
            } else {
                retract(shape, "path", to: startPath)
                retract(content, "position", to: startContent)
            }
            CATransaction.commit()
        }
    }

    // MARK: Motion

    private func spring(_ layer: CALayer, _ keyPath: String, from: Any, to: Any) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = 320
        animation.damping = 22  // a small overshoot, like the system's islands
        animation.duration = animation.settlingDuration
        animation.fromValue = from
        animation.toValue = to
        layer.add(animation, forKey: keyPath)
    }

    private func retract(_ layer: CALayer, _ keyPath: String, to: Any) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = layer.value(forKeyPath: keyPath)
        animation.toValue = to
        animation.duration = Self.retract
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
        layer.setValue(to, forKeyPath: keyPath)  // stay retracted when the animation ends
        layer.add(animation, forKey: keyPath)
    }

    // MARK: Shape

    /// A rounded-bottom island hanging from the top edge of a `size` canvas, centred, whose top
    /// corners curve outward into the edge (inverted corners), like the notch itself.
    /// Every call emits the same elements so CoreAnimation can morph between any two.
    private func islandPath(width: CGFloat, height: CGFloat, ear: CGFloat, in size: CGSize) -> CGPath {
        let top = size.height, bottom = top - height
        let left = (size.width - width) / 2, right = left + width
        let e = min(ear, height)
        let r = min(18, height / 2, width / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left - e, y: top))
        path.addLine(to: CGPoint(x: right + e, y: top))
        corner(path, via: CGPoint(x: right, y: top), to: CGPoint(x: right, y: top - e))
        path.addLine(to: CGPoint(x: right, y: bottom + r))
        corner(path, via: CGPoint(x: right, y: bottom), to: CGPoint(x: right - r, y: bottom))
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        corner(path, via: CGPoint(x: left, y: bottom), to: CGPoint(x: left, y: bottom + r))
        path.addLine(to: CGPoint(x: left, y: top - e))
        corner(path, via: CGPoint(x: left, y: top), to: CGPoint(x: left - e, y: top))
        path.closeSubpath()
        return path
    }

    /// A circular-looking corner from the current point to `end`, turning at `via`.
    private func corner(_ path: CGMutablePath, via: CGPoint, to end: CGPoint) {
        let k: CGFloat = 0.5523  // cubic approximation of a quarter circle
        let start = path.currentPoint
        path.addCurve(to: end,
                      control1: CGPoint(x: start.x + (via.x - start.x) * k, y: start.y + (via.y - start.y) * k),
                      control2: CGPoint(x: end.x + (via.x - end.x) * k, y: end.y + (via.y - end.y) * k))
    }

    // MARK: Content

    /// Lays out icon, app name and keycaps in `content`; returns their size.
    private func buildContent(_ binding: Binding, app: NSRunningApplication, scale: CGFloat) -> CGSize {
        content.sublayers?.forEach { $0.removeFromSuperlayer() }
        let height = Self.rowHeight
        var x: CGFloat = 0

        let icon = CALayer()
        icon.contents = app.icon
        icon.contentsGravity = .resizeAspect
        icon.contentsScale = scale
        icon.frame = CGRect(x: x, y: (height - 26) / 2, width: 26, height: 26)
        content.addSublayer(icon)
        x += 26 + 8

        let name = textLayer(app.localizedName ?? binding.bundleID, weight: .medium, scale: scale, maxWidth: 180)
        name.frame.origin = CGPoint(x: x, y: (height - name.frame.height) / 2)
        content.addSublayer(name)
        x += name.frame.width + 12

        // One keycap per modifier glyph ("⇪", or "⇧" and "⌘"), then the key.
        let glyphs = binding.display.prefix(while: { $0 != " " }).map(String.init)
        for label in glyphs + [binding.keyName] {
            let cap = keycapLayer(label, scale: scale)
            cap.frame.origin = CGPoint(x: x, y: (height - cap.frame.height) / 2)
            content.addSublayer(cap)
            x += cap.frame.width + 4
        }
        return CGSize(width: x - 4, height: height)
    }

    private func textLayer(_ string: String, weight: NSFont.Weight, scale: CGFloat,
                           maxWidth: CGFloat = .greatestFiniteMagnitude) -> CATextLayer {
        let text = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: weight), .foregroundColor: NSColor.white,
        ])
        let layer = CATextLayer()
        layer.string = text
        layer.contentsScale = scale
        layer.truncationMode = .end
        let size = text.size()
        layer.frame = CGRect(x: 0, y: 0, width: min(ceil(size.width), maxWidth), height: ceil(size.height))
        return layer
    }

    private func keycapLayer(_ label: String, scale: CGFloat) -> CALayer {
        let text = textLayer(label, weight: .semibold, scale: scale)
        let cap = CALayer()
        cap.backgroundColor = NSColor(white: 1, alpha: 0.2).cgColor
        cap.cornerRadius = 6
        cap.frame = CGRect(x: 0, y: 0, width: max(text.frame.width + 12, 26), height: 26)
        text.frame.origin = CGPoint(x: (cap.frame.width - text.frame.width) / 2, y: (26 - text.frame.height) / 2)
        cap.addSublayer(text)
        return cap
    }
}
