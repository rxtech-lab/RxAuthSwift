import AuthenticationServices
import Foundation
import Logging
import Observation

@MainActor
@Observable
public final class OAuthManager: Sendable {
    public private(set) var authState: AuthenticationState = .unknown
    public private(set) var currentUser: User?
    public private(set) var errorMessage: String?
    public private(set) var infoMessage: String?
    public private(set) var isAuthenticating = false
    public private(set) var signInSchema: AuthUISchema?
    public private(set) var signUpSchema: AuthUISchema?
    public private(set) var isLoadingSchema = false

    /// True after a password sign-up completes successfully on a server that
    /// supports passkey upgrade. The UI is expected to surface an "Add a
    /// passkey" prompt, then call either `addPasskeyForCurrentUser()` or
    /// `skipPasskeyUpgradeOffer()`. While this flag is set, `authState` is
    /// intentionally held at `.unauthenticated` so the host app keeps the
    /// sign-in surface mounted long enough for the prompt to render.
    public private(set) var pendingPasskeyOffer = false

    /// Clears the current error message
    public func clearError() {
        errorMessage = nil
    }

    /// Clears the current informational message
    public func clearInfo() {
        infoMessage = nil
    }
    public var supportsPasskeyAuthentication: Bool {
        configuration.passkeyChallengeURL != nil && configuration.passkeyVerificationURL != nil
    }
    public var supportsNativeSignup: Bool {
        configuration.nativeSignupURL != nil
    }
    public var supportsPasskeyRegistration: Bool {
        configuration.passkeyRegistrationChallengeURL != nil && configuration.passkeyRegistrationVerificationURL != nil
    }
    public var supportsPasskeyUpgrade: Bool {
        configuration.passkeyUpgradeChallengeURL != nil && configuration.passkeyUpgradeVerificationURL != nil
    }
    public var supportsPasskeyAccountCreation: Bool {
        configuration.passkeyAccountCreationOptionsURL != nil && configuration.passkeyAccountCreationVerifyURL != nil
    }

    private let configuration: RxAuthConfiguration
    private let tokenStorage: TokenStorageProtocol
    private let logger: Logger

    private var refreshTimer: Timer?

    public init(
        configuration: RxAuthConfiguration,
        tokenStorage: TokenStorageProtocol? = nil,
        logger: Logger? = nil
    ) {
        self.configuration = configuration
        self.tokenStorage = tokenStorage ?? KeychainTokenStorage(serviceName: configuration.keychainServiceName)

        var defaultLogger = logger ?? Logger(label: "com.rxlab.RxAuthSwift")
        if logger == nil {
            defaultLogger.logLevel = .info
        }
        self.logger = defaultLogger
    }

    // MARK: - Public API

    public func checkExistingAuth() async {
        if let _ = tokenStorage.getAccessToken(), !tokenStorage.isTokenExpired() {
            do {
                try await fetchUserInfo()
                authState = .authenticated
                startTokenRefreshTimer()
                logger.info("Restored existing authentication session")
            } catch {
                logger.warning("Failed to restore session: \(error.localizedDescription)")
                authState = .unauthenticated
            }
        } else if tokenStorage.getRefreshToken() != nil {
            do {
                try await refreshTokenIfNeeded()
                startTokenRefreshTimer()
                logger.info("Refreshed token from existing session")
            } catch {
                logger.warning("Token refresh failed: \(error.localizedDescription)")
                // Ensure stale tokens are fully cleared so that subsequent
                // calls to checkExistingAuth() don't retry a failed refresh.
                try? tokenStorage.clearAll()
                authState = .unauthenticated
            }
        } else {
            authState = .unauthenticated
        }
    }

    /// Browser-based authorization-code + PKCE sign-in.
    ///
    /// - Parameter additionalAuthorizationParameters: Extra query items for the
    ///   authorize request. Servers use these for hints such as
    ///   `identity_provider`; keys that collide with the standard OAuth
    ///   parameters are ignored so a hint can never break the core flow.
    public func authenticate(
        additionalAuthorizationParameters: [String: String] = [:]
    ) async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let codeVerifier = PKCEHelper.generateCodeVerifier()
            let codeChallenge = PKCEHelper.generateCodeChallenge(from: codeVerifier)

            guard let authorizeURL = buildAuthorizationURL(
                codeChallenge: codeChallenge,
                additionalParameters: additionalAuthorizationParameters
            ) else {
                throw OAuthError.invalidConfiguration
            }

            guard let callbackScheme = configuration.redirectScheme else {
                throw OAuthError.invalidConfiguration
            }

            logger.info("Starting OAuth authentication flow")

            let callbackURL = try await platformAuthenticate(url: authorizeURL, callbackScheme: callbackScheme)
            try await handleCallback(url: callbackURL, codeVerifier: codeVerifier)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Sign in through a third-party identity provider advertised by the
    /// server's UI schema (Google, GitHub, …). Runs the same browser flow as
    /// `authenticate()`, with the provider's `authorizationParameters` attached
    /// so the server skips its own login page and hands off to the provider.
    public func authenticate(identityProvider: AuthUISchema.IdentityProvider) async throws {
        logger.info("Starting identity provider sign-in: \(identityProvider.id)")
        try await authenticate(additionalAuthorizationParameters: identityProvider.authorizationParameters)
    }

