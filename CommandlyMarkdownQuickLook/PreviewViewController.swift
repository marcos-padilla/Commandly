import AppKit
import MarkdownPreviewKit
import QuickLookUI
import WebKit

final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private let previewBuilder = MarkdownQuickLookPreviewBuilder()
    private var previewWebView: WKWebView?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true

        previewWebView = webView
        view = webView
        preferredContentSize = NSSize(width: 900, height: 700)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        guard url.isFileURL else {
            throw MarkdownQuickLookError.unsupportedURL
        }

        let renderedHTML = try await previewBuilder.renderFile(at: url)
        try Task.checkCancellation()

        guard let previewWebView else {
            throw MarkdownQuickLookError.previewViewUnavailable
        }

        title = url.lastPathComponent
        previewWebView.loadHTMLString(Self.applyingContentSecurityPolicy(to: renderedHTML), baseURL: nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let targetURL = navigationAction.request.url
        let isInternalDocumentNavigation = targetURL?.scheme == "about"
            && targetURL?.path == "blank"
            && targetURL?.host == nil
        return isInternalDocumentNavigation ? .allow : .cancel
    }

    private static func applyingContentSecurityPolicy(to html: String) -> String {
        let policy = """
        <meta http-equiv="Content-Security-Policy" content="\(MarkdownHTMLHooks.contentSecurityPolicy)">
        """

        guard let head = html.range(of: "<head>", options: [.caseInsensitive]) else {
            return "<!doctype html><html><head>\(policy)</head><body>\(html)</body></html>"
        }

        var securedHTML = html
        securedHTML.insert(contentsOf: policy, at: head.upperBound)
        return securedHTML
    }
}
