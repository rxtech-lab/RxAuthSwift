import SwiftUI

public struct AnimatedGradientBackground: View {
    let accentColor: Color
    let secondaryColor: Color

    @State private var animateOrbs = false

    public init(accentColor: Color = .blue, secondaryColor: Color = .purple) {
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.05).environment(\.colorScheme, .dark)

                // Orb 1
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: geometry.size.width * 0.7)
                    .blur(radius: 60)
                    .offset(
                        x: animateOrbs ? geometry.size.width * 0.2 : -geometry.size.width * 0.2,
                        y: animateOrbs ? -geometry.size.height * 0.15 : geometry.size.height * 0.15
                    )

                // Orb 2
                Circle()
                    .fill(secondaryColor.opacity(0.12))
                    .frame(width: geometry.size.width * 0.6)
                    .blur(radius: 50)
                    .offset(
                        x: animateOrbs ? -geometry.size.width * 0.15 : geometry.size.width * 0.15,
                        y: animateOrbs ? geometry.size.height * 0.2 : -geometry.size.height * 0.1
                    )

                // Orb 3
                Circle()
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: geometry.size.width * 0.5)
                    .blur(radius: 40)
                    .offset(
                        x: animateOrbs ? geometry.size.width * 0.1 : -geometry.size.width * 0.1,
                        y: animateOrbs ? geometry.size.height * 0.1 : -geometry.size.height * 0.2
                    )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                animateOrbs = true
            }
        }
    }
}
