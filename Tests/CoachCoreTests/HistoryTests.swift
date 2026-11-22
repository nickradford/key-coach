import Foundation
import Testing
@testable import CoachCore

let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
let day = 86_400.0
func record(_ id: String, at: Date) -> SwitchRecord { SwitchRecord(bundleID: id, outcome: .hit, method: .hotkey, at: at) }

@Test func cappedDropsRecordsOlderThan30Days() {
    let old = record("old", at: t0 - 30 * day - 1)
    let edge = record("edge", at: t0 - 30 * day)
    let fresh = record("fresh", at: t0)
    #expect(capped([old, edge, fresh], now: t0) == [edge, fresh])
}
@Test func cappedKeepsTheNewest5000() {
    let records = (0..<5_001).map { record("app\($0)", at: t0 + Double($0)) }
    let kept = capped(records, now: t0 + 5_001)
    #expect(kept.count == 5_000)
    #expect(kept.first == records[1])
    #expect(kept.last == records[5_000])
}
@Test func cappedKeepsASmallRecentHistoryAsIs() {
    let records = [record("a", at: t0 - day), record("b", at: t0)]
    #expect(capped(records, now: t0) == records)
    #expect(capped([], now: t0).isEmpty)
}
@Test func switchRecordsRoundTripThroughJSON() throws {
    let records = [
        SwitchRecord(bundleID: "com.tinyspeck.slackmacgap", outcome: .hit, method: .hotkey, at: t0 + 0.123),
        SwitchRecord(bundleID: "md.obsidian", outcome: .miss, method: .commandTab, at: t0 + 1),
        SwitchRecord(bundleID: "com.apple.finder", outcome: .unbound, method: .other, at: t0 + 2),
    ]
    #expect(try JSONDecoder().decode([SwitchRecord].self, from: JSONEncoder().encode(records)) == records)
}
// A file written by an earlier build must keep loading.
@Test func readsTheStoredFormat() throws {
    let json = #"[{"bundleID":"md.obsidian","outcome":"miss","method":"commandTab","at":800000000}]"#
    #expect(try JSONDecoder().decode([SwitchRecord].self, from: Data(json.utf8))
            == [SwitchRecord(bundleID: "md.obsidian", outcome: .miss, method: .commandTab, at: t0)])
}
