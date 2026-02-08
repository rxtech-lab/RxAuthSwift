import Foundation

public enum AuthenticationState: Sendable {
    case unknown
    case authenticated
    case unauthenticated
}

public struct User: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let email: String?
    public let image: String?

    public init(id: String, name: String?, email: String?, image: String?) {
        self.id = id
        self.name = name
        self.email = email
        self.image = image
    }
}
