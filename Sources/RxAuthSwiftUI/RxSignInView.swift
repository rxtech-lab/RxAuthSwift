import RxAuthSwift
import SwiftUI

public struct RxSignInView<Header: View>: View {
    @Bindable private var manager: OAuthManager
    @State private var mode: NativeAuthMode = .signIn
    @State private var fieldValues: [String: String] = [:]
    @State private var fieldErrors: [String: String] = [:]
    @State private var isAppearing = false
    @State private var hasAttemptedSchemaLoad = false
    /// The method the user actually tapped, so only that button spins.
    @State private var activeMethod: AuthUISchema.SupportedMethod.MethodID?
    @State private var stage: FormStage = .methodPicker
    /// The method whose credentials the form is currently collecting.
    @State private var pendingMethod: AuthUISchema.SupportedMethod?
    @FocusState private var focusedField: String?
    @Namespace private var glassNamespace
    private let appearance: RxSignInAppearance
    private let style: RxSignInStyle
    private let customHeader: Header?
    private let onAuthSuccess: (() -> Void)?
    private let onAuthFailed: ((Error) -> Void)?

    // MARK: - Simple Init (appearance struct)

    public init(
        manager: OAuthManager,
        appearance: RxSignInAppearance = RxSignInAppearance(),
        style: RxSignInStyle = .web,
        onAuthSuccess: (() -> Void)? = nil,
        onAuthFailed: ((Error) -> Void)? = nil
    ) where Header == Never {
        self.manager = manager
        self.appearance = appearance
        self.style = style
        self.customHeader = nil
        self.onAuthSuccess = onAuthSuccess
        self.onAuthFailed = onAuthFailed
    }

    // MARK: - Advanced Init (ViewBuilder for custom header)

    public init(
        manager: OAuthManager,
        appearance: RxSignInAppearance = RxSignInAppearance(),
        style: RxSignInStyle = .web,
        onAuthSuccess: (() -> Void)? = nil,
        onAuthFailed: ((Error) -> Void)? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.manager = manager
        self.appearance = appearance
        self.style = style
        self.customHeader = header()
        self.onAuthSuccess = onAuthSuccess
        self.onAuthFailed = onAuthFailed
    }

    public var body: some View {
        ZStack {
            if appearance.showsAnimatedBackground {
                AnimatedGradientBackground(
                    accentColor: appearance.accentColor,
                    secondaryColor: appearance.secondaryColor
                )
            }
            content
        }
        .animation(.default, value: manager.errorMessage)
    }

