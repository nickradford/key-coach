import Testing
@testable import CoachCore

let slackB = Binding(bundleID: "slack", keyCode: 1, modifiers: 6912)
let loomB  = Binding(bundleID: "loom", keyCode: 37, modifiers: 768)
let all = [slackB, loomB]
func miss(_ i: MissInput) -> Binding? { missedBinding(i, bindings: all, ownBundleID: "coach") }

@Test func boundAppWithoutHotkeyIsAMiss() {
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100)) == slackB)
}
@Test func hyperHeldWithinGraceIsNotAMiss() {
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastHeld: [6912: 97.1])) == nil)
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastHeld: [6912: 100])) == nil)
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastHeld: [6912: 96.9])) == slackB)
}
@Test func eachBindingNeedsItsOwnModifiers() {
    #expect(miss(MissInput(activated: "loom", previousFrontmost: "zed", now: 100, lastHeld: [6912: 99])) == loomB)
    #expect(miss(MissInput(activated: "loom", previousFrontmost: "zed", now: 100, lastHeld: [768: 99])) == nil)
}
@Test func unboundAppIsNeverAMiss() {
    #expect(miss(MissInput(activated: "finder", previousFrontmost: "zed", now: 100)) == nil)
}
@Test func alreadyFrontmostIsNeverAMiss() {
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "slack", now: 100)) == nil)
}
@Test func ownAppIsNeverAMiss() {
    #expect(missedBinding(MissInput(activated: "slack", previousFrontmost: "zed", now: 100),
                          bindings: all, ownBundleID: "slack") == nil)
}
@Test func emptyBundleIDIsNeverAMiss() {
    #expect(miss(MissInput(activated: "", previousFrontmost: "zed", now: 100)) == nil)
}
@Test func previousAppQuittingOrHidingSuppresses() {
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastQuitOrHide: ("zed", 99.6))) == nil)
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastQuitOrHide: ("zed", 99.4))) == slackB)
    #expect(miss(MissInput(activated: "slack", previousFrontmost: "zed", now: 100, lastQuitOrHide: ("dia", 99.9))) == slackB)
}

@Test func guideOpensAfterDelayAndClosesOnRelease() {
    var t = HoldTracker()
    #expect(t.update(hyperHeld: true, now: 10.0) == false)
    #expect(t.update(hyperHeld: true, now: 10.65) == false)
    #expect(t.update(hyperHeld: true, now: 10.75) == true)   // not 10.7: 10.7 - 10.0 < 0.7 in floating point
    #expect(t.update(hyperHeld: false, now: 10.8) == false)
    #expect(t.update(hyperHeld: true, now: 10.9) == false)   // delay restarts
}
@Test func activationKeepsGuideClosedUntilRelease() {
    var t = HoldTracker()
    _ = t.update(hyperHeld: true, now: 10.0)
    t.boundAppActivated()
    #expect(t.update(hyperHeld: true, now: 11.0) == false)
    _ = t.update(hyperHeld: false, now: 11.1)
    _ = t.update(hyperHeld: true, now: 11.2)
    #expect(t.update(hyperHeld: true, now: 12.0) == true)
}
@Test func activationClosesAnOpenGuide() {
    var t = HoldTracker()
    _ = t.update(hyperHeld: true, now: 10.0)
    #expect(t.update(hyperHeld: true, now: 10.8) == true)
    t.boundAppActivated()
    #expect(t.update(hyperHeld: true, now: 10.9) == false)
}
