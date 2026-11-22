import AppKit
import CoachCore
import IOKit.hid
import SwiftUI

/// The onboarding card, drawn like the island: pure black, white system text, white keycaps.
struct OnboardingView: View {
    let model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: OnboardingModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ZStack(alignment: .topLeading) {
                step
                    .id(model.step)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(StepTransition(direction: model.direction)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        .padding(28)
        .frame(width: 480)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .dark)
        .modifier(Presence(presented: model.presented, reduceMotion: reduceMotion))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var step: some View {
        switch model.step {
        case .welcome: WelcomeStep(model: model)
        case .tinycast: TinycastStep(model: model)
        case .permission: PermissionStep(model: model)
        case .hyperKey: HyperKeyStep(model: model)
        case .tryIt: TryItStep(model: model)
        case .done: DoneStep()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(.white.opacity(step == model.step ? 1 : 0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(Motion.spring, value: model.step)
            Spacer()
            if model.step != .welcome {
                Button("Back") { model.back() }
                    .buttonStyle(QuietButtonStyle())
            }
            primary
        }
    }

    @ViewBuilder private var primary: some View {
        switch model.step {
        case .welcome:
            PrimaryButton("Get Started") { model.next() }
        case .permission where model.access == kIOHIDAccessTypeUnknown:
            Button("Skip") { model.next() }.buttonStyle(QuietButtonStyle())
            PrimaryButton("Allow") { HyperKeyListener.requestAccess(); model.refresh() }
        case .permission where model.access == kIOHIDAccessTypeDenied:
            Button("Skip") { model.next() }.buttonStyle(QuietButtonStyle())
            PrimaryButton("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
        case .done:
            PrimaryButton("Done") { model.finish() }
        default:
            PrimaryButton("Continue") { model.next() }
        }
    }
}

// MARK: Steps

private struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        StepLayout(title: "Shortcut Coach",
                   text: "When you bring an app forward the long way, by clicking it in the Dock or switching with ⌘Tab, and it has a Tinycast shortcut, a small island drops from the notch to show the shortcut you could have used.") {
            HStack(spacing: 4) {
                KeycapView(model.hyperKey.glyph)
                KeycapView("S")
            }
        }
    }
}

private struct TinycastStep: View {
    let model: OnboardingModel

    private var text: String {
        if !model.tinycastInstalled {
            return "Shortcut Coach reads your app shortcuts from Tinycast. Install Tinycast and give some apps a shortcut; this page updates as you do."
        }
        if model.bindings.isEmpty {
            return "Tinycast is installed but has no app shortcuts yet. Add some in Tinycast's settings; this page updates as you do."
        }
        let count = model.bindings.count
        return "Found \(count) app shortcut\(count == 1 ? "" : "s") in Tinycast."
    }

    var body: some View {
        StepLayout(title: "Tinycast", text: text) {
            if !model.bindings.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 12) {
                    ForEach(Array(model.bindings.prefix(8).enumerated()), id: \.offset) { index, binding in
                        BindingCell(binding: binding, hyper: model.hyperKey)
                            .modifier(Rise(index: index, spacing: 0.03))
                    }
                }
            }
        }
    }
}

private struct BindingCell: View {
    let binding: CoachCore.Binding
    let hyper: HyperKey

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.2))
                }
            }
            .frame(width: 36, height: 36)
            HStack(spacing: 4) {
                ForEach(keycaps, id: \.self) { KeycapView($0) }
            }
        }
    }

    private var keycaps: [String] {
        let glyphs = binding.display(hyper: hyper).prefix(while: { $0 != " " }).map(String.init)
        return glyphs + [binding.keyName]
    }
}

private struct PermissionStep: View {
    let model: OnboardingModel

