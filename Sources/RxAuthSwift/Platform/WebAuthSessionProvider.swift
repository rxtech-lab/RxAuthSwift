import Foundation

@MainActor
protocol WebAuthSessionProvider: Sendable {
    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL
}
