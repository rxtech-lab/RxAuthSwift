import SwiftUI

/// Slow-drifting mesh gradient behind the auth surfaces.
///
/// Corner control points stay pinned and edge points slide along their own
/// edge, so the mesh never folds over itself; only the interior points wander.
/// Honors Reduce Motion by falling back to the static mesh.
public struct AnimatedGradientBackground: View {
    let accentColor: Color
    let secondaryColor: Color

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(accentColor: Color = .blue, secondaryColor: Color = .purple) {
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
    }

    public var body: some View {
        ZStack {
            base

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: points(at: t),
                    colors: meshColors,
                    smoothsColors: true
                )
                .blur(radius: 24)
            }

            // Darkens the outer frame so the glass controls in the middle keep
            // their contrast against the brightest part of the mesh.
            RadialGradient(
                colors: [.clear, base.opacity(colorScheme == .dark ? 0.65 : 0.4)],
                center: .center,
                startRadius: 120,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private var base: Color {
        colorScheme == .dark ? Color(white: 0.07) : Color(white: 0.96)
    }

    /// 3×3 mesh: base tone in the corners, accent/secondary washes through the
    /// middle band so the color reads as light bleeding in rather than a wash.
    /// Kept deliberately low — this sits behind text, so it should register as
    /// atmosphere, not as colored blobs.
    private var meshColors: [Color] {
        let strong: Double = colorScheme == .dark ? 0.38 : 0.20
        let mid: Double = colorScheme == .dark ? 0.24 : 0.13
        let soft: Double = colorScheme == .dark ? 0.12 : 0.07

        return [
            base, blend(accentColor, strong), base,
            blend(secondaryColor, mid), blend(accentColor, soft), blend(accentColor, mid),
            base, blend(secondaryColor, mid), base,
        ]
    }

    private func blend(_ color: Color, _ amount: Double) -> Color {
        base.mix(with: color, by: amount)
    }

    private func points(at t: TimeInterval) -> [SIMD2<Float>] {
        func drift(_ seed: Double, speed: Double, amplitude: Double) -> Float {
            Float(sin(t * speed + seed) * amplitude)
        }

        return [
            SIMD2(0, 0),
            SIMD2(0.5 + drift(0.0, speed: 0.31, amplitude: 0.10), 0),
            SIMD2(1, 0),

            SIMD2(0, 0.5 + drift(1.3, speed: 0.27, amplitude: 0.10)),
            SIMD2(
                0.5 + drift(2.1, speed: 0.23, amplitude: 0.16),
                0.5 + drift(3.4, speed: 0.19, amplitude: 0.16)
            ),
            SIMD2(1, 0.5 + drift(4.2, speed: 0.29, amplitude: 0.10)),

            SIMD2(0, 1),
            SIMD2(0.5 + drift(5.0, speed: 0.21, amplitude: 0.10), 1),
            SIMD2(1, 1),
        ]
    }
}

#Preview("Dark") {
    AnimatedGradientBackground(accentColor: .blue, secondaryColor: .purple)
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AnimatedGradientBackground(accentColor: .indigo, secondaryColor: .pink)
        .preferredColorScheme(.light)
}
