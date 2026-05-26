import Foundation

/// Server-driven UI schema describing the sign-in or sign-up form.
///
/// Fetched from `GET {issuer}/api/auth/ui-schema/{flow}?client_id=...`.
/// Lets the backend evolve labels, validation, and supported auth methods
/// without re-shipping the native client.
public struct AuthUISchema: Codable, Sendable, Equatable {
    public enum Flow: String, Codable, Sendable, Equatable {
        case signin
        case signup
    }

    public let flow: Flow
    public let title: String
    public let submitLabel: String
    public let fields: [Field]
    public let supportedMethods: [SupportedMethod]
    public let links: [Link]?

    public struct Field: Codable, Sendable, Equatable, Identifiable {
        public enum FieldType: String, Codable, Sendable, Equatable {
            case text
            case email
            case password
            case name
        }

        public let key: String
        public let label: String
        public let placeholder: String?
        public let type: FieldType
        public let isPassword: Bool
        public let required: Bool
        public let autocomplete: String?
        public let validation: Validation?

        public var id: String { key }
    }

    public struct Validation: Codable, Sendable, Equatable {
        public let minLength: Int?
        public let maxLength: Int?
        public let pattern: String?
        public let patternMessage: String?
    }

    public struct SupportedMethod: Codable, Sendable, Equatable, Identifiable {
        public enum MethodID: String, Codable, Sendable, Equatable {
            case password
            case passkey
            /// WWDC 2025 / iOS 26 / macOS 26 `ASAuthorizationAccountCreationProvider`
            /// — the OS shows a native sheet that collects email/phone/name
            /// from iCloud, no form fields needed in the app. Emit this method
            /// only on the signup flow.
            case passkeyAccountCreation = "passkey_account_creation"
        }

        public let id: MethodID
        public let label: String
        public let primary: Bool
    }

    public struct Link: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let label: String
        public let href: String
    }
}

extension AuthUISchema.Field {
    /// Validate `value` against this field's rules. Returns a user-facing
    /// error string when invalid, or nil when the value passes.
    public func validate(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if required && trimmed.isEmpty {
            return "\(label) is required"
        }

        // Optional empty fields are valid.
        if !required && trimmed.isEmpty {
            return nil
        }

        if let v = validation {
            if let min = v.minLength, value.count < min {
                return "\(label) must be at least \(min) characters"
            }
            if let max = v.maxLength, value.count > max {
                return "\(label) must be at most \(max) characters"
            }
            if let pattern = v.pattern,
               let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
               ) == nil {
                return v.patternMessage ?? "\(label) is not valid"
            }
        }
        return nil
    }
}
