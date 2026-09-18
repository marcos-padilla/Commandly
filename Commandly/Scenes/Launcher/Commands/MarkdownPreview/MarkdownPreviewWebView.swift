import AppKit
import Infrastructure
import MarkdownPreviewKit
import SwiftUI
import WebKit

nonisolated struct MarkdownPreviewSearchResult: Equatable, Sendable {
    let currentMatch: Int
    let totalMatches: Int
    let errorMessage: String?

    static let empty = MarkdownPreviewSearchResult(
        currentMatch: 0,
        totalMatches: 0,
        errorMessage: nil
    )
}

/// Owns the narrow JavaScript and navigation boundary for the Markdown preview web view.
///
/// Document HTML is produced by `MarkdownPreviewKit`; document-provided HTML and scripts are
/// escaped before this controller receives them. Only the renderer-owned, nonce-authorized hooks
/// are called from native code.
@MainActor
final class MarkdownPreviewWebController: NSObject, MarkdownPreviewWebControlling {
    var onOpenMarkdownDocument: ((URL) -> Void)?
    var onSearchResult: ((MarkdownPreviewSearchResult) -> Void)?
    var onNavigationFailure: ((String) -> Void)?

    private let urlOpener: any URLOpening
    private weak var webView: WKWebView?
    private var documentBaseURL: URL?
    private var pendingHTML: String?
    private var pendingSourceVisibility = false
    private var pendingZoom = 1.0
    private var pendingScrollPosition: Double?
    private var cachedScrollPosition = 0.0
    private var isPageReady = false
    private var isLoadingOwnedDocument = false
    private var searchGeneration = 0

    private struct PendingSearch {
        let query: String
        let options: MarkdownPreviewSearchOptions
    }

    private var pendingSearch: PendingSearch?

    init(urlOpener: any URLOpening) {
        self.urlOpener = urlOpener
        super.init()
    }

    func makeWebView() -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences = preferences
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(self, name: Self.scrollMessageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.underPageBackgroundColor = .clear
        attach(webView)
        return webView
    }