    var body: some View {
        StepLayout(title: "Input Monitoring",
                   text: "To tell when you hold the hyper key, Shortcut Coach listens to the keys that can be hyper. macOS calls this Input Monitoring. Every other key is ignored.") {
            if model.accessGranted {
                CheckRow(text: "Allowed", done: true)
            } else if model.access == kIOHIDAccessTypeDenied {
                Text("Turn on Shortcut Coach in System Settings › Privacy & Security › Input Monitoring. This page notices when you do.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HyperKeyStep: View {
    let model: OnboardingModel

    var body: some View {
        if let key = model.tinycastHyper {
            StepLayout(title: "Hyper key",
                       text: "Tinycast uses \(key.name) as your hyper key. Hold it to see it light up.") {
                KeycapView(key.glyph, lit: model.hyperDown, size: 44)
            }
        } else {
            StepLayout(title: "Hyper key",
                       text: model.accessGranted
                           ? "Press the key you use as hyper in Tinycast."
                           : "Choose the key you use as hyper in Tinycast. Allow Input Monitoring to pick it by pressing it instead.") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        KeycapView(model.hyperKey.glyph, lit: model.hyperDown, size: 44)
                        Text(model.hyperKey.name)
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    }
                    Picker("Or choose:", selection: SwiftUI.Binding(get: { model.chosenHyper }, set: { model.choose($0) })) {
                        ForEach(HyperKey.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

private struct TryItStep: View {
    let model: OnboardingModel

    var body: some View {
        StepLayout(title: "Try it",
                   text: "Hold the hyper key for a moment and the guide shows every app's shortcut, with a letter over each window.") {
            VStack(alignment: .leading, spacing: 12) {
                CheckRow(text: "Hold \(model.hyperKey.glyph) for a moment", done: model.guideSeen)
                HStack(spacing: 12) {
                    CheckRow(text: "See a miss", done: model.demoShown)
                    Button("Show Me") { model.showDemo() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(!model.canDemo)
                }
            }
        }
    }
}

private struct DoneStep: View {
    var body: some View {
        StepLayout(title: "You're set",
                   text: "Shortcut Coach lives in the menu bar. Show this guide again from there. It starts at login when installed with scripts/install.sh.") {
            KeycapView(Image(systemName: "keyboard"), size: 44)
        }
    }
}

// MARK: Building blocks

/// Title, text, then the step's own content, each rising in a beat after the last.
private struct StepLayout<Content: View>: View {
    let title: String
    let text: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .modifier(Rise(index: 0))
            Text(text)
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Rise(index: 1))
            content
                .padding(.top, 4)
                .modifier(Rise(index: 2))
        }
    }
}

struct KeycapView: View {
    private let label: AnyView
    private let lit: Bool
    private let size: CGFloat

    init(_ text: String, lit: Bool = false, size: CGFloat = 26) {
        label = AnyView(Text(text))
        self.lit = lit
        self.size = size
    }

    init(_ image: Image, size: CGFloat = 26) {
        label = AnyView(image)
        lit = false
        self.size = size
    }

    var body: some View {
        label
            .font(.system(size: size * 14 / 26, weight: .semibold))
            .foregroundStyle(lit ? .black : .white)
            .padding(.horizontal, 6)
            .frame(minWidth: size, minHeight: size)
            .background(RoundedRectangle(cornerRadius: size * 6 / 26, style: .continuous)
                .fill(.white.opacity(lit ? 1 : 0.2)))
            .scaleEffect(lit ? 1.08 : 1)
            .animation(Motion.spring, value: lit)
    }
}

private struct CheckRow: View {
    let text: String
    let done: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().strokeBorder(.white.opacity(0.3)).frame(width: 18, height: 18)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(.white)
                        .transition(AnyTransition(Materialize()))
                }
            }
            .animation(Motion.spring, value: done)
            Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

private struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    init() {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(isEnabled ? (configuration.isPressed ? 0.5 : 0.7) : 0.3))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }
}

// MARK: Motion

/// The card's entrance and exit: the island's materialize and dematerialize, as SwiftUI.
private struct Presence: ViewModifier {
    let presented: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(presented ? 1 : 0)
                .animation(.easeInOut(duration: Motion.reduceMotionFade), value: presented)
        } else {
            content
                .animation(presented ? Motion.spring : Motion.exit) {
                    $0.scaleEffect(presented ? 1 : Motion.enterScale)
                }
                .animation(presented ? Motion.enter(Motion.blurInDuration) : Motion.exit) {
                    $0.blur(radius: presented ? 0 : Motion.enterBlur)
                }
                .animation(presented ? Motion.enter(Motion.fadeInDuration) : Motion.exit) {
                    $0.opacity(presented ? 1 : 0)
                }
        }
    }
}

/// One step leaving and the next arriving: the old one slides away and dematerializes while the new
/// one slides in from the other side and materializes. `direction` is +1 going forward, -1 going back.
private struct StepTransition: Transition {
    let direction: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(x: phase.value * -direction * Motion.stepOffset)
            .scaleEffect(phase.isIdentity ? 1 : Motion.enterScale, anchor: .leading)
            .blur(radius: phase == .willAppear ? Motion.enterBlur : phase == .didDisappear ? Motion.exitBlur : 0)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// A single element appearing: scales up, sharpens and fades in.
private struct Materialize: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : Motion.enterScale)
            .blur(radius: phase.isIdentity ? 0 : Motion.enterBlur)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// Settles an element into place from a little below, blurred, `spacing` seconds after the previous one.
private struct Rise: ViewModifier {
    let index: Int
    let spacing: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(index: Int, spacing: Double = 0.04) {
        self.index = index
        self.spacing = spacing
    }

    func body(content: Content) -> some View {
        content
            .offset(y: shown || reduceMotion ? 0 : 8)
            .blur(radius: shown || reduceMotion ? 0 : Motion.enterBlur / 2)
            .opacity(shown ? 1 : 0)
            .onAppear {
                let animation = reduceMotion ? Animation.easeInOut(duration: Motion.reduceMotionFade) : Motion.spring
                withAnimation(animation.delay(Double(index) * spacing)) { shown = true }
            }
    }
}
