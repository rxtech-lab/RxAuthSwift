import SwiftUI

/// Presses the label slightly on touch-down. Replaces `.buttonStyle(.plain)`
/// on the auth surfaces so glass controls respond the way system controls do.
struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleButtonStyle {
    static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }

    static func pressScale(_ scale: CGFloat) -> PressScaleButtonStyle {
        PressScaleButtonStyle(scale: scale)
    }
}

/// Horizontal shake used to draw the eye back to a field that failed
/// validation. Drive it by incrementing `animatableData` inside `withAnimation`.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: travel * sin(animatableData * .pi * shakes),
                y: 0
            )
        )
    }
}
