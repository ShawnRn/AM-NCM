import SwiftUI
import WebKit

struct AppleMusicLoginView: View {
    let connected: (AppleMusicSession) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var web = AppleLoginWebView()
    @State private var status = "请在 Apple Music 网页中选择「登录」。"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接 Apple Music").font(.title2.weight(.semibold))
            Text(status).foregroundStyle(.secondary)
            AppleLoginBrowser(web: web)
            HStack {
                Button("重新载入") { web.reload() }
                Spacer()
                Button("关闭") { dismiss() }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 620)
        .task {
            var lastDeveloper: String?
            var lastUser: String?
            while !Task.isCancelled {
                if let tokens = await web.tokens(),
                   tokens.developer != lastDeveloper || tokens.user != lastUser {
                    lastDeveloper = tokens.developer
                    lastUser = tokens.user
                    status = "正在验证 Apple Music 登录…"
                    do {
                        let session = try await AppleMusicImport.connect(developer: tokens.developer, user: tokens.user)
                        try Task.checkCancellation()
                        try connected(session)
                        dismiss()
                        return
                    } catch is CancellationError {
                        return
                    } catch {
                        status = "Apple Music 未确认这次登录。请在网页里重新登录，或选择「重新载入」。"
                    }
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

private struct AppleLoginBrowser: NSViewRepresentable {
    let web: AppleLoginWebView

    func makeNSView(context: Context) -> NSView { web.container }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class AppleLoginWebView: NSObject, WKUIDelegate, WKNavigationDelegate {
    let container = NSView()
    private let page: WKWebView
    private var popup: WKWebView?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        page = WKWebView(frame: .zero, configuration: config)
        super.init()
        page.uiDelegate = self
        page.navigationDelegate = self
        attach(page)
        reload()
    }

    func reload() {
        popup?.removeFromSuperview()
        popup = nil
        if let url = URL(string: "https://music.apple.com/") {
            page.load(URLRequest(url: url))
        }
    }

    func tokens() async -> (developer: String, user: String)? {
        guard page.url?.host == "music.apple.com" else { return nil }
        let script = """
        (() => {
            if (location.origin !== 'https://music.apple.com') return null;
            const music = window.MusicKit?.getInstance?.();
            return {developer: music?.developerToken ?? '', user: music?.musicUserToken ?? ''};
        })()
        """
        guard let values = (try? await page.evaluateJavaScript(script)) as? [String: String],
              let developer = values["developer"], !developer.isEmpty else { return nil }
        if let user = values["user"], !user.isEmpty { return (developer, user) }
        let cookies = await page.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard let cookie = cookies.first(where: {
            $0.name == "media-user-token" && ["music.apple.com", ".music.apple.com"].contains($0.domain)
        }) else { return nil }
        return (developer, cookie.value)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard Self.isApplePage(navigationAction.request.url) else { return nil }
        popup?.removeFromSuperview()
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.navigationDelegate = self
        child.uiDelegate = self
        popup = child
        attach(child)
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView == popup {
            webView.removeFromSuperview()
            popup = nil
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.targetFrame?.isMainFrame == false { return .allow }
        return Self.isApplePage(navigationAction.request.url) ? .allow : .cancel
    }

    private static func isApplePage(_ url: URL?) -> Bool {
        if url?.absoluteString == "about:blank" { return true }
        guard url?.scheme == "https", let host = url?.host else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com")
    }

    private func attach(_ view: WKWebView) {
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
