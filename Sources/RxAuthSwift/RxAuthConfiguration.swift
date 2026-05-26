import Foundation

public struct RxAuthConfiguration: Sendable {
    public let issuer: String
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]

    public let authorizePath: String
    public let tokenPath: String
    public let userInfoPath: String
    public let nativePasswordTokenPath: String?
    public let nativeSignupPath: String?
    public let passkeyChallengePath: String?
    public let passkeyVerificationPath: String?
    public let passkeyRegistrationChallengePath: String?
    public let passkeyRegistrationVerificationPath: String?
    public let passkeyRelyingPartyIdentifier: String?

    public let keychainServiceName: String

    public init(
        issuer: String,
        clientID: String,
        redirectURI: String,
        scopes: [String] = ["openid", "profile", "email"],
        authorizePath: String = "/api/oauth/authorize",
        tokenPath: String = "/api/oauth/token",
        userInfoPath: String = "/api/oauth/userinfo",
        nativePasswordTokenPath: String? = nil,
        nativeSignupPath: String? = "/api/oauth/signup",
        passkeyChallengePath: String? = nil,
        passkeyVerificationPath: String? = nil,
        passkeyRegistrationChallengePath: String? = nil,
        passkeyRegistrationVerificationPath: String? = nil,
        passkeyRelyingPartyIdentifier: String? = nil,
        keychainServiceName: String = "com.rxlab.RxAuthSwift"
    ) {
        self.issuer = issuer
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.authorizePath = authorizePath
        self.tokenPath = tokenPath
        self.userInfoPath = userInfoPath
        self.nativePasswordTokenPath = nativePasswordTokenPath
        self.nativeSignupPath = nativeSignupPath
        self.passkeyChallengePath = passkeyChallengePath
        self.passkeyVerificationPath = passkeyVerificationPath
        self.passkeyRegistrationChallengePath = passkeyRegistrationChallengePath
        self.passkeyRegistrationVerificationPath = passkeyRegistrationVerificationPath
        self.passkeyRelyingPartyIdentifier = passkeyRelyingPartyIdentifier
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

    public var nativePasswordTokenURL: URL? {
        URL(string: issuer + (nativePasswordTokenPath ?? tokenPath))
    }

    public var nativeSignupURL: URL? {
        guard let nativeSignupPath else { return nil }
        return URL(string: issuer + nativeSignupPath)
    }

    public var passkeyChallengeURL: URL? {
        guard let passkeyChallengePath else { return nil }
        return URL(string: issuer + passkeyChallengePath)
    }

    public var passkeyVerificationURL: URL? {
        guard let passkeyVerificationPath else { return nil }
        return URL(string: issuer + passkeyVerificationPath)
    }

    public var passkeyRegistrationChallengeURL: URL? {
        guard let passkeyRegistrationChallengePath else { return nil }
        return URL(string: issuer + passkeyRegistrationChallengePath)
    }

    public var passkeyRegistrationVerificationURL: URL? {
        guard let passkeyRegistrationVerificationPath else { return nil }
        return URL(string: issuer + passkeyRegistrationVerificationPath)
    }

    public var redirectScheme: String? {
        URL(string: redirectURI)?.scheme
    }
}
