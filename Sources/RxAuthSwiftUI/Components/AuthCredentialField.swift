import RxAuthSwift
import SwiftUI

/// A single credential input rendered from a server-driven `AuthUISchema.Field`.
///
/// The label starts centered as a placeholder and floats up into a caption once
/// the field is focused or filled, so the row keeps its meaning after the user
/// has typed. Password rows gain a reveal toggle; text rows gain a clear button
/// while focused.
struct AuthCredentialField: View {
    let field: AuthUISchema.Field
    @Binding var text: String
    let error: String?
    let accentColor: Color
    /// Drives `newPassword` vs `password` content types so iOS offers the
    /// strong-password sheet on sign-up and Keychain fill on sign-in.
    let isSignUp: Bool
    let isLast: Bool
    let namespace: Namespace.ID
    @FocusState.Binding var focusedField: String?
    let onSubmit: () -> Void

    @State private var isRevealed = false
    @State private var shakePhase: CGFloat = 0

    private var isFocused: Bool { focusedField == field.key }
    private var isFloating: Bool { isFocused || !text.isEmpty }
    private var hasError: Bool { error != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldRow

            if let error {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.red)
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: error)
        .onChange(of: error) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.linear(duration: 0.4)) { shakePhase += 1 }
        }
    }

    // MARK: - Row

    private var fieldRow: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 24)
                .symbolEffect(.bounce, value: isFocused)

            ZStack(alignment: .leading) {
                Text(field.label)
                    .font(.system(
                        size: isFloating ? 12 : Metrics.inputFont,
                        weight: isFloating ? .semibold : .regular
                    ))
                    .foregroundStyle(labelTint)
                    .offset(y: isFloating ? -Metrics.labelFloat : 0)
                    .allowsHitTesting(false)

                // Deliberately never hidden: "not floating" already implies the
                // field is empty and unfocused, so there is nothing to overlap
                // the centered label. Fading it out instead drops it out of the
                // accessibility tree, which breaks VoiceOver and UI automation.
                input
                    .offset(y: isFloating ? Metrics.inputDrop : 0)
            }
            .frame(height: Metrics.stackHeight, alignment: .center)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isFloating)

            accessory
        }
        .padding(.horizontal, 18)
        .frame(height: Metrics.rowHeight)
        .glassEffect(glass, in: .rect(cornerRadius: Metrics.corner))
        .glassEffectID("field-\(field.key)", in: namespace)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .strokeBorder(borderTint, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: Metrics.corner))
        .onTapGesture { focusedField = field.key }
        .modifier(ShakeEffect(animatableData: shakePhase))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasError)
    }

    @ViewBuilder
    private var input: some View {
        Group {
            if field.isPassword && !isRevealed {
                SecureField("", text: $text)
            } else {
                TextField("", text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: Metrics.inputFont))
        .focused($focusedField, equals: field.key)
        .submitLabel(isLast ? .go : .next)
        .onSubmit(onSubmit)
        .autocorrectionDisabled(true)
        .textContentType(contentType)
        #if os(iOS)
        .textInputAutocapitalization(autocapitalization)
        .keyboardType(keyboardType)
        #endif
        .accessibilityIdentifier("\(field.key)-field")
        .accessibilityLabel(Text(field.label))
    }

    @ViewBuilder
    private var accessory: some View {
        if field.isPassword {
            Button {
                isRevealed.toggle()
                // Swapping SecureField/TextField rebuilds the responder, so
                // hand focus back explicitly.
                focusedField = field.key
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            .accessibilityIdentifier("\(field.key)-reveal-toggle")
        } else if isFocused && !text.isEmpty {
            Button {
                text = ""
                focusedField = field.key
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale))
            .accessibilityLabel("Clear \(field.label)")
        }
    }

    // MARK: - Styling

    /// Focus should read as a quiet lift, not a colored block — the tint stays
    /// low and the accent shows up in the hairline and the icon instead.
    private var glass: Glass {
        if hasError {
            return .regular.tint(.red.opacity(0.10)).interactive()
        }
        if isFocused {
            return .regular.tint(accentColor.opacity(0.08)).interactive()
        }
        return .regular.interactive()
    }

    private var borderTint: Color {
        if hasError { return .red.opacity(0.5) }
        return isFocused ? accentColor.opacity(0.5) : .primary.opacity(0.14)
    }

    private var iconTint: Color {
        if hasError { return .red.opacity(0.85) }
        return isFocused ? accentColor : .secondary
    }

    private var labelTint: Color {
        hasError ? .red.opacity(0.9) : .secondary
    }

    private var iconName: String {
        switch field.type {
        case .email: return "envelope.fill"
        case .password: return "lock.fill"
        case .name: return "person.fill"
        case .text: return "person.crop.circle.fill"
        }
    }

    private enum Metrics {
        #if os(iOS)
        static let rowHeight: CGFloat = 58
        #else
        static let rowHeight: CGFloat = 52
        #endif
        static let stackHeight: CGFloat = rowHeight - 18
        static let labelFloat: CGFloat = rowHeight / 2 - 17
        static let inputDrop: CGFloat = 8
        static let corner: CGFloat = 14
        static let inputFont: CGFloat = 17
    }

    // MARK: - AutoFill

    #if os(iOS)
    private var contentType: UITextContentType? {
        switch field.autocomplete ?? "" {
        case "email", "username": return .username
        case "current-password": return .password
        case "new-password": return .newPassword
        case "name": return .name
        case "given-name": return .givenName
        case "family-name": return .familyName
        case "one-time-code": return .oneTimeCode
        default: break
        }
        switch field.type {
        // `.username` (not `.emailAddress`) is what pairs an identifier with a
        // password field for Keychain credential fill.
        case .email: return .username
        case .password: return isSignUp ? .newPassword : .password
        case .name: return .name
        case .text: return nil
        }
    }

    private var keyboardType: UIKeyboardType {
        field.type == .email ? .emailAddress : .default
    }

    private var autocapitalization: TextInputAutocapitalization {
        field.type == .name ? .words : .never
    }
    #else
    private var contentType: NSTextContentType? {
        switch field.autocomplete ?? "" {
        case "email", "username": return .username
        case "current-password": return .password
        case "new-password": return .newPassword
        case "one-time-code": return .oneTimeCode
        default: break
        }
        switch field.type {
        case .email: return .username
        case .password: return isSignUp ? .newPassword : .password
        case .name, .text: return nil
        }
    }
    #endif
}
