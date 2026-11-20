// Renders the app icon and the README header into assets/.
// Run from the repo root: swift scripts/render-art.swift
import AppKit

let assets = URL(fileURLWithPath: "assets", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

// MARK: Drawing helpers (AppKit coordinates: origin bottom-left)

func render(_ width: Int, _ height: Int, to name: String, draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent(name))
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor { NSColor(white: white, alpha: alpha).cgColor }

/// The island from the app: hangs from `top`, rounded bottom, top corners curving outward into the edge.
func island(centerX: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, ear: CGFloat, radius r: CGFloat) -> CGPath {
    let left = centerX - width / 2, right = centerX + width / 2, bottom = top - height
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left - ear, y: top))
    path.addLine(to: CGPoint(x: right + ear, y: top))
    path.addQuadCurve(to: CGPoint(x: right, y: top - ear), control: CGPoint(x: right, y: top))
    path.addLine(to: CGPoint(x: right, y: bottom + r))
    path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right - r, y: bottom), radius: r)
    path.addLine(to: CGPoint(x: left + r, y: bottom))
    path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: bottom + r), radius: r)
    path.addLine(to: CGPoint(x: left, y: top - ear))
    path.addQuadCurve(to: CGPoint(x: left - ear, y: top), control: CGPoint(x: left, y: top))
    path.closeSubpath()
    return path
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

func drawCentered(_ string: NSAttributedString, in rect: CGRect) {
    let size = string.size()
    string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
}

/// A keycap as in the app: translucent white rounded square with white text.
func keycap(_ ctx: CGContext, _ label: String, rect: CGRect, fontSize: CGFloat) {
    ctx.setFillColor(gray(1, 0.2))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height * 0.23, cornerHeight: rect.height * 0.23, transform: nil))
    ctx.fillPath()
    drawCentered(text(label, size: fontSize, weight: .semibold, color: .white), in: rect)
}

// MARK: App icon: a dark tile with the island and the ⇪ key hanging from its top edge

render(1024, 1024, to: "icon.png") { ctx in
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)  // Apple's macOS icon grid
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()  // drop shadow under the tile, as macOS icons have
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: gray(0, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(gray(0.11))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let light = CGGradient(colorsSpace: nil, colors: [gray(0.2), gray(0.09)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(light, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.addPath(island(centerX: 512, top: tile.maxY, width: 560, height: 470, ear: 60, radius: 140))
    ctx.setFillColor(gray(0))
    ctx.fillPath()
    keycap(ctx, "⇪", rect: CGRect(x: 512 - 140, y: tile.maxY - 470 + 75, width: 280, height: 280), fontSize: 170)
    ctx.restoreGState()

    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(gray(1, 0.1))  // faint rim so the tile reads on dark docks
    ctx.setLineWidth(3)
    ctx.strokePath()
}

// MARK: README header: a menu bar with the miss flash dropping from the notch, and the name

render(1600, 640, to: "header.png") { ctx in
    let width: CGFloat = 1600, height: CGFloat = 640
    ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(gray(1, 0.06))  // menu bar
    ctx.fill(CGRect(x: 0, y: height - 48, width: width, height: 48))

    // The flash: icon tile, app name, keycaps; same proportions as the app at 2x.
    let islandHeight: CGFloat = 48 + 116
    ctx.addPath(island(centerX: width / 2, top: height, width: 500, height: islandHeight, ear: 22, radius: 40))
    ctx.setFillColor(gray(0))
    ctx.fillPath()
    let rowMid = height - 48 - 58
    let appTile = CGRect(x: width / 2 - 206, y: rowMid - 30, width: 60, height: 60)
    ctx.addPath(CGPath(roundedRect: appTile, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(CGColor(red: 0.29, green: 0.5, blue: 0.98, alpha: 1))  // a stand-in app icon, no real brand
    ctx.fillPath()
    let name = text("Messages", size: 32, weight: .medium, color: .white)
    name.draw(at: CGPoint(x: appTile.maxX + 20, y: rowMid - name.size().height / 2))
    keycap(ctx, "⇪", rect: CGRect(x: width / 2 + 74, y: rowMid - 30, width: 60, height: 60), fontSize: 30)
    keycap(ctx, "M", rect: CGRect(x: width / 2 + 146, y: rowMid - 30, width: 60, height: 60), fontSize: 30)

    drawCentered(text("Shortcut Coach", size: 96, weight: .bold, color: .white),
                 in: CGRect(x: 0, y: 200, width: width, height: 120))
    drawCentered(text("Learn the Tinycast hotkeys you already set up", size: 36, weight: .regular,
                      color: NSColor(white: 0.62, alpha: 1)),
                 in: CGRect(x: 0, y: 130, width: width, height: 60))
}

// MARK: .icns for the app bundle

let iconset = assets.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func run(_ tool: String, _ args: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    try! process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "\(tool) failed")
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        run("/usr/bin/sips", ["-z", "\(size * scale)", "\(size * scale)", "assets/icon.png",
                              "--out", iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png").path])
    }
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", "assets/AppIcon.icns"])
try FileManager.default.removeItem(at: iconset)
print("wrote assets/icon.png, assets/header.png, assets/AppIcon.icns")