    public func authenticate(username: String, password: String) async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            try await exchangePasswordForTokens(username: username, password: password)
            logger.info("Native username/password authentication completed successfully")
            scheduleAutomaticPasskeyUpgrade()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func authenticateWithPasskey(username: String? = nil) async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            try await exchangePasskeyAssertionForTokens(username: username)
            logger.info("Native passkey authentication completed successfully")
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    public func signUp(username: String, password: String, name: String? = nil) async throws -> SignupResult {
        isAuthenticating = true
        errorMessage = nil
        infoMessage = nil
        defer { isAuthenticating = false }

        do {
            let result = try await exchangeSignupForTokens(username: username, password: password, name: name)
            switch result {
            case .authenticated:
                logger.info("Native username/password signup completed successfully")
                if supportsPasskeyUpgrade {
                    // Hold authState so the UI can show the passkey offer
                    // sheet on top of the still-mounted sign-in view.
                    pendingPasskeyOffer = true
                } else {
                    finalizeSignupSession()
                }
            case .emailVerificationRequired(let email):
                infoMessage = "Check \(email) for a verification link, then sign in."
                logger.info("Signup created an unverified account; awaiting email verification: \(email)")
            }
            return result
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func signUpWithPasskey(username: String, name: String? = nil) async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            try await exchangePasskeyRegistrationForTokens(username: username, name: name)
            logger.info("Native passkey signup completed successfully")
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// WWDC 2025 / iOS 26 / macOS 26: drives Apple's system-provided account
    /// creation sheet via `ASAuthorizationAccountCreationProvider`. The user
    /// never fills out a form — the OS pulls email/phone/name from iCloud,
    /// confirms with biometrics, and produces a passkey. The server creates
    /// the account from the returned contact identifier and issues tokens.
    public func createAccountWithPasskey(
        acceptedIdentifiers: [ASContactIdentifierRequest] = [.email],
        shouldRequestName: Bool = true
    ) async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            try await exchangePasskeyAccountCreationForTokens(
                acceptedIdentifiers: acceptedIdentifiers,
                shouldRequestName: shouldRequestName
            )
            logger.info("Native passkey account creation completed successfully")
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// User dismissed the post-signup "add a passkey" offer. Finalises the
    /// session — flips `authState` to `.authenticated` and starts the
    /// refresh timer — without registering a passkey.
    public func skipPasskeyUpgradeOffer() {
        guard pendingPasskeyOffer else { return }
        pendingPasskeyOffer = false
        finalizeSignupSession()
    }

    /// User accepted the post-signup "add a passkey" offer. Runs an
    /// interactive passkey registration ceremony against the upgrade
    /// endpoints (Bearer-authenticated with the just-issued access token),
    /// then finalises the session. Throws if the ceremony or verification
    /// fails — the caller may surface the error and let the user retry or
    /// skip.
    public func addPasskeyForCurrentUser() async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            try await performInteractivePasskeyUpgrade()
            pendingPasskeyOffer = false
            finalizeSignupSession()
            logger.info("Post-signup passkey registration succeeded")
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func logout() async {
        stopTokenRefreshTimer()

        do {
            try tokenStorage.clearAll()
        } catch {
            logger.error("Failed to clear token storage: \(error.localizedDescription)")
            // Attempt to clear individual tokens even if clearAll() fails,
            // so that a partial failure doesn't leave stale tokens behind.
            try? tokenStorage.deleteAccessToken()
            try? tokenStorage.deleteRefreshToken()
        }

        currentUser = nil
        authState = .unauthenticated
        logger.info("User logged out")
    }

    public func refreshTokenIfNeeded() async throws {
        guard let refreshToken = tokenStorage.getRefreshToken() else {
            throw OAuthError.noRefreshToken
        }

        guard let tokenURL = configuration.tokenURL else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = formEncodedBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": configuration.clientID,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenRefreshFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("Token refresh failed with status \(httpResponse.statusCode)")
            await handleTokenRefreshFailure()
            throw OAuthError.tokenRefreshFailed("HTTP \(httpResponse.statusCode)")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        try saveTokens(tokenResponse)
        try await fetchUserInfo()

        authState = .authenticated
        logger.info("Token refreshed successfully")
    }

    // MARK: - Private

    private func platformAuthenticate(url: URL, callbackScheme: String) async throws -> URL {
        #if os(iOS)
        let provider = IOSWebAuthSession()
        return try await provider.authenticate(url: url, callbackURLScheme: callbackScheme)
        #elseif os(macOS)
        let provider = MacOSWebAuthSession()
        return try await provider.authenticate(url: url, callbackURLScheme: callbackScheme)
        #else
        throw OAuthError.authenticationFailed("Unsupported platform")
        #endif
    }

    private func handleCallback(url: URL, codeVerifier: String) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw OAuthError.invalidCallbackURL
        }

        try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws {
        guard let tokenURL = configuration.tokenURL else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = formEncodedBody([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectURI,
            "client_id": configuration.clientID,
            "code_verifier": codeVerifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed("Token exchange returned non-200 status")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        try saveTokens(tokenResponse)
        try await fetchUserInfo()

        authState = .authenticated
        startTokenRefreshTimer()
        logger.info("Authentication completed successfully")
    }

    private func exchangePasswordForTokens(username: String, password: String) async throws {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            throw OAuthError.invalidCredentials
        }

        guard let tokenURL = configuration.nativePasswordTokenURL else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            "grant_type": "password",
            "username": trimmedUsername,
            "password": password,
            "client_id": configuration.clientID,
            "scope": configuration.scopes.joined(separator: " "),
        ])

        let tokenResponse = try await sendTokenRequest(request)
        try saveTokens(tokenResponse)
        try await fetchUserInfo()

        authState = .authenticated
        startTokenRefreshTimer()
    }

