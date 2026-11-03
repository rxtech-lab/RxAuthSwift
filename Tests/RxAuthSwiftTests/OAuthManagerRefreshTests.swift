import Foundation
import Testing
@testable import RxAuthSwift

@Suite("Conditional token refresh")
struct OAuthManagerRefreshTests {
    @Test @MainActor func validAccessTokenDoesNotRequireRefreshToken() async throws {
        let storage = InMemoryTokenStorage()
        try storage.saveAccessToken("valid-access")
        try storage.saveExpiresAt(Date().addingTimeInterval(3600))
        let manager = OAuthManager(configuration: .init(
            issuer: "https://auth.example.com", clientID: "test",
            redirectURI: "test://callback"), tokenStorage: storage)
        for _ in 0..<5 { try await manager.refreshTokenIfNeeded() }
        #expect(storage.getAccessToken() == "valid-access")
    }

    @Test @MainActor func missingAccessTokenStillRequiresRefresh() async throws {
        let storage = InMemoryTokenStorage()
        try storage.saveExpiresAt(Date().addingTimeInterval(3600))
        let manager = OAuthManager(configuration: .init(
            issuer: "https://auth.example.com", clientID: "test",
            redirectURI: "test://callback"), tokenStorage: storage)
        await #expect(throws: OAuthError.self) {
            try await manager.refreshTokenIfNeeded()
        }
    }
}