    func attach(_ webView: WKWebView) {
        guard self.webView !== webView else { return }
        if let attachedWebView = self.webView {
            detach(attachedWebView)
        }
        self.webView = webView
        webView.navigationDelegate = self
        if let pendingHTML {
            loadOwnedHTML(pendingHTML, baseURL: documentBaseURL)
        }
    }

    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        self.webView = nil
        isPageReady = false
        isLoadingOwnedDocument = false
        searchGeneration += 1
    }

    func loadHTML(_ html: String, baseURL: URL?) {
        pendingHTML = html
        documentBaseURL = baseURL?.standardizedFileURL
        guard webView != nil else { return }
        loadOwnedHTML(html, baseURL: documentBaseURL)
    }

    func find(_ query: String, options: MarkdownPreviewSearchOptions) {
        pendingSearch = PendingSearch(query: query, options: options)
        guard let webView, isPageReady else { return }
        executePendingSearch(on: webView)
    }

    private func executePendingSearch(on webView: WKWebView) {
        guard let pendingSearch, isPageReady else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let arguments: [String: Any] = [
            "query": pendingSearch.query,
            "options": [
                "caseSensitive": pendingSearch.options.isCaseSensitive,
                "wholeWord": pendingSearch.options.matchesWholeWords,
                "regex": pendingSearch.options.usesRegularExpression,
                "backwards": pendingSearch.options.searchesBackwards,
            ],
        ]
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let value = try await webView.callAsyncJavaScript(
                    "return window.commandlyMarkdown.search(query, options);",
                    arguments: arguments,
                    in: nil,
                    contentWorld: .page
                )
                guard generation == self.searchGeneration else { return }
                self.onSearchResult?(Self.searchResult(from: value))
            } catch {
                guard generation == self.searchGeneration else { return }
                self.onSearchResult?(
                    MarkdownPreviewSearchResult(
                        currentMatch: 0,
                        totalMatches: 0,
                        errorMessage: "Search is unavailable for this preview."
                    )
                )
            }
        }
    }

    func clearFind() {
        pendingSearch = nil
        searchGeneration += 1
        onSearchResult?(.empty)
        guard let webView, isPageReady else { return }
        Task { [weak webView] in
            _ = try? await webView?.callAsyncJavaScript(
                "return window.commandlyMarkdown.clearSearch();",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
        }
    }

    func setSource(_ source: String, isVisible: Bool) {
        // The renderer already placed an escaped copy of source in the page. Keeping the source
        // parameter in the protocol makes this boundary explicit without reinserting document text.
        _ = source
        pendingSourceVisibility = isVisible
        guard let webView, isPageReady else { return }
        applySourceVisibilityThenSearch(on: webView)
    }

    func setZoom(_ zoom: Double) {
        guard zoom.isFinite else { return }
        pendingZoom = min(
            max(zoom, MarkdownPreviewConfiguration.zoomRange.lowerBound),
            MarkdownPreviewConfiguration.zoomRange.upperBound
        )
        guard let webView, isPageReady else { return }
        applyZoom(on: webView)
    }

    func scrollTo(anchor: String) {
        guard let webView, isPageReady else { return }
        callHook(
            on: webView,
            script: "return window.commandlyMarkdown.scrollToAnchor(anchor);",
            arguments: ["anchor": anchor]
        )
    }

    func currentScrollPosition() -> Double? {
        cachedScrollPosition.isFinite && cachedScrollPosition >= 0
            ? cachedScrollPosition
            : nil
    }

    func restoreScrollPosition(_ position: Double) {
        guard position.isFinite, position >= 0 else { return }
        cachedScrollPosition = position
        pendingScrollPosition = position
        guard let webView, isPageReady else { return }
        applyScrollPosition(on: webView)
    }

    func makePDF() async throws -> Data {
        guard let webView, isPageReady else {
            throw MarkdownPreviewWebControllerError.unavailable
        }
        do {
            return try await webView.pdf(configuration: WKPDFConfiguration())
        } catch {
            throw MarkdownPreviewWebControllerError.pdfCreationFailed
        }
    }

    func printDocument() async throws {
        guard let webView, isPageReady else {
            throw MarkdownPreviewWebControllerError.unavailable
        }
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        // `run()` is also false when the user dismisses the print panel. Cancellation is a
        // successful no-op rather than a rendering failure.
        _ = operation.run()
    }

    private func loadOwnedHTML(_ html: String, baseURL: URL?) {
        guard let webView else { return }
        isPageReady = false
        isLoadingOwnedDocument = true
        cachedScrollPosition = 0
        searchGeneration += 1
        onSearchResult?(.empty)
        webView.stopLoading()
        webView.loadHTMLString(html.isEmpty ? Self.emptyDocument : html, baseURL: baseURL)
    }

    private func applyPendingState(on webView: WKWebView) {
        Task { [weak self, weak webView] in
            guard let self, let webView, self.webView === webView else { return }
            _ = try? await webView.callAsyncJavaScript(
                "return window.commandlyMarkdown.setSourceVisible(visible);",
                arguments: ["visible": self.pendingSourceVisibility],
                in: nil,
                contentWorld: .page
            )
            _ = try? await webView.callAsyncJavaScript(
                "return window.commandlyMarkdown.setZoom(zoom);",
                arguments: ["zoom": self.pendingZoom],
                in: nil,
                contentWorld: .page
            )
            if let position = self.pendingScrollPosition {
                self.pendingScrollPosition = nil
                _ = try? await webView.callAsyncJavaScript(
                    "window.scrollTo({top: position, left: 0, behavior: 'auto'}); return true;",
                    arguments: ["position": position],
                    in: nil,
                    contentWorld: .page
                )
            }
            guard self.webView === webView, self.isPageReady else { return }
            self.executePendingSearch(on: webView)
        }
    }

    private func applySourceVisibilityThenSearch(on webView: WKWebView) {
        let visibility = pendingSourceVisibility
        Task { [weak self, weak webView] in
            guard let self, let webView, self.webView === webView else { return }
            _ = try? await webView.callAsyncJavaScript(
                "return window.commandlyMarkdown.setSourceVisible(visible);",
                arguments: ["visible": visibility],
                in: nil,
                contentWorld: .page
            )
            guard self.webView === webView, self.isPageReady else { return }
            self.executePendingSearch(on: webView)
        }
    }

    private func applyZoom(on webView: WKWebView) {
        callHook(
            on: webView,
            script: "return window.commandlyMarkdown.setZoom(zoom);",
            arguments: ["zoom": pendingZoom]
        )
    }

    private func applyScrollPosition(on webView: WKWebView) {
        guard let pendingScrollPosition else { return }
        self.pendingScrollPosition = nil
        callHook(
            on: webView,
            script: "window.scrollTo({top: position, left: 0, behavior: 'auto'}); return true;",
            arguments: ["position": pendingScrollPosition]
        )
    }

    private func callHook(
        on webView: WKWebView,
        script: String,
        arguments: [String: Any]
    ) {
        Task { [weak webView] in
            _ = try? await webView?.callAsyncJavaScript(
                script,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
        }
    }

    private func handleActivatedLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return }
        switch scheme {
        case "http", "https", "mailto":
            Task { [weak self, urlOpener] in
                do {
                    try await urlOpener.openURL(url)
                } catch {
                    self?.onNavigationFailure?("The link could not be opened.")
                }
            }
        case "file":
            guard let documentURL = validatedMarkdownDocumentURL(url) else {
                onNavigationFailure?("That linked document is outside this preview’s folder.")
                return
            }
            onOpenMarkdownDocument?(documentURL)
        default:
            break
        }
    }

    private func validatedMarkdownDocumentURL(_ url: URL) -> URL? {
        guard let documentBaseURL,
              MarkdownPreviewFileTypes.supports(fileExtension: url.pathExtension) else {
            return nil
        }
        let base = documentBaseURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard candidate.path.hasPrefix(basePath) else { return nil }
        return candidate
    }

    private static func searchResult(from value: Any?) -> MarkdownPreviewSearchResult {
        guard let dictionary = value as? [String: Any] else { return .empty }
        return MarkdownPreviewSearchResult(
            currentMatch: (dictionary["current"] as? NSNumber)?.intValue ?? 0,
            totalMatches: (dictionary["total"] as? NSNumber)?.intValue ?? 0,
            errorMessage: dictionary["error"] as? String
        )
    }

    private static let emptyDocument = """
    <!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy"
    content="default-src 'none'; style-src 'unsafe-inline'"><style>html,body{background:transparent}</style>
    </head><body></body></html>
    """

    private static let scrollMessageName = "commandlyMarkdownScroll"
}

