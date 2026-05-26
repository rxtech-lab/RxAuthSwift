#if canImport(AuthenticationServices) && os(macOS)
import AppKit
import AuthenticationServices
import Foundation

@MainActor
final class MacOSPasskeyAuthenticator: NSObject {
    private var continuation: CheckedContinuation<PasskeyAssertion, Error>?
    private var retainedSelf: MacOSPasskeyAuthenticator?

    func authenticate(
        relyingPartyIdentifier: String,
        challenge: Data,
        allowedCredentialIDs: [Data] = []
    ) async throws -> PasskeyAssertion {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.retainedSelf = self

            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            let request = provider.createCredentialAssertionRequest(challenge: challenge)
            request.allowedCredentials = allowedCredentialIDs.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func complete(with result: Result<PasskeyAssertion, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.retainedSelf = nil

        switch result {
        case .success(let assertion):
            continuation.resume(returning: assertion)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension MacOSPasskeyAuthenticator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            complete(with: .failure(OAuthError.authenticationFailed("Unexpected passkey credential")))
            return
        }

        complete(with: .success(PasskeyAssertion(
            credentialID: credential.credentialID,
            rawClientDataJSON: credential.rawClientDataJSON,
            rawAuthenticatorData: credential.rawAuthenticatorData,
            signature: credential.signature,
            userID: credential.userID
        )))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           ASAuthorizationError.Code(rawValue: nsError.code) == .canceled {
            complete(with: .failure(OAuthError.cancelled))
        } else {
            complete(with: .failure(OAuthError.authenticationFailed(error.localizedDescription)))
        }
    }
}

extension MacOSPasskeyAuthenticator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? ASPresentationAnchor()
    }
}

struct PasskeyAssertion {
    let credentialID: Data
    let rawClientDataJSON: Data
    let rawAuthenticatorData: Data
    let signature: Data
    let userID: Data
}

@MainActor
final class MacOSPasskeyRegistrationAuthenticator: NSObject {
    private var continuation: CheckedContinuation<PasskeyRegistration, Error>?
    private var retainedSelf: MacOSPasskeyRegistrationAuthenticator?

    func register(
        relyingPartyIdentifier: String,
        challenge: Data,
        name: String,
        userID: Data
    ) async throws -> PasskeyRegistration {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.retainedSelf = self

            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            let request = provider.createCredentialRegistrationRequest(
                challenge: challenge,
                name: name,
                userID: userID
            )

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func complete(with result: Result<PasskeyRegistration, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.retainedSelf = nil

        switch result {
        case .success(let registration):
            continuation.resume(returning: registration)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension MacOSPasskeyRegistrationAuthenticator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            complete(with: .failure(OAuthError.authenticationFailed("Unexpected passkey registration credential")))
            return
        }

        complete(with: .success(PasskeyRegistration(
            credentialID: credential.credentialID,
            rawClientDataJSON: credential.rawClientDataJSON,
            rawAttestationObject: credential.rawAttestationObject
        )))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           ASAuthorizationError.Code(rawValue: nsError.code) == .canceled {
            complete(with: .failure(OAuthError.cancelled))
        } else {
            complete(with: .failure(OAuthError.authenticationFailed(error.localizedDescription)))
        }
    }
}

extension MacOSPasskeyRegistrationAuthenticator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? ASPresentationAnchor()
    }
}

struct PasskeyRegistration {
    let credentialID: Data
    let rawClientDataJSON: Data
    let rawAttestationObject: Data?
}

/// Performs Apple's "Automatic Passkey Upgrade" (WWDC iOS 18 / macOS 15):
/// silently creates a passkey for an already-authenticated account using
/// `ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest` with
/// `requestStyle = .conditional`. The OS shows no UI; any failure (no
/// candidates, user denial, biometrics off, etc.) resolves to `nil` so the
/// caller can treat it as a no-op without disturbing the sign-up flow.
@MainActor
final class MacOSPasskeyConditionalUpgradeAuthenticator: NSObject {
    private var continuation: CheckedContinuation<PasskeyRegistration?, Never>?
    private var retainedSelf: MacOSPasskeyConditionalUpgradeAuthenticator?