    private func exchangeSignupForTokens(username: String, password: String, name: String?) async throws -> SignupResult {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            throw OAuthError.invalidSignupDetails
        }

        guard let signupURL = configuration.nativeSignupURL else {
            throw OAuthError.invalidConfiguration
        }

        var request = URLRequest(url: signupURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SignupRequest(
            clientID: configuration.clientID,
            username: trimmedUsername,
            password: password,
            name: name.nilIfBlank,
            scope: configuration.scopes.joined(separator: " ")
        ))

        switch try await sendSignupRequest(request) {
        case .tokens(let tokenResponse):
            try saveTokens(tokenResponse)
            try await fetchUserInfo()
            // Defer the `.authenticated` transition to the caller so the
            // sign-up flow can interpose a passkey-offer step before the
            // host app swaps away from the sign-in surface.
            return .authenticated
        case .verificationRequired(let email):
            return .emailVerificationRequired(email: email ?? trimmedUsername)
        }
    }

    private func exchangePasskeyAssertionForTokens(username: String?) async throws {
        guard supportsPasskeyAuthentication,
              let challengeURL = configuration.passkeyChallengeURL,
              let verificationURL = configuration.passkeyVerificationURL
        else {
            throw OAuthError.passkeyUnavailable
        }

        var challengeRequest = URLRequest(url: challengeURL)
        challengeRequest.httpMethod = "POST"
        challengeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        challengeRequest.httpBody = try JSONEncoder().encode(PasskeyChallengeRequest(
            clientID: configuration.clientID,
            redirectURI: configuration.redirectURI,
            username: username.nilIfBlank
        ))

        let (challengeData, challengeResponse) = try await URLSession.shared.data(for: challengeRequest)
        guard let httpChallengeResponse = challengeResponse as? HTTPURLResponse,
              httpChallengeResponse.statusCode == 200
        else {
            throw OAuthError.authenticationFailed("Passkey challenge request failed")
        }

        let options = try JSONDecoder().decode(PasskeyChallengeResponse.self, from: challengeData)
        guard let challenge = Base64URL.decode(options.challenge) else {
            throw OAuthError.authenticationFailed("Invalid passkey challenge")
        }

        let relyingPartyIdentifier = options.relyingPartyIdentifier
            ?? configuration.passkeyRelyingPartyIdentifier
            ?? URL(string: configuration.issuer)?.host

        guard let relyingPartyIdentifier else {
            throw OAuthError.passkeyUnavailable
        }

        let allowedCredentialIDs = options.allowedCredentialIDs.compactMap(Base64URL.decode)

        #if os(macOS) || os(iOS)
        let assertion = try await PlatformPasskeyAuthenticator().authenticate(
            relyingPartyIdentifier: relyingPartyIdentifier,
            challenge: challenge,
            allowedCredentialIDs: allowedCredentialIDs
        )

        var verificationRequest = URLRequest(url: verificationURL)
        verificationRequest.httpMethod = "POST"
        verificationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        verificationRequest.httpBody = try JSONEncoder().encode(PasskeyVerificationRequest(
            clientID: configuration.clientID,
            sessionID: options.sessionID,
            scope: configuration.scopes.joined(separator: " "),
            assertion: assertion
        ))

        let tokenResponse = try await sendTokenRequest(verificationRequest)
        try saveTokens(tokenResponse)
        try await fetchUserInfo()

        authState = .authenticated
        startTokenRefreshTimer()
        #else
        throw OAuthError.passkeyUnavailable
        #endif
    }

    private func exchangePasskeyRegistrationForTokens(username: String, name: String?) async throws {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            throw OAuthError.invalidSignupDetails
        }

        guard supportsPasskeyRegistration,
              let challengeURL = configuration.passkeyRegistrationChallengeURL,
              let verificationURL = configuration.passkeyRegistrationVerificationURL
        else {
            throw OAuthError.passkeyUnavailable
        }

        var challengeRequest = URLRequest(url: challengeURL)
        challengeRequest.httpMethod = "POST"
        challengeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        challengeRequest.httpBody = try JSONEncoder().encode(PasskeyRegistrationChallengeRequest(
            clientID: configuration.clientID,
            redirectURI: configuration.redirectURI,
            username: trimmedUsername,
            name: name.nilIfBlank
        ))

        let (challengeData, challengeResponse) = try await URLSession.shared.data(for: challengeRequest)
        guard let httpChallengeResponse = challengeResponse as? HTTPURLResponse,
              httpChallengeResponse.statusCode == 200
        else {
            throw OAuthError.authenticationFailed("Passkey registration challenge request failed")
        }

        let options = try JSONDecoder().decode(PasskeyRegistrationChallengeResponse.self, from: challengeData)
        guard let challenge = Base64URL.decode(options.challenge) else {
            throw OAuthError.authenticationFailed("Invalid passkey registration challenge")
        }

        let relyingPartyIdentifier = options.relyingPartyIdentifier
            ?? configuration.passkeyRelyingPartyIdentifier
            ?? URL(string: configuration.issuer)?.host
        guard let relyingPartyIdentifier else {
            throw OAuthError.passkeyUnavailable
        }

        guard let userID = Base64URL.decode(options.userID) else {
            throw OAuthError.authenticationFailed("Invalid passkey registration user ID")
        }

        #if os(macOS) || os(iOS)
        let registration = try await PlatformPasskeyRegistrationAuthenticator().register(
            relyingPartyIdentifier: relyingPartyIdentifier,
            challenge: challenge,
            name: options.username ?? trimmedUsername,
            userID: userID
        )

        var verificationRequest = URLRequest(url: verificationURL)
        verificationRequest.httpMethod = "POST"
        verificationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        verificationRequest.httpBody = try JSONEncoder().encode(PasskeyRegistrationVerificationRequest(
            clientID: configuration.clientID,
            sessionID: options.sessionID,
            scope: configuration.scopes.joined(separator: " "),
            registration: registration
        ))

        let tokenResponse = try await sendTokenRequest(verificationRequest)
        try saveTokens(tokenResponse)
        try await fetchUserInfo()

        authState = .authenticated
        startTokenRefreshTimer()
        #else
        throw OAuthError.passkeyUnavailable
        #endif
    }

    // MARK: - System-Sheet Account Creation (WWDC iOS 26 / macOS 26)

    private func exchangePasskeyAccountCreationForTokens(
        acceptedIdentifiers: [ASContactIdentifierRequest],
        shouldRequestName: Bool
    ) async throws {
        guard supportsPasskeyAccountCreation,
              let optionsURL = configuration.passkeyAccountCreationOptionsURL,
              let verifyURL = configuration.passkeyAccountCreationVerifyURL
        else {
            throw OAuthError.passkeyUnavailable
        }

        var optionsRequest = URLRequest(url: optionsURL)
        optionsRequest.httpMethod = "POST"
        optionsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        optionsRequest.httpBody = try JSONEncoder().encode(PasskeyAccountCreationOptionsRequest(
            clientID: configuration.clientID,
            redirectURI: configuration.redirectURI
        ))

        let (optionsData, optionsResponse) = try await URLSession.shared.data(for: optionsRequest)
        guard let httpOptionsResponse = optionsResponse as? HTTPURLResponse,
              (200...299).contains(httpOptionsResponse.statusCode)
        else {
            let status = (optionsResponse as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: optionsData, encoding: .utf8) ?? ""
            logger.error("Passkey account-creation options failed: HTTP \(status) \(body)")
            throw OAuthError.authenticationFailed("Passkey account-creation challenge failed")
        }

        // Same SimpleWebAuthn-spread JSON shape as the upgrade route; decode
        // with the existing tolerant decoder, ignoring username/displayName
        // (the OS sheet supplies those).
        let options = try JSONDecoder().decode(PasskeyRegistrationChallengeResponse.self, from: optionsData)
        guard let challenge = Base64URL.decode(options.challenge) else {
            throw OAuthError.authenticationFailed("Invalid challenge")
        }
        guard let userID = Base64URL.decode(options.userID) else {
            throw OAuthError.authenticationFailed("Invalid user ID")
        }
        let relyingPartyIdentifier = options.relyingPartyIdentifier
            ?? configuration.passkeyRelyingPartyIdentifier
            ?? URL(string: configuration.issuer)?.host
        guard let relyingPartyIdentifier else {
            throw OAuthError.passkeyUnavailable
        }

        #if os(macOS) || os(iOS)
        let creation = try await PlatformPasskeyAccountCreationAuthenticator().createAccount(
            relyingPartyIdentifier: relyingPartyIdentifier,
            challenge: challenge,
            userID: userID,
            acceptedIdentifiers: acceptedIdentifiers,
            shouldRequestName: shouldRequestName
        )

        var verifyRequest = URLRequest(url: verifyURL)
        verifyRequest.httpMethod = "POST"
        verifyRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        verifyRequest.httpBody = try JSONEncoder().encode(PasskeyAccountCreationVerifyRequest(
            clientID: configuration.clientID,
            sessionID: options.sessionID,
            scope: configuration.scopes.joined(separator: " "),
            contactIdentifier: creation.contactIdentifier.value,
            contactIdentifierType: creation.contactIdentifier.serverTypeString,
            name: Self.formattedName(creation.name),
            creation: creation
        ))

        let tokenResponse = try await sendTokenRequest(verifyRequest)
        try saveTokens(tokenResponse)
        try await fetchUserInfo()

        authState = .authenticated
        startTokenRefreshTimer()
        #else
        throw OAuthError.passkeyUnavailable
        #endif
    }

    private static func formattedName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .long
        let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    private func finalizeSignupSession() {
        authState = .authenticated
        startTokenRefreshTimer()
    }

    /// Interactive variant of the upgrade ceremony used by the post-signup
    /// offer sheet. Unlike `attemptAutomaticPasskeyUpgrade`, this surfaces
    /// the system passkey UI (`MacOSPasskeyRegistrationAuthenticator`) and
    /// propagates errors so the UI can react.
    private func performInteractivePasskeyUpgrade() async throws {
        #if os(macOS) || os(iOS)
        guard supportsPasskeyUpgrade,
              let challengeURL = configuration.passkeyUpgradeChallengeURL,
              let verificationURL = configuration.passkeyUpgradeVerificationURL
        else {
            throw OAuthError.passkeyUnavailable
        }
        guard let accessToken = tokenStorage.getAccessToken() else {
            throw OAuthError.passkeyUnavailable
        }

        var challengeRequest = URLRequest(url: challengeURL)
        challengeRequest.httpMethod = "POST"
        challengeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        challengeRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        challengeRequest.httpBody = "{}".data(using: .utf8)

        let (challengeData, challengeResponse) = try await URLSession.shared.data(for: challengeRequest)
        guard let httpChallengeResponse = challengeResponse as? HTTPURLResponse,
              (200...299).contains(httpChallengeResponse.statusCode)
        else {
            let status = (challengeResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw OAuthError.authenticationFailed("Passkey upgrade challenge failed (HTTP \(status))")
        }

        let options = try JSONDecoder().decode(PasskeyRegistrationChallengeResponse.self, from: challengeData)
        guard let challenge = Base64URL.decode(options.challenge) else {
            throw OAuthError.authenticationFailed("Invalid passkey upgrade challenge")
        }
        guard let userID = Base64URL.decode(options.userID) else {
            throw OAuthError.authenticationFailed("Invalid passkey upgrade user ID")
        }
        let relyingPartyIdentifier = options.relyingPartyIdentifier
            ?? configuration.passkeyRelyingPartyIdentifier
            ?? URL(string: configuration.issuer)?.host
        guard let relyingPartyIdentifier else {
            throw OAuthError.passkeyUnavailable
        }

        let displayName = options.username ?? currentUser?.email ?? currentUser?.name ?? "Account"

        let registration = try await PlatformPasskeyRegistrationAuthenticator().register(
            relyingPartyIdentifier: relyingPartyIdentifier,
            challenge: challenge,
            name: displayName,
            userID: userID
        )

        var verificationRequest = URLRequest(url: verificationURL)
        verificationRequest.httpMethod = "POST"
        verificationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        verificationRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        verificationRequest.httpBody = try JSONEncoder().encode(PasskeyUpgradeVerificationRequest(
            sessionID: options.sessionID,
            name: displayName,
            registration: registration
        ))

        let (verifyData, verifyResponse) = try await URLSession.shared.data(for: verificationRequest)
        guard let httpVerifyResponse = verifyResponse as? HTTPURLResponse,
              (200...299).contains(httpVerifyResponse.statusCode)
        else {
            let status = (verifyResponse as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: verifyData, encoding: .utf8) ?? ""
            throw OAuthError.authenticationFailed("Passkey upgrade verification failed (HTTP \(status)): \(body)")
        }
        #else
        throw OAuthError.passkeyUnavailable
        #endif
    }

    // MARK: - Automatic Passkey Upgrade (WWDC iOS 18 / macOS 15)

    /// Fire-and-forget: after a successful password sign-in or sign-up, ask the
    /// OS to silently provision a passkey for the just-authenticated account so
    /// the next sign-in can be passwordless. Errors are swallowed by design;
    /// the user never sees an upgrade-related prompt or error.
    private func scheduleAutomaticPasskeyUpgrade() {
        guard supportsPasskeyUpgrade else { return }
        Task { [weak self] in
            await self?.attemptAutomaticPasskeyUpgrade()
        }
    }

    private func attemptAutomaticPasskeyUpgrade() async {
        #if os(macOS) || os(iOS)
        guard supportsPasskeyUpgrade,
              let challengeURL = configuration.passkeyUpgradeChallengeURL,
              let verificationURL = configuration.passkeyUpgradeVerificationURL
        else { return }

        guard let accessToken = tokenStorage.getAccessToken() else {
            logger.debug("Automatic passkey upgrade skipped: no access token")
            return
        }

        do {
            var challengeRequest = URLRequest(url: challengeURL)
            challengeRequest.httpMethod = "POST"
            challengeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            challengeRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            challengeRequest.httpBody = "{}".data(using: .utf8)

            let (challengeData, challengeResponse) = try await URLSession.shared.data(for: challengeRequest)
            guard let httpChallengeResponse = challengeResponse as? HTTPURLResponse,
                  (200...299).contains(httpChallengeResponse.statusCode)
            else {
                let status = (challengeResponse as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("Automatic passkey upgrade skipped: challenge HTTP \(status)")
                return
            }

            let options = try JSONDecoder().decode(PasskeyRegistrationChallengeResponse.self, from: challengeData)
            guard let challenge = Base64URL.decode(options.challenge) else {
                logger.info("Automatic passkey upgrade skipped: invalid challenge")
                return
            }
            guard let userID = Base64URL.decode(options.userID) else {
                logger.info("Automatic passkey upgrade skipped: invalid user ID")
                return
            }
            let relyingPartyIdentifier = options.relyingPartyIdentifier
                ?? configuration.passkeyRelyingPartyIdentifier
                ?? URL(string: configuration.issuer)?.host
            guard let relyingPartyIdentifier else {
                logger.info("Automatic passkey upgrade skipped: missing RP identifier")
                return
            }

            let displayName = options.username ?? currentUser?.email ?? currentUser?.name ?? "Account"

            guard let registration = await PlatformPasskeyConditionalUpgradeAuthenticator().upgrade(
                relyingPartyIdentifier: relyingPartyIdentifier,
                challenge: challenge,
                name: displayName,
                userID: userID
            ) else {
                logger.info("Automatic passkey upgrade skipped: OS declined or no candidates")
                return
            }

            var verificationRequest = URLRequest(url: verificationURL)
            verificationRequest.httpMethod = "POST"
            verificationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            verificationRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            verificationRequest.httpBody = try JSONEncoder().encode(PasskeyUpgradeVerificationRequest(
                sessionID: options.sessionID,
                name: displayName,
                registration: registration
            ))

            let (verifyData, verifyResponse) = try await URLSession.shared.data(for: verificationRequest)
            guard let httpVerifyResponse = verifyResponse as? HTTPURLResponse,
                  (200...299).contains(httpVerifyResponse.statusCode)
            else {
                let status = (verifyResponse as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: verifyData, encoding: .utf8) ?? ""
                logger.info("Automatic passkey upgrade failed at verify: HTTP \(status) \(body)")
                return
            }

            logger.info("Automatic passkey upgrade succeeded")
        } catch {
            logger.info("Automatic passkey upgrade skipped: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - UI Schema

    /// Fetch the server-driven UI schema for both flows. Stores results on the
    /// manager so SwiftUI views can render fields, validation, and supported
    /// auth methods dynamically.
    @discardableResult
    public func loadUISchema() async -> (signIn: AuthUISchema?, signUp: AuthUISchema?) {
        isLoadingSchema = true
        defer { isLoadingSchema = false }

        async let signIn = fetchUISchema(flow: .signin)
        async let signUp = fetchUISchema(flow: .signup)

        let resolved = await (signIn, signUp)
        if let schema = resolved.0 { signInSchema = schema }
        if let schema = resolved.1 { signUpSchema = schema }
        return (resolved.0, resolved.1)
    }

    public func fetchUISchema(flow: AuthUISchema.Flow) async -> AuthUISchema? {
        guard let url = configuration.uiSchemaURL(flow: flow) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.warning("UI schema fetch (\(flow.rawValue)) returned HTTP \(status)")
                return nil
            }
            return try JSONDecoder().decode(AuthUISchema.self, from: data)
        } catch {
            logger.warning("UI schema fetch (\(flow.rawValue)) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchUserInfo() async throws {
        guard let accessToken = tokenStorage.getAccessToken(),
              let userInfoURL = configuration.userInfoURL
        else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.userInfoFailed("Failed to fetch user info")
        }

        currentUser = try JSONDecoder().decode(User.self, from: data)
    }

    private func saveTokens(_ tokenResponse: TokenResponse) throws {
        try tokenStorage.saveAccessToken(tokenResponse.accessToken)

        if let refreshToken = tokenResponse.refreshToken {
            try tokenStorage.saveRefreshToken(refreshToken)
        }

        if let expiresIn = tokenResponse.expiresIn {
            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            try tokenStorage.saveExpiresAt(expiresAt)
        }
    }

    private func sendSignupRequest(_ request: URLRequest) async throws -> SignupServerResponse {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Invalid response")
        }

        let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"

        guard (200...299).contains(httpResponse.statusCode) else {
            let url = request.url?.absoluteString ?? "<unknown URL>"
            logger.error("Signup request failed: POST \(url) -> HTTP \(httpResponse.statusCode); body: \(bodyString)")

            if let parsed = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                throw OAuthError.tokenExchangeFailed(parsed.userFacingMessage)
            }
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode)")
        }

        // Signup may return either an OAuth token payload (E2E mode) or a
        // verification-required payload (default mode). Try the verification
        // shape first because it omits `access_token`, so a TokenResponse
        // decode would succeed for token payloads but fail for verification
        // ones.
        if let pending = try? JSONDecoder().decode(SignupPendingVerificationResponse.self, from: data),
           pending.emailVerificationRequired == true
        {
            return .verificationRequired(email: pending.email)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return .tokens(tokenResponse)
    }

    private func sendTokenRequest(_ request: URLRequest) async throws -> TokenResponse {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
            let url = request.url?.absoluteString ?? "<unknown URL>"
            logger.error("Token request failed: \(request.httpMethod ?? "?") \(url) -> HTTP \(httpResponse.statusCode); body: \(bodyString)")

            if let parsed = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                throw OAuthError.tokenExchangeFailed(parsed.userFacingMessage)
            }
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func formEncodedBody(_ values: [String: String]) -> Data? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return values
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    func buildAuthorizationURL(
        codeChallenge: String,
        additionalParameters: [String: String] = [:]
    ) -> URL? {
        guard var components = URLComponents(string: configuration.issuer + configuration.authorizePath) else {
            return nil
        }

        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let reserved = Set(queryItems.map(\.name))
        for (name, value) in additionalParameters.sorted(by: { $0.key < $1.key })
        where !reserved.contains(name) {
            queryItems.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = queryItems

        return components.url
    }

    // MARK: - Token Refresh Timer

    private func startTokenRefreshTimer() {
        stopTokenRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.refreshTokenIfNeeded()
                } catch {
                    self.logger.warning("Automatic token refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopTokenRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func handleTokenRefreshFailure() async {
        await logout()
        NotificationCenter.default.post(name: .rxAuthSessionExpired, object: nil)
    }
}

// MARK: - Token Response

private struct OAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    var userFacingMessage: String {
        if let description = errorDescription, !description.isEmpty {
            return description
        }
        if let error, !error.isEmpty {
            return error.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return "Authentication failed"
    }
}

// MARK: - Signup Result

public enum SignupResult: Sendable, Equatable {
    /// Server returned tokens and the user is now signed in.
    case authenticated
    /// Account was created but the server requires email verification before
    /// tokens will be issued. `email` is the address the verification link was
    /// sent to (mirrors what the user typed when the server did not echo one).
    case emailVerificationRequired(email: String)
}

private enum SignupServerResponse {
    case tokens(TokenResponse)
    case verificationRequired(email: String?)
}

private struct SignupPendingVerificationResponse: Decodable {
    let userID: String?
    let email: String?
    let emailVerificationRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case emailVerificationRequired = "email_verification_required"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

private struct PasskeyChallengeRequest: Encodable {
    let clientID: String
    let redirectURI: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
        case username
    }
}

private struct SignupRequest: Encodable {
    let clientID: String
    let username: String
    let password: String
    let name: String?
    let scope: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case username
        case password
        case name
        case scope
    }
}

private struct PasskeyChallengeResponse: Decodable {
    let challenge: String
    let sessionID: String?
    let relyingPartyIdentifier: String?
    let allowedCredentialIDs: [String]

    enum CodingKeys: String, CodingKey {
        case challenge
        case sessionID
        case sessionId
        case requestID
        case requestId
        case relyingPartyIdentifier
        case relyingPartyId
        case rpId
        case allowedCredentialIDs
        case allowedCredentials
        case allowCredentials
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        challenge = try container.decode(String.self, forKey: .challenge)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            ?? container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .requestID)
            ?? container.decodeIfPresent(String.self, forKey: .requestId)
        relyingPartyIdentifier = try container.decodeIfPresent(String.self, forKey: .relyingPartyIdentifier)
            ?? container.decodeIfPresent(String.self, forKey: .relyingPartyId)
            ?? container.decodeIfPresent(String.self, forKey: .rpId)

        if let ids = try container.decodeIfPresent([String].self, forKey: .allowedCredentialIDs) {
            allowedCredentialIDs = ids
        } else if let credentials = try container.decodeIfPresent([AllowedCredential].self, forKey: .allowedCredentials) {
            allowedCredentialIDs = credentials.map(\.id)
        } else if let credentials = try container.decodeIfPresent([AllowedCredential].self, forKey: .allowCredentials) {
            allowedCredentialIDs = credentials.map(\.id)
        } else {
            allowedCredentialIDs = []
        }
    }

    private struct AllowedCredential: Decodable {
        let id: String
    }
}

private struct PasskeyRegistrationChallengeRequest: Encodable {
    let clientID: String
    let redirectURI: String
    let username: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
        case username
        case name
    }
}

