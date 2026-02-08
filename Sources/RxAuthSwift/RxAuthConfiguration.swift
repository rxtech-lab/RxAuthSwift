import Foundation

public struct RxAuthConfiguration: Sendable {
    public let issuer: String
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]

    public let authorizePath: String
    public let tokenPath: String
    public let userInfoPath: String

    public let keychainServiceName: String

    public init(
        issuer: String,
        clientID: String,
        redirectURI: String,
        scopes: [String] = ["openid", "profile", "email"],
        authorizePath: String = "/api/oauth/authorize",
        tokenPath: String = "/api/oauth/token",
        userInfoPath: String = "/api/oauth/userinfo",
        keychainServiceName: String = "com.rxlab.RxAuthSwift"
    ) {
        self.issuer = issuer
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.authorizePath = authorizePath
        self.tokenPath = tokenPath
        self.userInfoPath = userInfoPath
        self.keychainServiceName = keychainServiceName
    }

    public var authorizeURL: URL? {
        URL(string: issuer + authorizePath)
    }

    public var tokenURL: URL? {
        URL(string: issuer + tokenPath)
    }

    public var userInfoURL: URL? {
        URL(string: issuer + userInfoPath)
    }

    public var redirectScheme: String? {
        URL(string: redirectURI)?.scheme
    }
}