extension MarkdownPreviewWebController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.scrollMessageName,
              let number = message.body as? NSNumber else { return }
        let position = number.doubleValue
        guard position.isFinite, position >= 0 else { return }
        cachedScrollPosition = position
    }
}

extension MarkdownPreviewWebController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame != false else { return .cancel }

        if isLoadingOwnedDocument, navigationAction.navigationType == .other {
            return .allow
        }

        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            return .cancel
        }

        if url.scheme == "about", url.fragment != nil {
            scrollTo(anchor: url.fragment ?? "")
            return .cancel
        }

        handleActivatedLink(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard self.webView === webView else { return }
        isLoadingOwnedDocument = false
        isPageReady = true
        applyPendingState(on: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        guard self.webView === webView else { return }
        isLoadingOwnedDocument = false
        isPageReady = false
        onNavigationFailure?("The rendered preview could not be displayed.")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        guard self.webView === webView else { return }
        isLoadingOwnedDocument = false
        isPageReady = false
        onNavigationFailure?("The rendered preview could not be displayed.")
    }
}

struct MarkdownPreviewWebView: NSViewRepresentable {
    let controller: MarkdownPreviewWebController

    func makeNSView(context: Context) -> WKWebView {
        controller.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.attach(webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Void) {
        (webView.navigationDelegate as? MarkdownPreviewWebController)?.detach(webView)
    }
}