private struct PasskeyRegistrationChallengeResponse: Decodable {
    let challenge: String
    let userID: String
    let username: String?
    let sessionID: String?
    let relyingPartyIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case challenge
        case userID
        case userId
        case user
        case username
        case userName
        case sessionID
        case sessionId
        case requestID
        case requestId
        case relyingPartyIdentifier
        case relyingPartyId
        case rpId
        case rp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        challenge = try container.decode(String.self, forKey: .challenge)

        if let flatUserID = try container.decodeIfPresent(String.self, forKey: .userID)
            ?? container.decodeIfPresent(String.self, forKey: .userId)
        {
            userID = flatUserID
            username = try container.decodeIfPresent(String.self, forKey: .username)
                ?? container.decodeIfPresent(String.self, forKey: .userName)
        } else if let user = try container.decodeIfPresent(NestedUser.self, forKey: .user) {
            userID = user.id
            username = user.name ?? user.displayName
        } else {
            userID = try container.decode(String.self, forKey: .userID)
            username = nil
        }

        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            ?? container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .requestID)
            ?? container.decodeIfPresent(String.self, forKey: .requestId)

        if let rpID = try container.decodeIfPresent(String.self, forKey: .relyingPartyIdentifier)
            ?? container.decodeIfPresent(String.self, forKey: .relyingPartyId)
            ?? container.decodeIfPresent(String.self, forKey: .rpId)
        {
            relyingPartyIdentifier = rpID
        } else if let rp = try container.decodeIfPresent(NestedRP.self, forKey: .rp) {
            relyingPartyIdentifier = rp.id
        } else {
            relyingPartyIdentifier = nil
        }
    }

    private struct NestedUser: Decodable {
        let id: String
        let name: String?
        let displayName: String?
    }

    private struct NestedRP: Decodable {
        let id: String
    }
}

