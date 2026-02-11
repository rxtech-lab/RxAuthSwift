#if canImport(WebKit) && os(macOS)
import AppKit
import WebKit

@MainActor
final class MacOSWebAuthSession: NSObject, WebAuthSessionProvider {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var urlTextField: NSTextField?
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

        let urlField = NSTextField()
        urlField.isEditable = false
        urlField.isSelectable = true
        urlField.isBordered = true
        urlField.bezelStyle = .roundedBezel
        urlField.font = .systemFont(ofSize: 13)
        urlField.lineBreakMode = .byTruncatingTail
        urlField.cell?.truncatesLastVisibleLine = true
        urlField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        urlField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlField.stringValue = url.absoluteString
        self.urlTextField = urlField

        let toolbar = NSStackView(views: [urlField])
        toolbar.orientation = .horizontal
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        toolbar.setHuggingPriority(.required, for: .horizontal)

        let container = NSStackView(views: [toolbar, webView])
        container.orientation = .vertical
        container.spacing = 0

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign In"
        window.contentView = container
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window

        webView.load(URLRequest(url: url))
    }

    private func complete(with result: Result<URL, any Error>) {
        webView?.navigationDelegate = nil
        webView = nil
        urlTextField = nil

        window?.orderOut(nil)
        window = nil

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

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            self.urlTextField?.stringValue = webView.url?.absoluteString ?? ""
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
