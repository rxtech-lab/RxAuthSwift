import SwiftUI
import RxAuthSwift

public struct RxSignInView<Header: View>: View {
    @Bindable private var manager: OAuthManager
    private let appearance: RxSignInAppearance
    private let customHeader: Header?

    // MARK: - Simple Init (appearance struct)

    public init(
        manager: OAuthManager,
        appearance: RxSignInAppearance = RxSignInAppearance()
    ) where Header == Never {
        self.manager = manager
        self.appearance = appearance
        self.customHeader = nil
    }

    // MARK: - Advanced Init (ViewBuilder for custom header)

    public init(
        manager: OAuthManager,
        appearance: RxSignInAppearance = RxSignInAppearance(),
        @ViewBuilder header: () -> Header
    ) {
        self.manager = manager
        self.appearance = appearance
        self.customHeader = header()
    }

    public var body: some View {
        ZStack {
            AnimatedGradientBackground(
                accentColor: appearance.accentColor,
                secondaryColor: appearance.secondaryColor
            )

            VStack(spacing: 32) {
                Spacer()

                // Header area
                if let customHeader {
                    customHeader
                } else {
                    defaultHeader
                }

                Spacer()

                // Error banner
                if let errorMessage = manager.errorMessage {
                    AuthErrorBanner(message: errorMessage)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Sign-in buttons
                VStack(spacing: 12) {
                    PrimaryAuthButton(
                        title: appearance.signInButtonTitle,
                        isLoading: manager.isAuthenticating,
                        accentColor: appearance.accentColor
                    ) {
                        Task {
                            do {
                                try await manager.authenticate()
                            } catch {
                                // Error is handled by the manager
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .animation(.default, value: manager.errorMessage)
    }

    @ViewBuilder
    private var defaultHeader: some View {
        VStack(spacing: 20) {
            AnimatedAppLogo(
                icon: appearance.icon,
                accentColor: appearance.accentColor
            )

            VStack(spacing: 8) {
                Text(appearance.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(appearance.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Previews

#Preview("Default Appearance") {
    RxSignInView(
        manager: OAuthManager(
            configuration: RxAuthConfiguration(
                issuer: "https://auth.example.com",
                clientID: "preview-client",
                redirectURI: "myapp://callback"
            )
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Custom Appearance") {
    RxSignInView(
        manager: OAuthManager(
            configuration: RxAuthConfiguration(
                issuer: "https://auth.example.com",
                clientID: "preview-client",
                redirectURI: "myapp://callback"
            )
        ),
        appearance: RxSignInAppearance(
            icon: .systemImage("person.circle.fill"),
            title: "My App",
            subtitle: "Sign in to access your account",
            signInButtonTitle: "Get Started",
            accentColor: .purple,
            secondaryColor: .pink
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Custom Header") {
    RxSignInView(
        manager: OAuthManager(
            configuration: RxAuthConfiguration(
                issuer: "https://auth.example.com",
                clientID: "preview-client",
                redirectURI: "myapp://callback"
            )
        )
    ) {
        VStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)
            Text("Custom Header")
                .font(.title.bold())
            Text("This is a fully custom header view")
                .foregroundStyle(.secondary)
        }
    }
    .preferredColorScheme(.dark)
}
