import Foundation

public protocol TokenStorageProtocol: Sendable {
    func saveAccessToken(_ token: String) throws
    func getAccessToken() -> String?
    func deleteAccessToken() throws

    func saveRefreshToken(_ token: String) throws
    func getRefreshToken() -> String?
    func deleteRefreshToken() throws

    func saveExpiresAt(_ date: Date) throws
    func getExpiresAt() -> Date?

    func isTokenExpired() -> Bool
    func clearAll() throws
}
