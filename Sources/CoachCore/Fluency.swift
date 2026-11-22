import Foundation

/// How well the user knows an app's hotkey, from how often they used it lately.
public enum Fluency: Equatable, Sendable {
    case learning, practicing, fluent, graduated

    /// How long the miss flash holds, or nil for no flash.
    public var flashHold: TimeInterval? {
        switch self {
        case .learning: 1.6
        case .practicing: 1.0
        case .fluent: 0.6
        case .graduated: nil
        }
    }
}

private let window = 20

/// Checked in order, first match wins. Below every row is `learning`.
private let stages: [(fluency: Fluency, attempts: Int, hitRate: Double)] = [
    (.graduated, window, 0.95),
    (.fluent, 10, 0.8),
    (.practicing, 5, 0.5),
]

/// From the app's most recent 20 hit/miss records (unbound and system records don't count).
/// `records` oldest first, as the history keeps them.
public func fluency(of bundleID: String, in records: [SwitchRecord]) -> Fluency {
    let attempts = records.filter { $0.bundleID == bundleID && [.hit, .miss].contains($0.outcome) }.suffix(window)
    let rate = attempts.isEmpty ? 0 : Double(attempts.count { $0.outcome == .hit }) / Double(attempts.count)
    return stages.first { attempts.count >= $0.attempts && rate >= $0.hitRate }?.fluency ?? .learning
}

/// The hit at the end of `records` graduated the app for the first time in the kept history.
/// Once per history, so an app hovering near 95% doesn't celebrate every time it climbs back.
public func justGraduated(_ bundleID: String, in records: [SwitchRecord]) -> Bool {
    guard let last = records.last, last.bundleID == bundleID, last.outcome == .hit else { return false }
    let attempts = records.filter { $0.bundleID == bundleID && [.hit, .miss].contains($0.outcome) }
    let graduated = { (end: Int) in fluency(of: bundleID, in: Array(attempts[max(0, end - window + 1)...end])) == .graduated }
    return graduated(attempts.count - 1) && !(0..<attempts.count - 1).contains(where: graduated)
}
