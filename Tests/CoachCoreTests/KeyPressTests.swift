import Testing
@testable import CoachCore

@Test func mapsHIDUsagesToCarbonKeyCodes() {
    #expect(carbonKeyCode(hidUsage: 0x04) == 0)     // A
    #expect(carbonKeyCode(hidUsage: 0x16) == 1)     // S
    #expect(carbonKeyCode(hidUsage: 0x0F) == 37)    // L
    #expect(carbonKeyCode(hidUsage: 0x1D) == 6)     // Z
    #expect(carbonKeyCode(hidUsage: 0x1E) == 18)    // 1
    #expect(carbonKeyCode(hidUsage: 0x27) == 29)    // 0
    #expect(carbonKeyCode(hidUsage: 0x28) == 36)    // Return
    #expect(carbonKeyCode(hidUsage: 0x29) == 53)    // Escape
    #expect(carbonKeyCode(hidUsage: 0x2A) == 51)    // Delete
    #expect(carbonKeyCode(hidUsage: 0x2B) == 48)    // Tab
    #expect(carbonKeyCode(hidUsage: 0x2C) == 49)    // Space
    #expect(carbonKeyCode(hidUsage: 0x36) == 43)    // Comma
    #expect(carbonKeyCode(hidUsage: 0x38) == 44)    // Slash
    #expect(carbonKeyCode(hidUsage: 0x3A) == 122)   // F1
    #expect(carbonKeyCode(hidUsage: 0x45) == 111)   // F12
    #expect(carbonKeyCode(hidUsage: 0x6F) == 90)    // F20
    #expect(carbonKeyCode(hidUsage: 0x50) == 123)   // Left arrow
    #expect(carbonKeyCode(hidUsage: 0x52) == 126)   // Up arrow
}
@Test func modifiersAndUnknownUsagesHaveNoKeyCode() {
    #expect(carbonKeyCode(hidUsage: 0xE3) == nil)   // Left Command
    #expect(carbonKeyCode(hidUsage: 0x39) == nil)   // Caps Lock
    #expect(carbonKeyCode(hidUsage: 0x01) == nil)   // rollover error
}
@Test func everyMappedKeyCodeIsDistinct() {
    let codes = (UInt32(0)...0xFF).compactMap { carbonKeyCode(hidUsage: $0) }
    #expect(Set(codes).count == codes.count)
}

// Uses slackB (hyper S) and loomB (Command-Shift L) from DecisionTests.
func classify(_ keyCode: Int, held: Int) -> KeyPress? { classifyKey(keyCode: keyCode, held: held, bindings: all) }

@Test func keysWithoutABindingsModifiersAreDropped() {
    #expect(classify(1, held: 0) == nil)            // S with nothing held: plain typing
    #expect(classify(1, held: 512) == nil)          // Shift S: a capital letter
    #expect(classify(8, held: 256) == nil)          // Command C
    #expect(classify(37, held: 2304) == nil)        // Option-Command L: L's key, other modifiers
}
@Test func bindingsKeyWithItsModifiersIsBound() {
    #expect(classify(1, held: 6912) == .bound(slackB))
    #expect(classify(37, held: 768) == .bound(loomB))
}
@Test func otherKeyWithABindingsModifiersIsUnbound() {
    #expect(classify(37, held: 6912) == .unbound)   // hyper L: L is Loom's key, but not with hyper
    #expect(classify(2, held: 6912) == .unbound)
    #expect(classify(1, held: 768) == .unbound)     // Command-Shift S
}
@Test func commandTabIsKeptWithOrWithoutAMatchingBinding() {
    #expect(classify(48, held: 256) == .commandTab)
    #expect(classify(48, held: 768) == .commandTab)   // backwards through the switcher, despite Loom's 768
    #expect(classify(48, held: 0) == nil)
    #expect(classify(48, held: 2304) == nil)          // Option-Command Tab is not the switcher
    #expect(classify(48, held: 6912) == .unbound)     // hyper Tab is a hyper key, not the switcher
}
@Test func aBoundTabWinsOverCommandTab() {
    let tab = Binding(bundleID: "tab", keyCode: 48, modifiers: 768)
    #expect(classifyKey(keyCode: 48, held: 768, bindings: [tab]) == .bound(tab))
}
@Test func noBindingsDropsEverythingButCommandTab() {
    #expect(classifyKey(keyCode: 1, held: 6912, bindings: []) == nil)
    #expect(classifyKey(keyCode: 48, held: 256, bindings: []) == .commandTab)
}
@Test func aBindingWithNoModifiersDoesNotReadTyping() {
    let f13 = Binding(bundleID: "f13", keyCode: 105, modifiers: 0)
    #expect(classifyKey(keyCode: 1, held: 0, bindings: [f13]) == nil)
}
