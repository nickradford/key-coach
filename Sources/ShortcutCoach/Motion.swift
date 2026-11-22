import AppKit
import CoreImage
import SwiftUI

/// Every motion value the overlays and the onboarding share, so the two never drift apart.
enum Motion {
    static let enterScale = 0.82
    static let enterBlur = 10.0
    static let exitBlur = 8.0
    static let exitDuration = 0.26
    static let springDuration = 0.5
    static let springBounce = 0.2
    static let blurInDuration = 0.4
    static let fadeInDuration = 0.3
    static let reduceMotionFade = 0.2
    static let enterCurve: (Double, Double, Double, Double) = (0.16, 1, 0.3, 1)
    static let exitCurve: (Double, Double, Double, Double) = (0.5, 0, 0.9, 0.5)
    static let stepOffset: CGFloat = 24

    // SwiftUI equivalents of the Core Animation helpers below.

    static var spring: Animation { .spring(duration: springDuration, bounce: springBounce) }

    static func enter(_ duration: Double) -> Animation {
        .timingCurve(enterCurve.0, enterCurve.1, enterCurve.2, enterCurve.3, duration: duration)
    }

    static var exit: Animation {
        .timingCurve(exitCurve.0, exitCurve.1, exitCurve.2, exitCurve.3, duration: exitDuration)
    }
}

/// Gives `layer` a blur named "blur" at radius 0, so its radius can be animated.
/// The hosting view needs `layerUsesCoreImageFilters`.
@MainActor func addBlurFilter(_ layer: CALayer) {
    let blur = CIFilter(name: "CIGaussianBlur")!
    blur.name = "blur"
    blur.setValue(0, forKey: kCIInputRadiusKey)
    layer.filters = [blur]
}

/// Entrance: scales up, sharpens from a blur and fades in, on the island's spring.
@MainActor func materialize(_ layer: CALayer) {
    spring(layer, "transform.scale", from: Motion.enterScale, to: 1.0)
    ease(layer, "filters.blur.inputRadius", from: Motion.enterBlur, to: 0.0, duration: Motion.blurInDuration, out: true)
    ease(layer, "opacity", from: 0.0, to: 1.0, duration: Motion.fadeInDuration, out: true)
}

/// Exit: the entrance in reverse, quicker. The layer stays invisible afterwards.
@MainActor func dematerialize(_ layer: CALayer) {
    let shown = layer.presentation()
    retract(layer, "transform.scale", from: shown?.value(forKeyPath: "transform.scale") ?? 1.0, to: Motion.enterScale)
    retract(layer, "filters.blur.inputRadius", from: 0.0, to: Motion.exitBlur)
    retract(layer, "opacity", from: shown?.opacity ?? 1, to: 0.0)
}

@MainActor func spring(_ layer: CALayer, _ keyPath: String, from: Any, to: Any) {
    let animation = CASpringAnimation(perceptualDuration: Motion.springDuration, bounce: Motion.springBounce)
    animation.keyPath = keyPath
    animation.duration = animation.settlingDuration
    animation.fromValue = from
    animation.toValue = to
    layer.add(animation, forKey: keyPath)
}

@MainActor func ease(_ layer: CALayer, _ keyPath: String, from: Any, to: Any, duration: Double, out: Bool) {
    let c = out ? Motion.enterCurve : Motion.exitCurve
    let animation = CABasicAnimation(keyPath: keyPath)
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(controlPoints: Float(c.0), Float(c.1), Float(c.2), Float(c.3))
    layer.add(animation, forKey: keyPath)
}

/// Animates to `to` and keeps it there.
@MainActor func retract(_ layer: CALayer, _ keyPath: String, from: Any?, to: Any) {
    layer.setValue(to, forKeyPath: keyPath)
    ease(layer, keyPath, from: from as Any, to: to, duration: Motion.exitDuration, out: false)
}