private struct PasskeyVerificationRequest: Encodable {
    let clientID: String
    let sessionID: String?
    let scope: String?
    let credential: Credential

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case sessionID = "session_id"
        case scope
        case credential
    }

    struct Credential: Encodable {
        let id: String
        let rawID: String
        let type: String
        let response: Response
        let clientExtensionResults: [String: String]

        enum CodingKeys: String, CodingKey {
            case id
            case rawID = "rawId"
            case type
            case response
            case clientExtensionResults
        }

        struct Response: Encodable {
            let clientDataJSON: String
            let authenticatorData: String
            let signature: String
            let userHandle: String
        }
    }
}

private struct PasskeyRegistrationVerificationRequest: Encodable {
    let clientID: String
    let sessionID: String?
    let scope: String?
    let credential: Credential

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case sessionID = "session_id"
        case scope
        case credential
    }

    struct Credential: Encodable {
        let id: String
        let rawID: String
        let type: String
        let response: Response

        enum CodingKeys: String, CodingKey {
            case id
            case rawID = "rawId"
            case type
            case response
        }

        struct Response: Encodable {
            let clientDataJSON: String
            let attestationObject: String?
        }
    }
}

private struct PasskeyAccountCreationOptionsRequest: Encodable {
    let clientID: String
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
    }
}

