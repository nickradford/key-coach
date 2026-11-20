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
