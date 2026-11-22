import Testing
@testable import CoachCore

@Test func readsTinycastHyperKey() {
    #expect(tinycastHyperKey(["hyperKeyPhysicalKey": "capsLock"]) == .capsLock)
    #expect(tinycastHyperKey(["hyperKeyPhysicalKey": "rightCommand"]) == .rightCommand)
    #expect(tinycastHyperKey([:]) == nil)
    #expect(tinycastHyperKey(["hyperKeyPhysicalKey": "fnKey"]) == nil)
    #expect(tinycastHyperKey(["hyperKeyPhysicalKey": 3]) == nil)
}
@Test func tinycastBeatsStoredChoiceThenCapsLock() {
    #expect(resolveHyperKey(tinycast: .capsLock, stored: "rightCommand") == .capsLock)
    #expect(resolveHyperKey(tinycast: nil, stored: "rightOption") == .rightOption)
    #expect(resolveHyperKey(tinycast: nil, stored: "x") == .capsLock)
    #expect(resolveHyperKey(tinycast: nil, stored: nil) == .capsLock)
}
@Test func mapsHIDUsagesToKeys() {
    #expect(HyperKey(hidUsage: 0x39) == .capsLock)
    #expect(HyperKey(hidUsage: 0x6D) == .capsLock)
    #expect(HyperKey(hidUsage: 0xE7) == .rightCommand)
    #expect(HyperKey(hidUsage: 0xE4) == .rightControl)
    #expect(HyperKey(hidUsage: 0x04) == nil)
}
@Test func everyKeyHasDistinctUsagesAndGlyph() {
    let usages = HyperKey.allCases.flatMap(\.hidUsages)
    #expect(Set(usages).count == usages.count)
    #expect(Set(HyperKey.allCases.map(\.glyph)).count == HyperKey.allCases.count)
}
@Test func hyperBindingShowsTheHyperKeysGlyph() {
    let hyper = Binding(bundleID: "x", keyCode: 1, modifiers: 6912)
    #expect(hyper.display(hyper: .capsLock) == "⇪ S")
    #expect(hyper.display(hyper: .rightCommand) == "⌘ S")
    #expect(Binding(bundleID: "x", keyCode: 37, modifiers: 768).display(hyper: .rightCommand) == "⇧⌘ L")
}