private struct PasskeyAccountCreationVerifyRequest: Encodable {
    let clientID: String
    let sessionID: String?
    let scope: String?
    let contactIdentifier: String
    let contactIdentifierType: String
    let name: String?
    let credential: PasskeyRegistrationVerificationRequest.Credential

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case sessionID = "session_id"
        case scope
        case contactIdentifier = "contact_identifier"
        case contactIdentifierType = "contact_identifier_type"
        case name
        case credential
    }
}

#if os(macOS) || os(iOS)
private extension PasskeyAccountCreationVerifyRequest {
    init(
        clientID: String,
        sessionID: String?,
        scope: String?,
        contactIdentifier: String,
        contactIdentifierType: String,
        name: String?,
        creation: PasskeyAccountCreation
    ) {
        let credentialID = Base64URL.encode(creation.credentialID)
        self.init(
            clientID: clientID,
            sessionID: sessionID,
            scope: scope.nilIfBlank,
            contactIdentifier: contactIdentifier,
            contactIdentifierType: contactIdentifierType,
            name: name.nilIfBlank,
            credential: PasskeyRegistrationVerificationRequest.Credential(
                id: credentialID,
                rawID: credentialID,
                type: "public-key",
                response: PasskeyRegistrationVerificationRequest.Credential.Response(
                    clientDataJSON: Base64URL.encode(creation.rawClientDataJSON),
                    attestationObject: creation.rawAttestationObject.map(Base64URL.encode)
                )
            )
        )
    }
}
#endif

