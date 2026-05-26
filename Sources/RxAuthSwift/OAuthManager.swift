import Foundation
import Logging
import Observation

@MainActor
@Observable
public final class OAuthManager: Sendable {
    public private(set) var authState: AuthenticationState = .unknown
    public private(set) var currentUser: User?
    public private(set) var errorMessage: String?
    public private(set) var isAuthenticating = false

    /// Clears the current error message
    public func clearError() {
        errorMessage = nil
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

    public func authenticate() async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let codeVerifier = PKCEHelper.generateCodeVerifier()
            let codeChallenge = PKCEHelper.generateCodeChallenge(from: codeVerifier)

            guard let authorizeURL = buildAuthorizationURL(codeChallenge: codeChallenge) else {
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

    public func authenticate(username: String, password: String) async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            try await exchangePasswordForTokens(username: username, password: password)
            logger.info("Native username/password authentication completed successfully")
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

    public func signUp(username: String, password: String, name: String? = nil) async throws {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            try await exchangeSignupForTokens(username: username, password: password, name: name)
            logger.info("Native username/password signup completed successfully")
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

    private func exchangeSignupForTokens(username: String, password: String, name: String?) async throws {
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

        let tokenResponse = try await sendTokenRequest(request)
        try saveTokens(tokenResponse)
        try await fetchUserInfo()

        authState = .authenticated
        startTokenRefreshTimer()
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

        #if os(macOS)
        let assertion = try await MacOSPasskeyAuthenticator().authenticate(
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

        #if os(macOS)
        let registration = try await MacOSPasskeyRegistrationAuthenticator().register(
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

    private func sendTokenRequest(_ request: URLRequest) async throws -> TokenResponse {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
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

    private func buildAuthorizationURL(codeChallenge: String) -> URL? {
        guard var components = URLComponents(string: configuration.issuer + configuration.authorizePath) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

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
    let username: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
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
    let username: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
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

#if os(macOS)
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
