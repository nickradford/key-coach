import AppKit
import CoachCore
import IOKit.hid
import Observation
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, tinycast, permission, hyperKey, tryIt, done
}

/// Live state behind the onboarding steps. While the window is open the hyper key is sampled at
/// 30 Hz, so its keycap lights promptly, and everything else four times a second.
@MainActor @Observable
final class OnboardingModel {
    var step: OnboardingStep = .welcome
    var direction: CGFloat = 1  // +1 going forward, -1 going back
    var presented = false
    var tinycastInstalled = false
    var bindings: [CoachCore.Binding] = []
    var access: IOHIDAccessType = kIOHIDAccessTypeUnknown
    var tinycastHyper: HyperKey?
    var chosenHyper: HyperKey
    var hyperDown = false
    var guideSeen = false
    var demoShown = false

    let flash: Flash
    let finish: @MainActor () -> Void
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0

    init(flash: Flash, finish: @escaping @MainActor () -> Void) {
        self.flash = flash
        self.finish = finish
        chosenHyper = resolveHyperKey(tinycast: nil, stored: UserDefaults.standard.string(forKey: "hyperKey"))
        refresh()
    }

    /// The key hyper means right now: Tinycast's when it is set, else the user's choice.
    var hyperKey: HyperKey { tinycastHyper ?? chosenHyper }

    var accessGranted: Bool { access == kIOHIDAccessTypeGranted }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        HyperKeyListener.shared.capture = nil
    }

    private func tick() {
        ticks += 1
        if ticks % 8 == 0 { refresh() }
        let down = HyperKeyListener.shared.isDown
        if down != hyperDown { hyperDown = down }
    }

    func refresh() {
        let prefs = loadTinycastPrefs()
        let installed = !prefs.isEmpty
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.abueammar.tinycast") != nil
        let fresh = parseBindings(prefs)
        let access = HyperKeyListener.access
        let tinycast = tinycastHyperKey(prefs)
        // Assign only changes, so the view is not redrawn four times a second for nothing.
        if installed != tinycastInstalled { tinycastInstalled = installed }
        if fresh != bindings { bindings = fresh }
        if access != self.access { self.access = access }
        if tinycast != tinycastHyper { tinycastHyper = tinycast }
        updateCapture()
    }

    func next() { go(to: OnboardingStep(rawValue: step.rawValue + 1), direction: 1) }
    func back() { go(to: OnboardingStep(rawValue: step.rawValue - 1), direction: -1) }

    /// Sets the direction first and moves a moment later, so the leaving step is already
    /// carrying the new direction when it is removed.
    private func go(to target: OnboardingStep?, direction: CGFloat) {
        guard let target else { return }
        self.direction = direction
        Task { @MainActor in
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduce ? .easeInOut(duration: Motion.reduceMotionFade) : Motion.spring) { self.step = target }
            self.updateCapture()
        }
    }

    func choose(_ key: HyperKey) {
        chosenHyper = key
        UserDefaults.standard.set(key.rawValue, forKey: "hyperKey")
        HyperKeyListener.shared.refreshHyperKey()
    }

    /// Listens for the user's hyper key only on the hyper step, and only when Tinycast does not say.
    private func updateCapture() {
        guard step == .hyperKey, tinycastHyper == nil else {
            HyperKeyListener.shared.capture = nil
            return
        }
        HyperKeyListener.shared.capture = { [weak self] key in self?.choose(key) }
    }

    var canDemo: Bool { !bindings.isEmpty }

    func showDemo() {
        guard let binding = bindings.first(where: \.isHyper) ?? bindings.first else { return }
        flash.demo(binding)
        demoShown = true
    }
}
