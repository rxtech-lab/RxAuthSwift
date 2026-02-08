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

    enum CodingKeys: String, CodingKey {
        case id
        case sub
        case name
        case email
        case image
        case picture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Support both "id" and "sub" (OIDC standard) for user identifier
        if let id = try container.decodeIfPresent(String.self, forKey: .id) {
            self.id = id
        } else if let sub = try container.decodeIfPresent(String.self, forKey: .sub) {
            self.id = sub
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Neither 'id' nor 'sub' found in user info response"
                )
            )
        }
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        // Support both "image" and "picture" (OIDC standard) for profile image
        self.image = try container.decodeIfPresent(String.self, forKey: .image)
            ?? container.decodeIfPresent(String.self, forKey: .picture)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(image, forKey: .image)
    }
}
