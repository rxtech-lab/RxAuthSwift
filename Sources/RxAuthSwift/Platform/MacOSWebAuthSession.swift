#if canImport(WebKit) && os(macOS)
import AppKit
import WebKit

@MainActor
final class MacOSWebAuthSession: NSObject, WebAuthSessionProvider {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var callbackScheme: String = ""

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        self.callbackScheme = callbackURLScheme
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            setupAndShowWindow(url: url)
        }
    }

    private func setupAndShowWindow(url: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign In"
        window.contentView = webView
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window

        webView.load(URLRequest(url: url))
    }

    private func complete(with result: Result<URL, any Error>) {
        window?.close()
        window = nil
        webView?.navigationDelegate = nil
        webView = nil

        let cont = continuation
        continuation = nil
        switch result {
        case .success(let url):
            cont?.resume(returning: url)
        case .failure(let error):
            cont?.resume(throwing: error)
        }
    }
}

extension MacOSWebAuthSession: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        MainActor.assumeIsolated {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme,
                  scheme == self.callbackScheme
            else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            self.complete(with: .success(url))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated {
            self.complete(with: .failure(OAuthError.authenticationFailed(error.localizedDescription)))
        }
    }
}

extension MacOSWebAuthSession: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if self.continuation != nil {
                self.complete(with: .failure(OAuthError.cancelled))
            }
        }
    }
}
#endif