    func upgrade(
        relyingPartyIdentifier: String,
        challenge: Data,
        name: String,
        userID: Data
    ) async -> PasskeyRegistration? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PasskeyRegistration?, Never>) in
            self.continuation = continuation
            self.retainedSelf = self

            let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                relyingPartyIdentifier: relyingPartyIdentifier
            )
            let request = provider.createCredentialRegistrationRequest(
                challenge: challenge,
                name: name,
                userID: userID
            )
            request.requestStyle = .conditional

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func complete(with registration: PasskeyRegistration?) {
        guard let continuation else { return }
        self.continuation = nil
        self.retainedSelf = nil
        continuation.resume(returning: registration)
    }
}

extension MacOSPasskeyConditionalUpgradeAuthenticator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            complete(with: nil)
            return
        }
        complete(with: PasskeyRegistration(
            credentialID: credential.credentialID,
            rawClientDataJSON: credential.rawClientDataJSON,
            rawAttestationObject: credential.rawAttestationObject
        ))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        complete(with: nil)
    }
}

extension MacOSPasskeyConditionalUpgradeAuthenticator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? ASPresentationAnchor()
    }
}

/// Result of the WWDC 2025 `ASAuthorizationAccountCreationProvider` ceremony.
/// The system sheet collects the contact identifier (email or phone) and
/// optional name from the user's iCloud profile, then creates a passkey.
struct PasskeyAccountCreation {
    enum ContactIdentifier {
        case email(String)
        case phoneNumber(String)

        var value: String {
            switch self {
            case .email(let v), .phoneNumber(let v): return v
            }
        }

        var serverTypeString: String {
            switch self {
            case .email: return "email"
            case .phoneNumber: return "phone_number"
            }
        }
    }

    let contactIdentifier: ContactIdentifier
    let name: PersonNameComponents?
    let credentialID: Data
    let rawClientDataJSON: Data
    let rawAttestationObject: Data?
}

/// Drives Apple's iOS 26 / macOS 26 `ASAuthorizationAccountCreationProvider`
/// ceremony: the OS shows a native sheet that pulls email/phone/name from
/// iCloud, the user confirms with biometrics, and the system generates the
/// passkey. The caller never collects a username — it arrives back here.
@MainActor
final class MacOSPasskeyAccountCreationAuthenticator: NSObject {
    private var continuation: CheckedContinuation<PasskeyAccountCreation, Error>?
    private var retainedSelf: MacOSPasskeyAccountCreationAuthenticator?

    func createAccount(
        relyingPartyIdentifier: String,
        challenge: Data,
        userID: Data,
        acceptedIdentifiers: [ASContactIdentifierRequest] = [.email],
        shouldRequestName: Bool = true
    ) async throws -> PasskeyAccountCreation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.retainedSelf = self

            let provider = ASAuthorizationAccountCreationProvider()
            let request = provider.createPlatformPublicKeyCredentialRegistrationRequest(
                acceptedContactIdentifiers: acceptedIdentifiers,
                shouldRequestName: shouldRequestName,
                relyingPartyIdentifier: relyingPartyIdentifier,
                challenge: challenge,
                userID: userID
            )

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func complete(with result: Result<PasskeyAccountCreation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.retainedSelf = nil
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

extension MacOSPasskeyAccountCreationAuthenticator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAccountCreationPlatformPublicKeyCredential else {
            complete(with: .failure(OAuthError.authenticationFailed("Unexpected passkey account-creation credential")))
            return
        }

        let identifier: PasskeyAccountCreation.ContactIdentifier
        switch credential.contactIdentifier {
        case .email(let email):
            identifier = .email(email.value)
        case .phoneNumber(let phone):
            identifier = .phoneNumber(phone.value)
        @unknown default:
            complete(with: .failure(OAuthError.authenticationFailed("Unsupported contact identifier")))
            return
        }

        let registration = credential.credentialRegistration
        complete(with: .success(PasskeyAccountCreation(
            contactIdentifier: identifier,
            name: credential.name,
            credentialID: registration.credentialID,
            rawClientDataJSON: registration.rawClientDataJSON,
            rawAttestationObject: registration.rawAttestationObject
        )))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           ASAuthorizationError.Code(rawValue: nsError.code) == .canceled {
            complete(with: .failure(OAuthError.cancelled))
        } else {
            complete(with: .failure(OAuthError.authenticationFailed(error.localizedDescription)))
        }
    }
}

extension MacOSPasskeyAccountCreationAuthenticator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? ASPresentationAnchor()
    }
}
#endif
