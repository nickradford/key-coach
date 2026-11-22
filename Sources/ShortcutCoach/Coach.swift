import AppKit
import CoachCore

/// Watches app switches, the modifier keys and which app each click lands on, and reports misses and when the hold guide should show.
@MainActor
final class Coach: NSObject {
    /// The binding that should have been used, its app, and how long to flash.
    var onMiss: @MainActor (Binding, NSRunningApplication, TimeInterval) -> Void = { binding, app, _ in
        print("MISS \(app.localizedName ?? binding.bundleID) \(binding.display(hyper: HyperKeyListener.shared.hyperKey))")
    }
    var onGuide: (Bool) -> Void = { print("GUIDE \($0)") }

    private var lastHeld: [Int: TimeInterval] = [:]
    private var lastQuitOrHide: (bundleID: String, at: TimeInterval)?
    private var lastClick: (bundleID: String?, at: TimeInterval)?
    private var clickMonitor: Any?
    // Starts as whatever is frontmost, so launching the coach never flashes.
    private var previousFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    private var tracker = HoldTracker()
    private var guideVisible = false
    private var history = HistoryFile()

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appGone), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appGone), name: NSWorkspace.didHideApplicationNotification, object: nil)
        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        // Mouse events need no permission to watch, unlike key events.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let click = (bundleID: windowOwner(of: event), at: event.timestamp)  // the event's own time, on the uptime clock
            MainActor.assumeIsolated { self?.lastClick = click }  // AppKit calls global monitors on the main thread
        }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func sampleModifiers() {
        let held = heldModifiers()
        if held != 0 { lastHeld[held] = now }
        if let pressed = HyperKeyListener.shared.pressedAt {
            lastHeld[hyperModifiers] = max(lastHeld[hyperModifiers] ?? pressed, pressed)
        }
    }

    @objc private func poll() {
        sampleModifiers()
        let listener = HyperKeyListener.shared
        // Only while down. A stale press time would open the guide at once when hyper comes from the flags.
        let visible = tracker.update(hyperHeld: hyperHeld(), pressedAt: listener.isDown ? listener.pressedAt : nil, now: now)
        if visible != guideVisible {
            guideVisible = visible
            onGuide(visible)
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        sampleModifiers()
        let id = app.bundleIdentifier ?? ""
        let bindings = parseBindings(loadTinycastPrefs())
        let input = MissInput(activated: id, previousFrontmost: previousFrontmost, now: now)
        let at = Date.now
        if bindings.contains(where: { $0.bundleID == id }) { tracker.boundAppActivated(now: now) }
        // A lock screen, password prompt or other non-regular app taking focus is not a switch:
        // coming back from it to the same app must not count as a miss.
        if app.activationPolicy == .regular { previousFrontmost = id }
        // macOS reports a quit or hide about 10 ms after the next app's activation, so decide a moment later.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            // Read the inputs now, so a key-down handled after the activation still counts.
            // Tradeoffs: without Input Monitoring a hyper press in these 150 ms suppresses a real miss; with it,
            // another hotkey pressed in these 150 ms replaces lastPress. Any key in them hides an earlier one.
            sampleModifiers()
            var input = input
            input.lastHeld = lastHeld
            input.lastQuitOrHide = lastQuitOrHide
            input.lastPress = HyperKeyListener.shared.lastPress
            input.listening = HyperKeyListener.shared.isListening
            input.lastKeyAt = lastKeyDownAt()
            input.lastClick = lastClick
            let ownID = Bundle.main.bundleIdentifier
            // Read before this switch is recorded, so the flash reflects how well the app was known going in.
            if let binding = missedBinding(input, bindings: bindings, ownBundleID: ownID),
               let hold = fluency(of: id, in: history.records).flashHold {
                onMiss(binding, app, hold)
            }
            if app.activationPolicy == .regular, let outcome = switchOutcome(input, bindings: bindings, ownBundleID: ownID) {
                history.append(SwitchRecord(bundleID: id, outcome: outcome, method: switchMethod(input), at: at))
            }
        }
    }

    @objc private func appGone(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier else { return }
        lastQuitOrHide = (id, now)
    }
}
