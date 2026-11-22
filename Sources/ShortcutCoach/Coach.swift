import AppKit
import CoachCore

/// Watches app switches and the modifier keys, and reports misses and when the hold guide should show.
@MainActor
final class Coach: NSObject {
    var onMiss: @MainActor (Binding, NSRunningApplication) -> Void = { binding, app in
        print("MISS \(app.localizedName ?? binding.bundleID) \(binding.display(hyper: HyperKeyListener.shared.hyperKey))")
    }
    var onGuide: (Bool) -> Void = { print("GUIDE \($0)") }

    private var lastHeld: [Int: TimeInterval] = [:]
    private var lastQuitOrHide: (bundleID: String, at: TimeInterval)?
    // Starts as whatever is frontmost, so launching the coach never flashes.
    private var previousFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    private var tracker = HoldTracker()
    private var guideVisible = false

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appGone), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appGone), name: NSWorkspace.didHideApplicationNotification, object: nil)
        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
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
        if bindings.contains(where: { $0.bundleID == id }) { tracker.boundAppActivated(now: now) }
        // A lock screen, password prompt or other non-regular app taking focus is not a switch:
        // coming back from it to the same app must not count as a miss.
        if app.activationPolicy == .regular { previousFrontmost = id }
        // macOS reports a quit or hide about 10 ms after the next app's activation, so decide a moment later.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            // Read lastHeld now, so a key-down handled after the activation still counts.
            // Tradeoff: a hyper press in these 150 ms also suppresses a real miss.
            sampleModifiers()
            var input = input
            input.lastHeld = lastHeld
            input.lastQuitOrHide = lastQuitOrHide
            if let binding = missedBinding(input, bindings: bindings, ownBundleID: Bundle.main.bundleIdentifier) {
                onMiss(binding, app)
            }
        }
    }

    @objc private func appGone(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier else { return }
        lastQuitOrHide = (id, now)
    }
}
