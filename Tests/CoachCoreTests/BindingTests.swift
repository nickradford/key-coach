import Testing
@testable import CoachCore

let slack = #"{"combo":{"_0":{"carbonModifiers":6912,"carbonKeyCode":1}}}"#
let loom  = #"{"combo":{"_0":{"carbonKeyCode":37,"carbonModifiers":768}}}"#

@Test func parsesAppBindingsSortedAndIgnoresOtherKeys() {
    let b = parseBindings([
        "hotkey.app.com.tinyspeck.slackmacgap": slack,
        "hotkey.app.com.loom.desktop.native": loom,
        "hotkey.windowCommand.left-half": slack,
        "appearance": "system",
    ])
    #expect(b == [
        Binding(bundleID: "com.loom.desktop.native", keyCode: 37, modifiers: 768),
        Binding(bundleID: "com.tinyspeck.slackmacgap", keyCode: 1, modifiers: 6912),
    ])
}
@Test func displayStrings() {
    #expect(Binding(bundleID: "x", keyCode: 1, modifiers: 6912).display == "⇪ S")
    #expect(Binding(bundleID: "x", keyCode: 37, modifiers: 768).display == "⇧⌘ L")
    #expect(Binding(bundleID: "x", keyCode: 123, modifiers: 2304).display == "⌥⌘ ←")
    #expect(Binding(bundleID: "x", keyCode: 49, modifiers: 256).display == "⌘ Space")
    #expect(Binding(bundleID: "x", keyCode: 200, modifiers: 6912).display == "⇪ key 200")
}
@Test func malformedValuesAreSkipped() {
    #expect(parseBindings(["hotkey.app.a": "not json", "hotkey.app.b": 42,
                           "hotkey.app.c": #"{"combo":{}}"#]).isEmpty)
}
@Test func emptyPrefsGiveNoBindings() { #expect(parseBindings([:]).isEmpty) }
@Test func parseComboReadsEitherFieldOrder() {
    #expect(parseCombo(slack)?.keyCode == 1)
    #expect(parseCombo(loom)?.modifiers == 768)
    #expect(parseCombo(nil) == nil)
}
