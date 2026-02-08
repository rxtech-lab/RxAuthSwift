import Foundation

public enum OAuthError: LocalizedError, Sendable {
    case invalidURL
    case invalidConfiguration
    case authenticationFailed(String)
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case networkError(String)
    case userInfoFailed(String)
    case noRefreshToken
    case invalidCallbackURL
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .invalidConfiguration:
            return "Invalid OAuth configuration"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .tokenRefreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .userInfoFailed(let message):
            return "Failed to fetch user info: \(message)"
        case .noRefreshToken:
            return "No refresh token available"
        case .invalidCallbackURL:
            return "Invalid callback URL received"
        case .cancelled:
            return "Authentication was cancelled"
        }
    }
}

public enum KeychainError: LocalizedError, Sendable {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        case .deleteFailed(let status):
            return "Keychain delete failed with status: \(status)"
        case .unexpectedData:
            return "Unexpected data format in keychain"
        }
    }
}
