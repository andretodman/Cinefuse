import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

struct HelpCenterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = HelpCenterBrowserState()

    var body: some View {
        VStack(spacing: 0) {
            header
            HelpCenterWebContainer(browser: browser)
        }
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            browser.loadInitialPage()
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: CinefuseTokens.Spacing.s) {
                Text("Cinefuse Help Center")
                    .font(CinefuseTokens.Typography.sectionTitle)
                Spacer()
                if browser.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button { browser.goBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(!browser.canGoBack)

                Button { browser.goForward() } label: {
                    Label("Forward", systemImage: "chevron.right")
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(!browser.canGoForward)

                Button { browser.reload() } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
            .padding(CinefuseTokens.Spacing.s)

            HStack(spacing: CinefuseTokens.Spacing.s) {
                Label(browser.sourceLabel, systemImage: browser.isUsingFallback ? "doc.text.magnifyingglass" : "network")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                Spacer()
                Text(browser.displayURLText)
                    .lineLimit(1)
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, CinefuseTokens.Spacing.s)
            .padding(.bottom, CinefuseTokens.Spacing.xs)

            if let errorMessage = browser.errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.horizontal, CinefuseTokens.Spacing.s)
                    .padding(.bottom, CinefuseTokens.Spacing.xs)
            }
            Divider()
        }
    }
}

private struct HelpCenterWebContainer: View {
    @ObservedObject var browser: HelpCenterBrowserState

    var body: some View {
#if canImport(WebKit)
        Group {
            #if os(macOS)
            HelpCenterWebViewMac(browser: browser)
            #else
            HelpCenterWebViewIOS(browser: browser)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
        ScrollView {
            Text("Help Center is not available on this platform.")
                .padding(CinefuseTokens.Spacing.m)
        }
#endif
    }
}

#if canImport(WebKit)
final class HelpCenterBrowserState: NSObject, ObservableObject {
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isUsingFallback = false
    @Published var errorMessage: String?
    @Published var displayURLText = "bundled://help-center.html"

    weak var webView: WKWebView?

    private var didAttemptHostedLoad = false
    private var hasLoadedFallback = false

    var sourceLabel: String {
        isUsingFallback ? "Bundled help content" : "Hosted help content"
    }

    func attachWebView(_ webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        refreshNavigationState()
    }

    func loadInitialPage() {
        guard let webView else { return }
        errorMessage = nil
        if let hostedURL = HelpCenterContent.hostedURL {
            didAttemptHostedLoad = true
            isUsingFallback = false
            displayURLText = hostedURL.absoluteString
            webView.load(URLRequest(url: hostedURL))
            return
        }
        loadFallback(reason: nil)
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        if isUsingFallback {
            loadFallback(reason: nil)
            return
        }
        if let hostedURL = HelpCenterContent.hostedURL {
            webView?.load(URLRequest(url: hostedURL))
        } else {
            loadFallback(reason: nil)
        }
    }

    private func loadFallback(reason: String?) {
        guard let webView else { return }
        hasLoadedFallback = true
        isUsingFallback = true
        displayURLText = "bundled://help-center.html"
        if let reason {
            errorMessage = "Hosted help unavailable (\(reason)). Showing bundled help."
        }
        webView.loadHTMLString(HelpCenterContent.fallbackHTML, baseURL: nil)
    }

    private func refreshNavigationState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        if let absoluteURL = webView?.url?.absoluteString, !absoluteURL.isEmpty {
            displayURLText = absoluteURL
        }
    }
}

extension HelpCenterBrowserState: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error: error)
    }

    private func handle(error: Error) {
        isLoading = false
        refreshNavigationState()
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if didAttemptHostedLoad && !hasLoadedFallback {
            loadFallback(reason: nsError.localizedDescription)
            return
        }
        errorMessage = "Help page load failed: \(nsError.localizedDescription)"
    }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
private struct HelpCenterWebViewMac: NSViewRepresentable {
    @ObservedObject var browser: HelpCenterBrowserState

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
        browser.attachWebView(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if browser.webView !== nsView {
            browser.attachWebView(nsView)
        }
    }
}
#endif
#endif

#if canImport(WebKit) && canImport(UIKit)
private struct HelpCenterWebViewIOS: UIViewRepresentable {
    @ObservedObject var browser: HelpCenterBrowserState

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        browser.attachWebView(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if browser.webView !== uiView {
            browser.attachWebView(uiView)
        }
    }
}
#endif

private enum HelpCenterContent {
    static var hostedURL: URL? {
        let raw = ProcessInfo.processInfo.environment["CINEFUSE_HELP_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    static var fallbackHTML: String {
        guard let url = Bundle.module.url(forResource: "help-center", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "<html><body><h1>Cinefuse Help</h1><p>Bundled help content unavailable.</p></body></html>"
        }
        return html
    }
}
