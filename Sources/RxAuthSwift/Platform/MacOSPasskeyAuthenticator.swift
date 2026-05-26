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
#endif
