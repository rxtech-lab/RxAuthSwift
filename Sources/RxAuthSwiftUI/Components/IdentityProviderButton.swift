import RxAuthSwift
import SwiftDraw
import SwiftUI

/// One "Continue with …" row for a third-party identity provider advertised by
/// the server's UI schema.
///
/// It shares the alternative-method shape from `AuthMethodButton` so Google
/// and GitHub sit in the same list as "Sign in with passkey" rather than
/// forming a second, differently styled block. The brand mark streams from the
/// schema's icon URL — SVG rendered by SwiftDraw, since `AsyncImage` cannot
/// decode it — so a provider the server enables tomorrow shows up with its
/// real logo without a client release.
struct IdentityProviderButton: View {
    let provider: AuthUISchema.IdentityProvider
    let accentColor: Color
    let isBusy: Bool
    let isRunning: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
                label.opacity(isRunning ? 0 : 1)

                if isRunning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(accentColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.height)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.corner))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                    .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.pressScale)
        .glassEffectID("identity-\(provider.id)", in: namespace)
        .disabled(isBusy)
        .opacity(isBusy && !isRunning ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: isBusy)
        .accessibilityIdentifier("identity-provider-\(provider.id)-button")
    }

    private var label: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: Metrics.iconSide, height: Metrics.iconSide)
            Text(provider.label)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
    }

    /// The icon slot keeps its frame through every phase so the label never
    /// jumps sideways when the SVG arrives.
    @ViewBuilder
    private var icon: some View {
        if let url = provider.iconURL(dark: colorScheme == .dark) {
            AsyncSVGView(url: url) { phase in
                switch phase {
                case .success(let svg):
                    SVGView(svg: svg)
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity)
                case .failure:
                    fallbackIcon
                case .empty:
                    Color.clear
                }
            }
            .animation(.easeOut(duration: 0.2), value: url)
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "person.crop.circle.badge.checkmark")
            .font(.system(size: 16, weight: .semibold))
    }

    private enum Metrics {
        #if os(iOS)
        static let height: CGFloat = 52
        #else
        static let height: CGFloat = 44
        #endif
        static let corner: CGFloat = 14
        static let iconSide: CGFloat = 18
    }
}
