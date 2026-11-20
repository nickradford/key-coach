import AppKit

setvbuf(stdout, nil, _IOLBF, 0)  // show output line by line even when piped to a file

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Shortcut Coach")
let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Quit Shortcut Coach", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu

let coach = Coach()
coach.start()
app.run()
