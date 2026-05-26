import RxAuthSwift
import SwiftUI

public struct RxSignInView<Header: View>: View {
    @Bindable private var manager: OAuthManager
    @State private var mode: NativeAuthMode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isAppearing = false
    #if os(macOS)
    @FocusState private var focusedField: CredentialField?
    @Namespace private var glassNamespace
    #endif
    private let appearance: RxSignInAppearance
    private let customHeader: Header?
    private let onAuthSuccess: (() -> Void)?
    private let onAuthFailed: ((Error) -> Void)?

    // MARK: - Simple Init (appearance struct)

    public init(
        manager: OAuthManager,
        appearance: RxSignInAppearance = RxSignInAppearance(),
        onAuthSuccess: (() -> Void)? = nil,
        onAuthFailed: ((Error) -> Void)? = nil
    ) where Header == Never {
        self.manager = manager
        self.appearance = appearance
        self.customHeader = nil
        self.onAuthSuccess = onAuthSuccess
        self.onAuthFailed = onAuthFailed
    }

    // MARK: - Advanced Init (ViewBuilder for custom header)

    public init(
        manager: OAuthManager,
        appearance: RxSignInAppearance = RxSignInAppearance(),
        onAuthSuccess: (() -> Void)? = nil,
        onAuthFailed: ((Error) -> Void)? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.manager = manager
        self.appearance = appearance
        self.customHeader = header()
        self.onAuthSuccess = onAuthSuccess
        self.onAuthFailed = onAuthFailed
    }

    public var body: some View {
        ZStack {
            #if os(macOS)
            AnimatedGradientBackground(
                accentColor: appearance.accentColor,
                secondaryColor: appearance.secondaryColor
            )
            macOSContent
            #else
            AnimatedGradientBackground(
                accentColor: appearance.accentColor,
                secondaryColor: appearance.secondaryColor
            )
            iOSContent
            #endif
        }
        .animation(.default, value: manager.errorMessage)
    }

    #if os(macOS)
    private var macOSContent: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    GlassEffectContainer(spacing: 20) {
                        VStack(spacing: 24) {
                            if let customHeader {
                                customHeader
                                    .scaleEffect(isAppearing ? 1 : 0.9)
                                    .opacity(isAppearing ? 1 : 0)
                            } else {
                                compactHeader
                                    .scaleEffect(isAppearing ? 1 : 0.9)
                                    .opacity(isAppearing ? 1 : 0)
                            }

                            nativeCredentialForm
                        }
                        .padding(32)
                        .frame(minWidth: 360, maxWidth: 400, minHeight: 480, alignment: .top)
                    }
                    .padding(.horizontal, 32)
                    .offset(y: isAppearing ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isAppearing)

