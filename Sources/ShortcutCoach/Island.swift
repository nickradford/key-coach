import AppKit

/// A black island that grows out of the notch (or Alcove's fake notch), in the style of Alcove:
/// a soft spring, inverted top corners, and content that scales and sharpens into place.
/// Used by both the miss flash and the hold guide.
@MainActor
final class Island {
    private static let ear: CGFloat = 10       // radius of the inverted corners at the top edge
    private static let headroom: CGFloat = 28  // spare window around the island so the spring's overshoot is never clipped
    private static let enterLift: CGFloat = 14  // content starts this far up and settles down

    private let panel = makeOverlayPanel()
    private let root = CALayer()
    private let fill = CALayer()  // black, clipped to the island by `shape`
    private let shape = CAShapeLayer()
    private var content = CALayer()
    private var screen: NSScreen?
    private var startPath: CGPath?
    private var visible = false  // shown or growing; false once hiding starts
    private var generation = 0

    init() {
        let host = NSView()
        host.layer = root  // layer-hosting: we own the geometry, AppKit does no layout
        host.wantsLayer = true
        host.layerUsesCoreImageFilters = true  // lets the content layer blur
        panel.contentView = host
        fill.backgroundColor = NSColor.black.cgColor
        fill.mask = shape
        root.addSublayer(fill)
    }

    /// Shows `newContent` (a layer of `contentSize`, its own padding included) under the notch of
    /// `screen`. When the island is already up on that screen, the content is swapped in place.
    func show(_ newContent: CALayer, size contentSize: CGSize, sidePadding: CGFloat, on screen: NSScreen) {
        generation += 1
        let notch = notchRect(on: screen)
        let island = CGSize(width: max(contentSize.width + 2 * sidePadding, notch.width),
                            height: notch.height + contentSize.height)
        let size = CGSize(width: island.width + 2 * (Self.ear + Self.headroom), height: island.height + Self.headroom)
        let start = islandPath(width: notch.width, height: notch.height, ear: 0, in: size)
        let end = islandPath(width: island.width, height: island.height, ear: Self.ear, in: size)
        let centre = CGPoint(x: size.width / 2, y: size.height - notch.height - contentSize.height / 2)
        let swapInPlace = visible && self.screen == screen

        panel.setFrame(NSRect(x: notch.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.removeAllAnimations()
        content.removeFromSuperlayer()
        content = newContent
        content.bounds = CGRect(origin: .zero, size: contentSize)
        content.position = centre
        addBlurFilter(content)
        root.frame = CGRect(origin: .zero, size: size)
        fill.frame = root.frame
        shape.frame = root.frame
        shape.path = end
        fill.addSublayer(content)
        CATransaction.commit()
        self.screen = screen
        startPath = start
        visible = true
        panel.alphaValue = 1
        if swapInPlace { return }

        panel.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { $0.duration = Motion.reduceMotionFade; panel.animator().alphaValue = 1 }
            return
        }
        spring(shape, "path", from: start, to: end)
        spring(content, "position", from: CGPoint(x: centre.x, y: centre.y + Self.enterLift), to: centre)
        materialize(content)
    }

    /// Retracts into the notch, then takes the window off screen.
    func hide() {
        guard visible, let start = startPath else { return }
        visible = false
        generation += 1
        let mine = generation
        let done: () -> Void = { [weak self] in
            guard let self, mine == generation else { return }  // shown again meanwhile
            panel.orderOut(nil)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ $0.duration = Motion.exitDuration; panel.animator().alphaValue = 0 },
                                                 completionHandler: done)
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        retract(shape, "path", from: shape.presentation()?.path ?? shape.path, to: start)
        dematerialize(content)
        CATransaction.commit()
    }

    // MARK: Shape

    /// A rounded-bottom island hanging from the top edge of a `size` canvas, centred, whose top
    /// corners curve outward into the edge (inverted corners), like the notch itself.
    /// Every call emits the same elements so Core Animation can morph between any two.
    private func islandPath(width: CGFloat, height: CGFloat, ear: CGFloat, in size: CGSize) -> CGPath {
        let top = size.height, bottom = top - height
        let left = (size.width - width) / 2, right = left + width
        let e = min(ear, height)
        let r = min(20, height / 2, width / 2)
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
}

// MARK: Content building blocks

/// White system text as a layer sized to fit, truncated at `maxWidth`.
@MainActor func textLayer(_ string: String, size: CGFloat = 14, weight: NSFont.Weight, scale: CGFloat,
                          maxWidth: CGFloat = .greatestFiniteMagnitude) -> CATextLayer {
    let text = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.white,
    ])
    let layer = CATextLayer()
    layer.string = text
    layer.contentsScale = scale
    layer.truncationMode = .end
    let fit = text.size()
    layer.frame = CGRect(x: 0, y: 0, width: min(ceil(fit.width), maxWidth), height: ceil(fit.height))
    return layer
}

/// One key drawn as a keycap: white text on a translucent rounded square, 26 pt tall.
@MainActor func keycapLayer(_ label: String, scale: CGFloat) -> CALayer {
    let text = textLayer(label, weight: .semibold, scale: scale)
    let cap = CALayer()
    cap.backgroundColor = NSColor(white: 1, alpha: 0.2).cgColor
    cap.cornerRadius = 6
    cap.frame = CGRect(x: 0, y: 0, width: max(text.frame.width + 12, 26), height: 26)
    text.frame.origin = CGPoint(x: (cap.frame.width - text.frame.width) / 2, y: (26 - text.frame.height) / 2)
    cap.addSublayer(text)
    return cap
}

@MainActor func iconLayer(_ image: NSImage?, side: CGFloat, scale: CGFloat) -> CALayer {
    let icon = CALayer()
    icon.contents = image
    icon.contentsGravity = .resizeAspect
    icon.contentsScale = scale
    icon.frame = CGRect(x: 0, y: 0, width: side, height: side)
    return icon
}
