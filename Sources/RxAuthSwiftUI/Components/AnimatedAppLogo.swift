import SwiftUI
import RxAuthSwift

public struct AnimatedAppLogo: View {
    let icon: RxSignInAppearance.SignInIcon
    let accentColor: Color

    @State private var isFloating = false
    @State private var glowPulse = false

    public init(icon: RxSignInAppearance.SignInIcon, accentColor: Color = .blue) {
        self.icon = icon
        self.accentColor = accentColor
    }

    public var body: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(glowPulse ? 0.4 : 0.1), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)

            // Icon container
            iconView
                .frame(width: 80, height: 80)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
        }
        .offset(y: isFloating ? -8 : 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                isFloating = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .accessibilityLabel("App logo")
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .systemImage(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundStyle(accentColor)
        case .image(let image):
            image
                .resizable()
                .scaledToFit()
        case .assetImage(let name, let bundle):
            Image(name, bundle: bundle)
                .resizable()
                .scaledToFit()
        case .none:
            EmptyView()
        }
    }
}