                    Spacer(minLength: 32)
                }
                .frame(maxWidth: .infinity, minHeight: 580)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    isAppearing = true
                }
            }

            // Error overlay
            if let errorMessage = manager.errorMessage {
                errorOverlay(message: errorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func errorOverlay(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    manager.clearError()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 400)
        .glassEffect(.regular.tint(.red.opacity(0.3)), in: .rect(cornerRadius: 12))
        .glassEffectID("error", in: glassNamespace)
        .padding(.top, 16)
        .padding(.horizontal, 32)
    }
    #else
    private var iOSContent: some View {
        VStack(spacing: 32) {
            Spacer()
            if let customHeader {
                customHeader
            } else {
                defaultHeader
            }
            Spacer()

            if let errorMessage = manager.errorMessage {
                AuthErrorBanner(message: errorMessage)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(spacing: 12) {
                PrimaryAuthButton(
                    title: appearance.signInButtonTitle,
                    isLoading: manager.isAuthenticating,
                    accentColor: appearance.accentColor
                ) {
                    Task {
                        do {
                            try await manager.authenticate()
                            onAuthSuccess?()
                        } catch {
                            onAuthFailed?(error)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
    #endif

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
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(appearance.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
    }

    #if os(macOS)
    private var compactHeader: some View {
        VStack(spacing: 14) {
            compactIcon
                .glassEffectID("header-icon", in: glassNamespace)

            VStack(spacing: 6) {
                Text(appearance.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(appearance.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var compactIcon: some View {
        switch appearance.icon {
        case .systemImage(let name):
            Image(systemName: name)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(appearance.accentColor)
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(appearance.accentColor.opacity(0.3)), in: .rect(cornerRadius: 18))
        case .image(let image):
            image
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .assetImage(let name, let bundle):
            Image(name, bundle: bundle)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .none:
            EmptyView()
        }
    }

    private var nativeCredentialForm: some View {
        VStack(spacing: 18) {
            modeTogglePill

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    if mode == .signUp {
                        credentialField(
                            systemImage: "person.text.rectangle",
                            placeholder: appearance.namePlaceholder,
                            text: $name,
                            field: .name,
                            accessibilityIdentifier: "name-field"
                        )
                        .glassEffectTransition(.matchedGeometry)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)))
                    }

                    credentialField(
                        systemImage: "person.crop.circle",
                        placeholder: appearance.usernamePlaceholder,
                        text: $username,
                        field: .username,
                        accessibilityIdentifier: "username-field"
                    )

                    secureCredentialField(
                        systemImage: "lock.fill",
                        placeholder: appearance.passwordPlaceholder,
                        text: $password
                    )
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)

            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 14) {
                    primaryButton
                        .keyboardShortcut(.defaultAction)

                    if showsPasskeyButton {
                        orDivider

                        passkeyButton
                            .glassEffectTransition(.materialize)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var modeTogglePill: some View {
        HStack(spacing: 0) {
            modeTab(.signIn, label: "Sign In")
            modeTab(.signUp, label: "Sign Up")
        }
        .padding(4)
        .glassEffect(in: .capsule)
        .glassEffectID("mode-toggle-container", in: glassNamespace)
        .accessibilityIdentifier("auth-mode-picker")
        .disabled(manager.isAuthenticating)
    }

    private func modeTab(_ value: NativeAuthMode, label: String) -> some View {
        let isSelected = mode == value
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                mode = value
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(appearance.accentColor)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var primaryButton: some View {
        Button {
            submitPrimary()
        } label: {
            ZStack {
                Text(mode == .signIn ? appearance.signInButtonTitle : appearance.signUpButtonTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(manager.isAuthenticating ? 0 : 1)

                if manager.isAuthenticating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .glassEffect(.regular.tint(appearance.accentColor).interactive(), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .glassEffectID("primary-button", in: glassNamespace)
        .disabled(manager.isAuthenticating)
        .opacity(manager.isAuthenticating ? 0.7 : 1)
        .accessibilityIdentifier("sign-in-button")
    }

    private var orDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.5)
            Text("or")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.5)
        }
    }

    private var passkeyButton: some View {
        Button {
            submitPasskeyAction()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appearance.accentColor)
                Text(mode == .signIn ? appearance.passkeyButtonTitle : appearance.passkeySignupButtonTitle)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .glassEffectID("passkey-button", in: glassNamespace)
        .disabled(manager.isAuthenticating)
        .accessibilityIdentifier("passkey-sign-in-button")
    }

    private func credentialField(
        systemImage: String,
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        field: CredentialField,
        accessibilityIdentifier: String
    ) -> some View {
        let isFocused = focusedField == field
        return HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFocused ? appearance.accentColor : Color.secondary)
                .frame(width: 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
                .scaleEffect(isFocused ? 1.1 : 1.0)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focusedField, equals: field)
                .submitLabel(.next)
                .onSubmit(advanceFocus)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(
            isFocused ? .regular.tint(appearance.accentColor.opacity(0.2)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 12)
        )
        .glassEffectID("field-\(field)", in: glassNamespace)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }

    private func secureCredentialField(
        systemImage: String,
        placeholder: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        let isFocused = focusedField == .password
        return HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFocused ? appearance.accentColor : Color.secondary)
                .frame(width: 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
                .scaleEffect(isFocused ? 1.1 : 1.0)

            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focusedField, equals: .password)
                .onSubmit(submitPrimary)
                .accessibilityIdentifier("password-field")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(
            isFocused ? .regular.tint(appearance.accentColor.opacity(0.2)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 12)
        )
        .glassEffectID("field-password", in: glassNamespace)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }

    private func advanceFocus() {
        switch focusedField {
        case .name:
            focusedField = .username
        case .username:
            focusedField = .password
        case .password, .none:
            submitPrimary()
        }
    }

    private var showsPasskeyButton: Bool {
        switch mode {
        case .signIn:
            return manager.supportsPasskeyAuthentication
        case .signUp:
            return manager.supportsPasskeyRegistration
        }
    }

    private func submitPrimary() {
        Task {
            do {
                switch mode {
                case .signIn:
                    try await manager.authenticate(username: username, password: password)
                case .signUp:
                    try await manager.signUp(username: username, password: password, name: name)
                }
                onAuthSuccess?()
            } catch {
                onAuthFailed?(error)
            }
        }
    }

    private func submitPasskeyAction() {
        Task {
            do {
                switch mode {
                case .signIn:
                    try await manager.authenticateWithPasskey(username: username)
                case .signUp:
                    try await manager.signUpWithPasskey(username: username, name: name)
                }
                onAuthSuccess?()
            } catch {
                onAuthFailed?(error)
            }
        }
    }
    #endif
}

private enum NativeAuthMode: Hashable {
    case signIn
    case signUp
}

#if os(macOS)
private enum CredentialField: Hashable {
    case name
    case username
    case password
}
#endif

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
