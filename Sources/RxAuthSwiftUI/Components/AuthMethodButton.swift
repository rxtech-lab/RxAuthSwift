import RxAuthSwift
import SwiftUI

/// One entry in the server-driven list of supported auth methods.
///
/// `prominent` drives two distinct shapes: a prominent method is a centered,
/// tinted call-to-action, while the rest render as left-aligned rows so they
/// read as a list of other ways in rather than as competing buttons. It
/// defaults to the schema's `primary` flag but is forced on for the submit
/// button of the credential stage, where the chosen method is the only action.
///
/// Only the method that was actually tapped shows a spinner — the others fade
/// back so the surface reads as "this one is working" rather than
/// "everything is busy".
struct AuthMethodButton: View {
    let method: AuthUISchema.SupportedMethod
    let accentColor: Color
    let isBusy: Bool
    let isRunning: Bool
    let namespace: Namespace.ID
    var prominent: Bool?
    var showsSymbol: Bool = true
    /// Distinguishes the picker entry from the credential-stage submit button,
    /// which share a method id and therefore an accessibility identifier.
    var glassIDSuffix: String = ""
    let action: () -> Void

    private var isProminent: Bool { prominent ?? method.primary }

    var body: some View {
        Button(action: action) {
            ZStack {
                label.opacity(isRunning ? 0 : 1)

                if isRunning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(isProminent ? .white : accentColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.height)
            .glassEffect(
                isProminent
                    ? .regular.tint(accentColor).interactive()
                    : .regular.interactive(),
                in: .rect(cornerRadius: Metrics.corner)
            )
            // Plain glass all but disappears over a dark background; a hairline
            // gives the alternatives an edge without making them compete.
            .overlay {
                if !isProminent {
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                }
            }
            .shadow(
                color: isProminent ? accentColor.opacity(0.25) : .clear,
                radius: 12,
                y: 6
            )
        }
        .buttonStyle(.pressScale)
        .glassEffectID("method-\(method.id.rawValue)\(glassIDSuffix)", in: namespace)
        .disabled(isBusy)
        .opacity(isBusy && !isRunning ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: isBusy)
        .keyboardShortcut(isProminent ? .defaultAction : nil)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    /// Both weights share one shape and one centered layout — the fill is the
    /// only thing that ranks them, the way stacked system sign-in buttons do.
    private var label: some View {
        HStack(spacing: 8) {
            // The filled button is already unambiguous; the icon only earns its
            // place on the alternatives, where it names the mechanism.
            if showsSymbol && !isProminent {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(method.label)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(isProminent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 16)
    }

    private var symbol: String {
        switch method.id {
        case .password: return "envelope.fill"
        case .passkey: return "person.badge.key.fill"
        case .passkeyAccountCreation: return "sparkles"
        }
    }

    private var accessibilityIdentifier: String {
        switch method.id {
        case .password: return "sign-in-button"
        case .passkey: return "passkey-sign-in-button"
        case .passkeyAccountCreation: return "passkey-account-creation-button"
        }
    }

    private enum Metrics {
        #if os(iOS)
        static let height: CGFloat = 52
        #else
        static let height: CGFloat = 44
        #endif
        static let corner: CGFloat = 14
    }
}
