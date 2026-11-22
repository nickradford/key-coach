import Foundation
import Testing
@testable import CoachCore

private let app = "md.obsidian"
private func switches(_ outcome: Outcome, _ count: Int, of id: String = app) -> [SwitchRecord] {
    Array(repeating: SwitchRecord(bundleID: id, outcome: outcome, method: .other, at: t0), count: count)
}
private func hits(_ count: Int) -> [SwitchRecord] { switches(.hit, count) }
private func misses(_ count: Int) -> [SwitchRecord] { switches(.miss, count) }

@Test func noHistoryIsLearning() {
    #expect(fluency(of: app, in: []) == .learning)
}
@Test func graduatesAt20AttemptsAndA95PercentHitRate() {
    #expect(fluency(of: app, in: hits(19) + misses(1)) == .graduated)
    #expect(fluency(of: app, in: hits(18) + misses(2)) == .fluent)
    #expect(fluency(of: app, in: hits(19)) == .fluent)  // a perfect run still needs 20 attempts
}
@Test func fluentAt10AttemptsAndAn80PercentHitRate() {
    #expect(fluency(of: app, in: hits(8) + misses(2)) == .fluent)
    #expect(fluency(of: app, in: hits(7) + misses(3)) == .practicing)
    #expect(fluency(of: app, in: hits(9)) == .practicing)
}
@Test func practicingAt5AttemptsAndA50PercentHitRate() {
    #expect(fluency(of: app, in: hits(3) + misses(3)) == .practicing)
    #expect(fluency(of: app, in: hits(2) + misses(3)) == .learning)
    #expect(fluency(of: app, in: hits(4)) == .learning)
}
@Test func onlyTheLast20AttemptsCount() {
    #expect(fluency(of: app, in: misses(20) + hits(20)) == .graduated)
    #expect(fluency(of: app, in: hits(20) + misses(5)) == .practicing)
}
@Test func ignoresUnboundAndSystemSwitchesAndOtherApps() {
    let noise = switches(.unbound, 10) + switches(.system, 10) + switches(.miss, 20, of: "com.apple.finder")
    #expect(fluency(of: app, in: hits(19) + noise + misses(1)) == .graduated)
    #expect(fluency(of: app, in: switches(.hit, 20, of: "com.apple.finder")) == .learning)
}
@Test func theFlashShortensAsFluencyGrowsAndStopsAtGraduation() {
    #expect(Fluency.learning.flashHold == 1.6)
    #expect(Fluency.practicing.flashHold == 1.0)
    #expect(Fluency.fluent.flashHold == 0.6)
    #expect(Fluency.graduated.flashHold == nil)
}
@Test func celebratesTheHitThatFirstGraduates() {
    #expect(justGraduated(app, in: hits(20)))
    #expect(!justGraduated(app, in: hits(19)))
    #expect(!justGraduated(app, in: hits(19) + misses(1)))  // a miss never celebrates
    #expect(!justGraduated(app, in: hits(20) + switches(.hit, 1, of: "other")))
}
@Test func celebratesOnlyOncePerHistory() {
    #expect(!justGraduated(app, in: hits(21)))
    // Dips to fluent, then climbs back once the misses leave the window.
    #expect(!justGraduated(app, in: hits(20) + misses(2) + hits(20)))
}