    /// Picks the credential presentation. macOS only ships the native form, so
    /// the `style` is honored on iOS and ignored on macOS.
    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        nativeContent
        #else
        switch style {
        case .web:
            webContent
        case .native:
            nativeContent
        }
        #endif
    }

    // MARK: - Web Flow (iOS)

    #if os(iOS)
    private var webContent: some View {
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

    // MARK: - Native Form (macOS + iOS)

    private var nativeContent: some View {
        ZStack(alignment: .top) {
            formScrollView

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

    private var formScrollView: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Equal-weight spacers above and below center the brand and
                    // controls as one optical group, while the mode footer stays
                    // pinned to the bottom of the screen.
                    Spacer(minLength: Layout.topInset)

                    GlassEffectContainer(spacing: 20) {
                        VStack(spacing: Layout.cardSpacing) {
                            Group {
                                if let customHeader {
                                    customHeader
                                } else {
                                    compactHeader
                                }
                            }
                            .scaleEffect(isAppearing ? 1 : 0.92)
                            .opacity(isAppearing ? 1 : 0)

                            nativeCredentialForm
                        }
                        .padding(Layout.cardPadding)
                        .frame(
                            minWidth: Layout.cardMinWidth,
                            maxWidth: Layout.cardMaxWidth,
                            alignment: .top
                        )
                    }
                    .offset(y: isAppearing ? 0 : 24)
                    .opacity(isAppearing ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: isAppearing)

                    Spacer(minLength: Layout.topInset)

                    modeFooter
                        .padding(.top, 24)
                        .opacity(isAppearing ? 1 : 0)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, Layout.outerPadding)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.error, trigger: manager.errorMessage) { _, new in new != nil }
        #endif
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isAppearing = true
            }
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

    private var compactHeader: some View {
        VStack(spacing: 20) {
            compactIcon
                .glassEffectID("header-icon", in: glassNamespace)

            VStack(spacing: 7) {
                headerTitle
                    .font(HeaderMetrics.titleFont)
                    .foregroundStyle(.primary)
                    .contentTransition(.opacity)

                Text(appearance.subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: mode)
        }
    }

    private var headerTitle: Text {
        if let title = currentSchema?.title, !title.isEmpty {
            return Text(title)
        }
        return Text(appearance.title)
    }

    @ViewBuilder
    private var compactIcon: some View {
        let side = HeaderMetrics.iconSide

        switch appearance.icon {
        // A bare symbol reads as a mark; wrapping it in a tinted tile just
        // imitates an app icon badly, so only real images get a container.
        case .systemImage(let name):
            Image(systemName: name)
                .font(.system(size: side * 0.78, weight: .medium))
                .foregroundStyle(appearance.accentColor.gradient)
                .frame(height: side)
                .shadow(color: appearance.accentColor.opacity(0.35), radius: 24, y: 8)
        case .image(let image):
            image
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
        case .assetImage(let name, let bundle):
            Image(name, bundle: bundle)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
        case .none:
            EmptyView()
        }
    }

    private var currentSchema: AuthUISchema? {
        mode == .signIn ? manager.signInSchema : manager.signUpSchema
    }

    private var nativeCredentialForm: some View {
        VStack(spacing: 0) {
            if let schema = currentSchema {
                ZStack(alignment: .top) {
                    if stage == .methodPicker {
                        methodPickerStage(schema)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    if stage == .credentials {
                        credentialsStage(schema)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            } else if manager.isLoadingSchema || !hasAttemptedSchemaLoad {
                ProgressView()
                    .padding(.vertical, 56)
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

    // MARK: - Stage 1: pick a method

    /// The landing stage: branding plus the ways in, with no form. Methods that
    /// need typed input hand off to `credentialsStage`; the rest fire straight
    /// away, so passkey sign-in never shows a form it doesn't use.
    private func methodPickerStage(_ schema: AuthUISchema) -> some View {
        let prominentMethods = schema.supportedMethods.filter(\.primary)
        let alternativeMethods = schema.supportedMethods.filter { !$0.primary }

        return VStack(spacing: 0) {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 10) {
                    ForEach(prominentMethods) { method in
                        methodButton(method, schema: schema)
                            .glassEffectTransition(.materialize)
                    }

                    if !alternativeMethods.isEmpty {
                        if !prominentMethods.isEmpty {
                            orDivider
                                .padding(.vertical, 6)
                        }

                        ForEach(alternativeMethods) { method in
                            methodButton(method, schema: schema)
                                .glassEffectTransition(.materialize)
                        }
                    }
                }
            }

            linkRow(schema)
                .padding(.top, 20)
        }
    }

    // MARK: - Stage 2: collect credentials for the chosen method

    private func credentialsStage(_ schema: AuthUISchema) -> some View {
        let fields = visibleFields(schema)

        return VStack(spacing: 0) {
            backToMethodsButton
                .padding(.bottom, 18)

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 10) {
                    ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                        renderField(field, isLast: index == fields.count - 1)
                    }
                }
            }

            // Sits tight under the password row it belongs to, rather than
            // floating midway between the form and the button.
            // The gap below has to live on the button: when the schema carries
            // no links this row collapses to an EmptyView, and padding on that
            // collapses with it.
            linkRow(schema, alignment: .trailing)
                .padding(.top, 12)

            if let pendingMethod {
                AuthMethodButton(
                    method: pendingMethod,
                    accentColor: appearance.accentColor,
                    isBusy: manager.isAuthenticating,
                    isRunning: manager.isAuthenticating && activeMethod == pendingMethod.id,
                    namespace: glassNamespace,
                    prominent: true,
                    showsSymbol: false,
                    glassIDSuffix: "-submit"
                ) {
                    run(pendingMethod, schema: schema)
                }
                .padding(.top, 24)
            }
        }
        .onAppear {
            focusedField = fields.first?.key
        }
    }

    private var backToMethodsButton: some View {
        Button {
            focusedField = nil
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                stage = .methodPicker
                pendingMethod = nil
                fieldErrors = [:]
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text(mode == .signIn ? "All sign-in options" : "All sign-up options")
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(appearance.accentColor)
            .contentShape(.rect)
        }
        .buttonStyle(.pressScale(0.98))
        .disabled(manager.isAuthenticating)
        .accessibilityIdentifier("back-to-methods-button")
    }

    // MARK: - Method routing

    /// Fields the chosen method actually needs. Passkey flows never collect a
    /// password, so those rows are dropped rather than shown and ignored.
    private func fields(
        for method: AuthUISchema.SupportedMethod?,
        in schema: AuthUISchema
    ) -> [AuthUISchema.Field] {
        guard let method else { return schema.fields }
        switch method.id {
        case .password:
            return schema.fields
        case .passkey, .passkeyAccountCreation:
            return schema.fields.filter { !$0.isPassword }
        }
    }

    private func visibleFields(_ schema: AuthUISchema) -> [AuthUISchema.Field] {
        fields(for: pendingMethod, in: schema)
    }

    /// Passkey *sign-in* identifies the user by itself, and system account
    /// creation collects everything in the OS sheet — only flows that still
    /// need typed input open the form.
    private func requiresCredentials(
        _ method: AuthUISchema.SupportedMethod,
        schema: AuthUISchema
    ) -> Bool {
        guard !fields(for: method, in: schema).isEmpty else { return false }
        switch method.id {
        case .password: return true
        case .passkey: return mode == .signUp
        case .passkeyAccountCreation: return false
        }
    }

    private func select(_ method: AuthUISchema.SupportedMethod, schema: AuthUISchema) {
        focusedField = nil
        guard requiresCredentials(method, schema: schema) else {
            run(method, schema: schema)
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            pendingMethod = method
            stage = .credentials
            fieldErrors = [:]
        }
    }

    private func run(_ method: AuthUISchema.SupportedMethod, schema: AuthUISchema) {
        focusedField = nil
        switch method.id {
        case .password:
            submitPrimary(schema: schema)
        case .passkey:
            submitPasskeyAction()
        case .passkeyAccountCreation:
            submitPasskeyAccountCreationAction()
        }
    }

    /// Renders schema-provided links (e.g. "Forgot password?"). Relative hrefs
    /// are skipped — the view has no base URL to resolve them against.
    @ViewBuilder
    private func linkRow(
        _ schema: AuthUISchema,
        alignment: HorizontalAlignment = .center
    ) -> some View {
        let usable = (schema.links ?? []).compactMap { link -> (AuthUISchema.Link, URL)? in
            guard let url = URL(string: link.href), url.scheme != nil else { return nil }
            return (link, url)
        }

        if !usable.isEmpty {
            HStack(spacing: 18) {
                if alignment != .leading { Spacer(minLength: 0) }
                ForEach(usable, id: \.0.id) { link, url in
                    Link(link.label, destination: url)
                        .font(.system(size: 14))
                        .tint(appearance.accentColor)
                }
                if alignment != .trailing { Spacer(minLength: 0) }
            }
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

    private func renderField(_ field: AuthUISchema.Field, isLast: Bool) -> some View {
        AuthCredentialField(
            field: field,
            text: Binding<String>(
                get: { fieldValues[field.key] ?? "" },
                set: { newValue in
                    fieldValues[field.key] = newValue
                    fieldErrors[field.key] = nil
                }
            ),
            error: fieldErrors[field.key],
            accentColor: appearance.accentColor,
            isSignUp: mode == .signUp,
            isLast: isLast,
            namespace: glassNamespace,
            focusedField: $focusedField,
            onSubmit: { advanceFocus(from: field.key) }
        )
    }

    private func methodButton(_ method: AuthUISchema.SupportedMethod, schema: AuthUISchema) -> some View {
        AuthMethodButton(
            method: method,
            accentColor: appearance.accentColor,
            isBusy: manager.isAuthenticating,
            isRunning: manager.isAuthenticating && activeMethod == method.id,
            namespace: glassNamespace
        ) {
            select(method, schema: schema)
        }
    }

    /// Switching between sign-in and sign-up reads as fine print at the bottom
    /// rather than a second tinted control competing with the call to action.
    private var modeFooter: some View {
        HStack(spacing: 5) {
            Text(mode == .signIn ? "Don't have an account?" : "Already have an account?")
                .foregroundStyle(.secondary)

            Button {
                focusedField = nil
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    mode = mode == .signIn ? .signUp : .signIn
                    stage = .methodPicker
                    pendingMethod = nil
                    fieldErrors = [:]
                }
            } label: {
                Text(mode == .signIn ? "Sign Up" : "Sign In")
                    .fontWeight(.semibold)
                    .foregroundStyle(appearance.accentColor)
                    .contentShape(.rect)
            }
            .buttonStyle(.pressScale(0.96))
            .disabled(manager.isAuthenticating)
            .accessibilityIdentifier("auth-mode-picker")
        }
        .font(.system(size: 15))
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.primary.opacity(0.1))
                .frame(height: 0.5)
            Text("or")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle()
                .fill(.primary.opacity(0.1))
                .frame(height: 0.5)
        }
    }

    private func advanceFocus(from key: String) {
        guard let schema = currentSchema else { return }
        let fields = visibleFields(schema)
        guard let idx = fields.firstIndex(where: { $0.key == key }) else { return }

        let next = idx + 1
        if next < fields.count {
            focusedField = fields[next].key
        } else if let pendingMethod {
            run(pendingMethod, schema: schema)
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
        activeMethod = .password

        Task {
            defer { activeMethod = nil }
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
                            stage = .methodPicker
                            pendingMethod = nil
                            fieldErrors = [:]
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
        activeMethod = .passkey

        Task {
            defer { activeMethod = nil }
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
        activeMethod = .passkeyAccountCreation
        Task {
            defer { activeMethod = nil }
            do {
                try await manager.createAccountWithPasskey()
                onAuthSuccess?()
            } catch {
                onAuthFailed?(error)
            }
        }
    }
}

private enum NativeAuthMode: Hashable {
    case signIn
    case signUp
}

/// The native form is a two-step flow: pick how you want to sign in, then —
/// only for the methods that need it — type credentials.
private enum FormStage: Hashable {
    case methodPicker
    case credentials
}

/// Layout metrics for the native form. iOS goes edge-to-edge with a wide cap
/// for iPad; macOS keeps the fixed-width panel it was designed around.
private enum Layout {
    #if os(iOS)
    static let outerPadding: CGFloat = 24
    static let cardPadding: CGFloat = 0
    static let cardSpacing: CGFloat = 40
    static let cardMinWidth: CGFloat? = nil
    static let cardMaxWidth: CGFloat = 400
    static let topInset: CGFloat = 24
    #else
    static let outerPadding: CGFloat = 32
    static let cardPadding: CGFloat = 24
    static let cardSpacing: CGFloat = 32
    static let cardMinWidth: CGFloat? = 340
    static let cardMaxWidth: CGFloat = 380
    static let topInset: CGFloat = 28
    #endif
}

private enum HeaderMetrics {
    #if os(iOS)
    static let iconSide: CGFloat = 64
    static let titleFont: Font = .system(size: 28, weight: .bold)
    #else
    static let iconSide: CGFloat = 52
    static let titleFont: Font = .system(size: 22, weight: .semibold)
    #endif
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
    private let style: RxSignInStyle
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

    init(style: RxSignInStyle = .native) {
        self.style = style
    }

    var body: some View {
        RxSignInView(manager: manager, style: style)
    }
}

#Preview("Grouped Methods (1 primary + 2 secondary)") {
    GroupedMethodsPreview()
        .preferredColorScheme(.dark)
}

#Preview("iOS Native Form") {
    GroupedMethodsPreview(style: .native)
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
