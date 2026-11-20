import AppKit

setvbuf(stdout, nil, _IOLBF, 0)  // show output line by line even when piped to a file

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Shortcut Coach")
let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Quit Shortcut Coach", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu

let flash = Flash()
let coach = Coach()
coach.onMiss = { flash.show($0, app: $1) }
let guide = Guide()
coach.onGuide = { $0 ? guide.show() : guide.hide() }
coach.start()
app.run()