private struct PasskeyUpgradeVerificationRequest: Encodable {
    let sessionID: String?
    let name: String?
    let credential: PasskeyRegistrationVerificationRequest.Credential

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case name
        case credential
    }
}

#if os(macOS) || os(iOS)
private extension PasskeyUpgradeVerificationRequest {
    init(sessionID: String?, name: String?, registration: PasskeyRegistration) {
        let credentialID = Base64URL.encode(registration.credentialID)
        self.init(
            sessionID: sessionID,
            name: name.nilIfBlank,
            credential: PasskeyRegistrationVerificationRequest.Credential(
                id: credentialID,
                rawID: credentialID,
                type: "public-key",
                response: PasskeyRegistrationVerificationRequest.Credential.Response(
                    clientDataJSON: Base64URL.encode(registration.rawClientDataJSON),
                    attestationObject: registration.rawAttestationObject.map(Base64URL.encode)
                )
            )
        )
    }
}

private extension PasskeyVerificationRequest {
    init(clientID: String, sessionID: String?, scope: String?, assertion: PasskeyAssertion) {
        let credentialID = Base64URL.encode(assertion.credentialID)
        self.init(
            clientID: clientID,
            sessionID: sessionID,
            scope: scope.nilIfBlank,
            credential: Credential(
                id: credentialID,
                rawID: credentialID,
                type: "public-key",
                response: Credential.Response(
                    clientDataJSON: Base64URL.encode(assertion.rawClientDataJSON),
                    authenticatorData: Base64URL.encode(assertion.rawAuthenticatorData),
                    signature: Base64URL.encode(assertion.signature),
                    userHandle: Base64URL.encode(assertion.userID)
                ),
                clientExtensionResults: [:]
            )
        )
    }
}

private extension PasskeyRegistrationVerificationRequest {
    init(clientID: String, sessionID: String?, scope: String?, registration: PasskeyRegistration) {
        let credentialID = Base64URL.encode(registration.credentialID)
        self.init(
            clientID: clientID,
            sessionID: sessionID,
            scope: scope.nilIfBlank,
            credential: Credential(
                id: credentialID,
                rawID: credentialID,
                type: "public-key",
                response: Credential.Response(
                    clientDataJSON: Base64URL.encode(registration.rawClientDataJSON),
                    attestationObject: registration.rawAttestationObject.map(Base64URL.encode)
                )
            )
        )
    }
}
#endif

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

#if DEBUG
public extension OAuthManager {
    /// Preview-only: inject pre-baked schemas so SwiftUI previews can render
    /// the native form without hitting the network.
    func _previewInject(signIn: AuthUISchema?, signUp: AuthUISchema?) {
        signInSchema = signIn
        signUpSchema = signUp
    }
}
#endif
