import CoreGraphics

public struct WindowInfo: Equatable, Sendable {
    public let pid: Int32
    public let bounds: CGRect

    public init(pid: Int32, bounds: CGRect) {
        self.pid = pid
        self.bounds = bounds
    }
}

/// Index of the screen frame overlapping `bounds` the most; nil when it overlaps none.
public func screenIndex(forWindowBounds bounds: CGRect, screenFrames: [CGRect]) -> Int? {
    let areas = screenFrames.map { frame -> CGFloat in
        let overlap = frame.intersection(bounds)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
    guard let best = areas.max(), best > 0 else { return nil }
    return areas.firstIndex(of: best)
}

/// `windows` is front to back. For each pid in `pids`, the centre of its frontmost window,
/// omitted when a window nearer the front contains that point.
public func badgePoints(windows: [WindowInfo], pids: Set<Int32>) -> [Int32: CGPoint] {
    var points: [Int32: CGPoint] = [:]
    var seen: Set<Int32> = []
    for (index, window) in windows.enumerated() where pids.contains(window.pid) && seen.insert(window.pid).inserted {
        let centre = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        if !windows[..<index].contains(where: { $0.bounds.contains(centre) }) {
            points[window.pid] = centre
        }
    }
    return points
}

/// Where the flash grows from on a screen with no hardware notch.
/// With Alcove set to show on all displays it draws a fake notch there; its size is not stored
/// anywhere readable, so assume the built-in notch's width and the menu bar's height.
public func notchlessStart(screenFrame: CGRect, menuBarHeight: CGFloat, builtInNotchWidth: CGFloat?,
                           alcoveOnAllDisplays: Bool) -> CGRect {
    guard alcoveOnAllDisplays else {
        return CGRect(x: screenFrame.midX - 90, y: screenFrame.maxY, width: 180, height: 0)
    }
    let width = builtInNotchWidth ?? 185
    let height = menuBarHeight > 0 ? menuBarHeight : 32
    return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
}
