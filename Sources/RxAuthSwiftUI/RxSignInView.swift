import RxAuthSwift
import SwiftUI

public struct RxSignInView<Header: View>: View {
    @Bindable private var manager: OAuthManager
    @State private var mode: NativeAuthMode = .signIn
    @State private var fieldValues: [String: String] = [:]
    @State private var fieldErrors: [String: String] = [:]
    @State private var isAppearing = false
    @State private var hasAttemptedSchemaLoad = false
    #if os(macOS)
    @FocusState private var focusedField: String?
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
            if appearance.showsAnimatedBackground {
                AnimatedGradientBackground(
                    accentColor: appearance.accentColor,
                    secondaryColor: appearance.secondaryColor
                )
            }
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
            } else if let infoMessage = manager.infoMessage {
                infoOverlay(message: infoMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: manager.infoMessage)
        .sheet(isPresented: Binding(
            get: { manager.pendingPasskeyOffer },
            set: { newValue in
                if !newValue && manager.pendingPasskeyOffer {
                    manager.skipPasskeyUpgradeOffer()
                    onAuthSuccess?()
                }
            }
        )) {
            passkeyOfferSheet
        }
    }

    private var passkeyOfferSheet: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(appearance.accentColor.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
            }
            .padding(.top, 24)

            VStack(spacing: 8) {
                Text("Add a passkey?")
                    .font(.title3.weight(.semibold))
                Text("Sign in next time with Touch ID or your iCloud Keychain — no password needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            if let errorMessage = manager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                Button {
                    Task {
                        do {
                            try await manager.addPasskeyForCurrentUser()
                            onAuthSuccess?()
                        } catch {
                            onAuthFailed?(error)
                        }
                    }
                } label: {
                    ZStack {
                        Text("Add Passkey")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .opacity(manager.isAuthenticating ? 0 : 1)
                        if manager.isAuthenticating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(appearance.accentColor, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(manager.isAuthenticating)
                .accessibilityIdentifier("add-passkey-button")

                Button {
                    manager.skipPasskeyUpgradeOffer()
                    onAuthSuccess?()
                } label: {
                    Text("Maybe later")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .disabled(manager.isAuthenticating)
                .accessibilityIdentifier("skip-passkey-button")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 340)
    }

    private func infoOverlay(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(appearance.accentColor)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    manager.clearInfo()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 400)
        .glassEffect(.regular.tint(appearance.accentColor.opacity(0.3)), in: .rect(cornerRadius: 12))
        .glassEffectID("info", in: glassNamespace)
        .padding(.top, 16)
        .padding(.horizontal, 32)
    }

    private func errorOverlay(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(4)

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
                if let schemaTitle = currentSchema?.title, !schemaTitle.isEmpty {
                    Text(schemaTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text(appearance.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                }

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

    private var currentSchema: AuthUISchema? {
        mode == .signIn ? manager.signInSchema : manager.signUpSchema
    }

    private var nativeCredentialForm: some View {
        VStack(spacing: 18) {
            modeTogglePill

            if let schema = currentSchema {
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        ForEach(schema.fields) { field in
                            renderField(field)
                        }
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)

                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 14) {
                        let primaryMethods = schema.supportedMethods.filter { $0.primary }
                        let secondaryMethods = schema.supportedMethods.filter { !$0.primary }
                        let orderedMethods = primaryMethods + secondaryMethods

                        ForEach(Array(orderedMethods.enumerated()), id: \.element.id) { index, method in
                            if index == primaryMethods.count, !primaryMethods.isEmpty, !secondaryMethods.isEmpty {
                                orDivider
                            }
                            methodButton(method, schema: schema)
                                .glassEffectTransition(.materialize)
                        }
                    }
                }
                .padding(.top, 6)
            } else if manager.isLoadingSchema || !hasAttemptedSchemaLoad {
                ProgressView()
                    .padding(.vertical, 40)
            } else {
                schemaErrorFallback
            }
        }
        .task(id: mode) {
            if currentSchema == nil {
                await manager.loadUISchema()
            }
            hasAttemptedSchemaLoad = true
        }
    }

    private var schemaErrorFallback: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Couldn't load sign-in form")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await manager.loadUISchema() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private func renderField(_ field: AuthUISchema.Field) -> some View {
        let binding = Binding<String>(
            get: { fieldValues[field.key] ?? "" },
            set: { newValue in
                fieldValues[field.key] = newValue
                fieldErrors[field.key] = nil
            }
        )
        VStack(alignment: .leading, spacing: 4) {
            if field.isPassword {
                secureCredentialField(field: field, text: binding)
            } else {
                credentialField(field: field, text: binding)
            }
            if let error = fieldErrors[field.key] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 14)
                    .transition(.opacity)
            }
        }
    }

    private func methodButton(_ method: AuthUISchema.SupportedMethod, schema: AuthUISchema) -> some View {
        Button {
            switch method.id {
            case .password:
                submitPrimary(schema: schema)
            case .passkey:
                submitPasskeyAction()
            case .passkeyAccountCreation:
                submitPasskeyAccountCreationAction()
            }
        } label: {
            ZStack {
                HStack(spacing: 8) {
                    if method.id == .passkey || method.id == .passkeyAccountCreation {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(method.primary ? Color.white : appearance.accentColor)
                    }
                    Text(method.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(method.primary ? Color.white : .primary)
                }
                .opacity(manager.isAuthenticating ? 0 : 1)

                if manager.isAuthenticating, isCurrentSubmitMethod(method) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .glassEffect(
                method.primary
                    ? .regular.tint(appearance.accentColor).interactive()
                    : .regular.interactive(),
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .glassEffectID("method-\(method.id.rawValue)", in: glassNamespace)
        .disabled(manager.isAuthenticating)
        .opacity(manager.isAuthenticating ? 0.7 : 1)
        .keyboardShortcut(method.primary ? .defaultAction : nil)
        .accessibilityIdentifier(accessibilityIdentifier(for: method))
    }

    private func accessibilityIdentifier(for method: AuthUISchema.SupportedMethod) -> String {
        switch method.id {
        case .password: return "sign-in-button"
        case .passkey: return "passkey-sign-in-button"
        case .passkeyAccountCreation: return "passkey-account-creation-button"
        }
    }

    private func isCurrentSubmitMethod(_ method: AuthUISchema.SupportedMethod) -> Bool {
        // Best-effort indicator; primary method shows progress when authenticating.
        method.primary
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

    private func credentialField(
        field: AuthUISchema.Field,
        text: Binding<String>
    ) -> some View {
        let isFocused = focusedField == field.key
        return HStack(spacing: 12) {
            Image(systemName: iconName(for: field))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFocused ? appearance.accentColor : Color.secondary)
                .frame(width: 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
                .scaleEffect(isFocused ? 1.1 : 1.0)

            TextField(field.placeholder ?? field.label, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focusedField, equals: field.key)
                .submitLabel(.next)
                .onSubmit { advanceFocus(from: field.key) }
                .accessibilityIdentifier("\(field.key)-field")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(
            isFocused ? .regular.tint(appearance.accentColor.opacity(0.2)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 12)
        )
        .glassEffectID("field-\(field.key)", in: glassNamespace)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }

    private func secureCredentialField(
        field: AuthUISchema.Field,
        text: Binding<String>
    ) -> some View {
        let isFocused = focusedField == field.key
        return HStack(spacing: 12) {
            Image(systemName: iconName(for: field))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFocused ? appearance.accentColor : Color.secondary)
                .frame(width: 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
                .scaleEffect(isFocused ? 1.1 : 1.0)

            SecureField(field.placeholder ?? field.label, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focusedField, equals: field.key)
                .onSubmit {
                    if let schema = currentSchema { submitPrimary(schema: schema) }
                }
                .accessibilityIdentifier("\(field.key)-field")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(
            isFocused ? .regular.tint(appearance.accentColor.opacity(0.2)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 12)
        )
        .glassEffectID("field-\(field.key)", in: glassNamespace)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }

    private func iconName(for field: AuthUISchema.Field) -> String {
        switch field.type {
        case .email: return "envelope"
        case .password: return "lock.fill"
        case .name: return "person.text.rectangle"
        case .text: return "person.crop.circle"
        }
    }

    private func advanceFocus(from key: String) {
        guard let schema = currentSchema,
              let idx = schema.fields.firstIndex(where: { $0.key == key })
        else { return }
        let next = idx + 1
        if next < schema.fields.count {
            focusedField = schema.fields[next].key
        } else {
            submitPrimary(schema: schema)
        }
    }

    private func value(forKey key: String) -> String {
        fieldValues[key] ?? ""
    }

    private func primaryIdentifier(_ schema: AuthUISchema) -> String {
        // Server-driven username/email is whichever non-password field comes first.
        for field in schema.fields where !field.isPassword && field.type != .name {
            return value(forKey: field.key)
        }
        return value(forKey: "email").isEmpty ? value(forKey: "username") : value(forKey: "email")
    }

    private func validate(_ schema: AuthUISchema, requirePassword: Bool) -> Bool {
        var errors: [String: String] = [:]
        for field in schema.fields {
            if !requirePassword && field.isPassword { continue }
            if let error = field.validate(value(forKey: field.key)) {
                errors[field.key] = error
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            fieldErrors = errors
        }
        return errors.isEmpty
    }

    private func submitPrimary(schema: AuthUISchema) {
        guard validate(schema, requirePassword: true) else { return }
        let identifier = primaryIdentifier(schema)
        let password = value(forKey: "password")
        let name = value(forKey: "name")

        Task {
            do {
                switch mode {
                case .signIn:
                    try await manager.authenticate(username: identifier, password: password)
                    onAuthSuccess?()
                case .signUp:
                    let result = try await manager.signUp(username: identifier, password: password, name: name)
                    switch result {
                    case .authenticated:
                        if !manager.pendingPasskeyOffer {
                            onAuthSuccess?()
                        }
                        // Otherwise the sheet bound to `manager.pendingPasskeyOffer`
                        // takes over; it will call `onAuthSuccess` once the user
                        // either adds a passkey or skips.
                    case .emailVerificationRequired:
                        fieldValues["password"] = ""
                        fieldValues["name"] = ""
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            mode = .signIn
                        }
                    }
                }
            } catch {
                onAuthFailed?(error)
            }
        }
    }

    private func submitPasskeyAction() {
        guard let schema = currentSchema else { return }

        // For passkey sign-in, skip validation - the passkey identifies the user.
        // For sign-up, we still need to validate user info fields.
        if mode == .signUp {
            guard validate(schema, requirePassword: false) else { return }
        }

        let identifier = primaryIdentifier(schema)
        let name = value(forKey: "name")

        Task {
            do {
                switch mode {
                case .signIn:
                    try await manager.authenticateWithPasskey(username: identifier)
                case .signUp:
                    try await manager.signUpWithPasskey(username: identifier, name: name)
                }
                onAuthSuccess?()
            } catch {
                onAuthFailed?(error)
            }
        }
    }

    /// System-sheet account creation (iOS 26 / macOS 26): no fields, no
    /// validation — the OS sheet collects email/name from iCloud. Only
    /// reachable when the server emits the `passkey_account_creation`
    /// method in the signup schema.
    private func submitPasskeyAccountCreationAction() {
        Task {
            do {
                try await manager.createAccountWithPasskey()
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

#Preview("No Animated Background") {
    RxSignInView(
        manager: OAuthManager(
            configuration: RxAuthConfiguration(
                issuer: "https://auth.example.com",
                clientID: "preview-client",
                redirectURI: "myapp://callback"
            )
        ),
        appearance: RxSignInAppearance(
            accentColor: .blue,
            secondaryColor: .purple,
            showsAnimatedBackground: false
        )
    )
    .preferredColorScheme(.dark)
}

#if DEBUG
private struct GroupedMethodsPreview: View {
    @State private var manager: OAuthManager = {
        let manager = OAuthManager(
            configuration: RxAuthConfiguration(
                issuer: "https://auth.example.com",
                clientID: "preview-client",
                redirectURI: "myapp://callback"
            )
        )
        let json = #"""
        {
          "flow": "signin",
          "title": "Welcome back",
          "submitLabel": "Sign In",
          "fields": [
            { "key": "email", "label": "Email", "placeholder": "you@example.com", "type": "email", "isPassword": false, "required": true, "autocomplete": "email" },
            { "key": "password", "label": "Password", "placeholder": "••••••••", "type": "password", "isPassword": true, "required": true, "autocomplete": "current-password" }
          ],
          "supportedMethods": [
            { "id": "password", "label": "Sign In", "primary": true },
            { "id": "passkey", "label": "Sign in with Passkey", "primary": false },
            { "id": "passkey_account_creation", "label": "Use iCloud Keychain", "primary": false }
          ]
        }
        """#
        let signIn = try! JSONDecoder().decode(AuthUISchema.self, from: Data(json.utf8))
        manager._previewInject(signIn: signIn, signUp: nil)
        return manager
    }()

    var body: some View {
        RxSignInView(manager: manager)
    }
}

#Preview("Grouped Methods (1 primary + 2 secondary)") {
    GroupedMethodsPreview()
        .preferredColorScheme(.dark)
}
#endif

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
