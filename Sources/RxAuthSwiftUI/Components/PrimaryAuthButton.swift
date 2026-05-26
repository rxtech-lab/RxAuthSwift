import SwiftUI

public struct PrimaryAuthButton: View {
    let title: LocalizedStringKey
    let loadingTitle: LocalizedStringKey
    let isLoading: Bool
    let accentColor: Color
    let action: () -> Void

    public init(
        title: LocalizedStringKey = "Sign In",
        loadingTitle: LocalizedStringKey = "Signing In...",
        isLoading: Bool = false,
        accentColor: Color = .blue,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.loadingTitle = loadingTitle
        self.isLoading = isLoading
        self.accentColor = accentColor
        self.action = action
    }

    public var body: some View {
        Button(action: {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                }
                Text(isLoading ? loadingTitle : title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .rxGlassProminentButton()
        .tint(accentColor)
        .disabled(isLoading)
        .accessibilityIdentifier("sign-in-button")
        .accessibilityHint(isLoading ? "Authentication in progress" : "Double tap to sign in")
    }
}
