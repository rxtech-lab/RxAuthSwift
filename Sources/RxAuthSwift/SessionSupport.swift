import Foundation

/// The user-info endpoint answered 401: the access token was rejected, which
/// (unlike a network error) is evidence about the session itself.
struct UserInfoRejected: LocalizedError {
    var errorDescription: String? {
        OAuthError.userInfoFailed("Failed to fetch user info").errorDescription
    }
}

/// Asks the system for extra run time while a short critical step finishes,
/// such as saving a rotated refresh token. Uses `performExpiringActivity`, which
/// (unlike `UIApplication.beginBackgroundTask`) is also allowed in app
/// extensions. A no-op on macOS, where apps aren't suspended this way.
final class BackgroundActivity: @unchecked Sendable {
    #if os(iOS)
    private let finished = DispatchSemaphore(value: 0)
    #endif

    init(reason: String) {
        #if os(iOS)
        let finished = finished
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
            // The activity lasts while this block runs. On expiry the system
            // calls it again with `expired == true`; that call returns at once.
            guard !expired else { return }
            _ = finished.wait(timeout: .now() + 30)
        }
        #endif
    }

    func end() {
        #if os(iOS)
        finished.signal()
        #endif
    }
}
