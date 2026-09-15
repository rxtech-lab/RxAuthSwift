#if canImport(AuthenticationServices) && (os(macOS) || os(iOS))
import AuthenticationServices
import CryptoKit
import Foundation

/// What `ASAuthorizationAppleIDProvider` hands back after a successful
/// ceremony.
///
/// `fullName` and `email` are populated on the **first** authorization only —
/// Apple gives the user's name to the app exactly once and never again — so the
/// server has to be told about them on that first sign-in or the display name
/// is lost for good.
struct AppleSignInCredential {
    /// The signed JWT the server verifies against Apple's public keys. This is
    /// the actual proof of identity; everything else here is advisory.
    let identityToken: String
    /// Apple's stable per-app user identifier.
    let userIdentifier: String
    let givenName: String?
    let familyName: String?
    let email: String?
}

/// Drives the native Sign in with Apple sheet.
///
/// The browser flow the other providers use would work here too, but Apple's
/// own OS-level ceremony is the right call on its platforms: it reuses the
/// signed-in Apple Account, offers Hide My Email inline, and never leaves the
/// app. The trade-off is that the app receives the identity token directly
/// rather than through a redirect, so it posts it to the server's native
/// endpoint instead of exchanging an authorization code.
@MainActor
final class PlatformAppleSignInAuthenticator: NSObject {
    private var continuation: CheckedContinuation<AppleSignInCredential, Error>?
    private var retainedSelf: PlatformAppleSignInAuthenticator?

    /// - Parameter hashedNonce: SHA-256 of the server-issued nonce, hex-encoded.
    ///   Apple copies it verbatim into the identity token's `nonce` claim; the
    ///   server re-hashes its own copy and compares, which pins the token to one
    ///   single-use request. Use `PlatformAppleSignInAuthenticator.sha256Hex`.
    func signIn(hashedNonce: String) async throws -> AppleSignInCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.retainedSelf = self

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// Hex-encoded SHA-256, matching what the server computes before comparing.
    /// Pure, so it escapes the enclosing `@MainActor` isolation.
    nonisolated static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func complete(with result: Result<AppleSignInCredential, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.retainedSelf = nil

        switch result {
        case .success(let credential):
            continuation.resume(returning: credential)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension PlatformAppleSignInAuthenticator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            complete(with: .failure(OAuthError.authenticationFailed("Unexpected Apple credential")))
            return
        }

        guard
            let tokenData = credential.identityToken,
            let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            complete(with: .failure(OAuthError.authenticationFailed("Apple returned no identity token")))
            return
        }

        complete(with: .success(AppleSignInCredential(
            identityToken: identityToken,
            userIdentifier: credential.user,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName,
            email: credential.email
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

extension PlatformAppleSignInAuthenticator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        resolvePresentationAnchor()
    }
}
#endif
