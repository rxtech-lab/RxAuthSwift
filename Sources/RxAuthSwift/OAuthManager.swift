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
                logger.info("Refreshed token from existing session")
            } catch {
                logger.warning("Token refresh failed: \(error.localizedDescription)")
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
    }

    public func logout() async {
        stopTokenRefreshTimer()

        do {
            try tokenStorage.clearAll()
        } catch {
            logger.error("Failed to clear token storage: \(error.localizedDescription)")
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

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(configuration.clientID)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

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

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(configuration.redirectURI)",
            "client_id=\(configuration.clientID)",
            "code_verifier=\(codeVerifier)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

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
