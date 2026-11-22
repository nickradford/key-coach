import Foundation

/// One app switch, as kept in the history file. It holds no key: only the app, how the switch went,
/// how the app was reached, and when.
public struct SwitchRecord: Codable, Equatable, Sendable {
    public let bundleID: String
    public let outcome: Outcome
    public let method: Method
    public let at: Date

    public init(bundleID: String, outcome: Outcome, method: Method, at: Date) {
        self.bundleID = bundleID
        self.outcome = outcome
        self.method = method
        self.at = at
    }
}

/// `unbound`: the app has no hotkey, so there was nothing to hit or miss.
public enum Outcome: String, Codable, Sendable { case hit, miss, unbound }

public enum Method: String, Codable, Sendable { case hotkey, commandTab, other }

// 30 days covers a monthly recap. 5,000 is about 30 days at 170 switches a day and keeps the file
// near 0.5 MB (about 100 bytes a record), cheap to rewrite after every switch.
private let historyDays = 30.0
private let historyLimit = 5_000

/// `records` oldest first, as appended: those from the last 30 days, at most the newest 5,000.
public func capped(_ records: [SwitchRecord], now: Date) -> [SwitchRecord] {
    let cutoff = now.addingTimeInterval(-historyDays * 86_400)
    return Array(records.filter { $0.at >= cutoff }.suffix(historyLimit))
}
