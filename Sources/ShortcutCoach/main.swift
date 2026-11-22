import AppKit

setvbuf(stdout, nil, _IOLBF, 0)  // show output line by line even when piped to a file

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let flash = Flash()
let onboarding = Onboarding(flash: flash)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Shortcut Coach")
let menu = NSMenu()
let showOnboarding = NSMenuItem(title: "Show Onboarding…", action: #selector(Onboarding.showFromMenu), keyEquivalent: "")
showOnboarding.target = onboarding
menu.addItem(showOnboarding)
menu.addItem(.separator())
menu.addItem(NSMenuItem(title: "Quit Shortcut Coach", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu

let coach = Coach()
coach.onMiss = { flash.show($0, app: $1, hold: $2) }
coach.onGraduate = { flash.celebrate($0, app: $1) }
let guide = Guide()
coach.onGuide = { visible in
    visible ? guide.show() : guide.hide()
    if visible { onboarding.guideShown() }
}
HyperKeyListener.shared.start()
coach.start()
if !Onboarding.completed { onboarding.show() }
app.run()
