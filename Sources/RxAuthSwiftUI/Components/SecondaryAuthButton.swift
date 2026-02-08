import SwiftUI

public struct SecondaryAuthButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    public init(
        title: String,
        systemImage: String = "questionmark.circle",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .rxGlassButton()
        .accessibilityIdentifier("secondaryAuthButton")
    }
}
