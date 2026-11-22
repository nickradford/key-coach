import AppKit
import SwiftUI

/// A borderless, transparent panel that, unlike the overlays, takes clicks and key focus.
/// Clicks on its transparent margin fall through to whatever is behind.
private final class OnboardingPanel: NSPanel {
    var onCancel: @MainActor () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }  // Esc
}

/// The first-launch window: shows itself once, and again from the menu.
@MainActor
final class Onboarding: NSObject {
    static let completedKey = "onboardingCompleted"
    private static let size = CGSize(width: 560, height: 620)  // room for the card plus its entrance scale

    private let flash: Flash
    private var panel: OnboardingPanel?
    private var model: OnboardingModel?
    private var generation = 0

    init(flash: Flash) {
        self.flash = flash
    }

    static var completed: Bool { UserDefaults.standard.bool(forKey: completedKey) }

    @objc func showFromMenu() { show() }

    func show() {
        generation += 1
        NSApp.activate()
        if let panel, let model, panel.isVisible, model.presented {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        panel?.orderOut(nil)
        model?.stop()

        let model = OnboardingModel(flash: flash) { [weak self] in self?.close() }
        let panel = OnboardingPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: OnboardingView(model: model))
        host.frame = CGRect(origin: .zero, size: Self.size)
        panel.contentView = host
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: visible.midX - Self.size.width / 2, y: visible.midY - Self.size.height / 2))
        }
        self.panel = panel
        self.model = model
        model.start()
        panel.makeKeyAndOrderFront(nil)
        Task { @MainActor in model.presented = true }  // after the first frame, so the entrance animates
    }

    /// Closing at any step counts as done; the menu brings it back.
    func close() {
        guard let panel, let model, model.presented else { return }
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        model.stop()
        model.presented = false
        generation += 1
        let mine = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Motion.exitDuration))
            guard let self, mine == self.generation else { return }  // reopened while closing
            panel.orderOut(nil)
            self.panel = nil
            self.model = nil
        }
    }

    /// The hold guide appeared; the "Try it" step ticks off holding the hyper key.
    func guideShown() {
        model?.guideSeen = true
    }
}
