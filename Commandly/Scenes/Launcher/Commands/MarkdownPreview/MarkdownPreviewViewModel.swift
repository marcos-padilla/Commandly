import CommandKit
import Foundation
import MarkdownPreviewKit
import Observation

nonisolated struct MarkdownPreviewSearchOptions: Equatable, Sendable {
    var isCaseSensitive: Bool
    var matchesWholeWords: Bool
    var usesRegularExpression: Bool
    var searchesBackwards: Bool
    var wraps: Bool

    init(
        isCaseSensitive: Bool = false,
        matchesWholeWords: Bool = false,
        usesRegularExpression: Bool = false,
        searchesBackwards: Bool = false,
        wraps: Bool = true
    ) {
        self.isCaseSensitive = isCaseSensitive
        self.matchesWholeWords = matchesWholeWords
        self.usesRegularExpression = usesRegularExpression
        self.searchesBackwards = searchesBackwards
        self.wraps = wraps
    }
}

@MainActor
protocol MarkdownPreviewWebControlling: AnyObject {
    func loadHTML(_ html: String, baseURL: URL?)
    func find(_ query: String, options: MarkdownPreviewSearchOptions)
    func clearFind()
    func setSource(_ source: String, isVisible: Bool)
    func setZoom(_ zoom: Double)
    func scrollTo(anchor: String)
    func currentScrollPosition() -> Double?
    func restoreScrollPosition(_ position: Double)
    func makePDF() async throws -> Data
    func printDocument() async throws
}

nonisolated enum MarkdownPreviewWebControllerError: LocalizedError, Equatable, Sendable {
    case unavailable
    case pdfCreationFailed
    case printFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The Markdown preview is not ready yet."
        case .pdfCreationFailed:
            "The PDF could not be created."
        case .printFailed:
            "The document could not be printed."
        }
    }
}

@MainActor
final class NoopMarkdownPreviewWebController: MarkdownPreviewWebControlling {
    func loadHTML(_ html: String, baseURL: URL?) {
        _ = (html, baseURL)
    }

    func find(_ query: String, options: MarkdownPreviewSearchOptions) {
        _ = (query, options)
    }

    func clearFind() {}

    func setSource(_ source: String, isVisible: Bool) {
        _ = (source, isVisible)
    }

    func setZoom(_ zoom: Double) {
        _ = zoom
    }

    func scrollTo(anchor: String) {
        _ = anchor
    }

    func currentScrollPosition() -> Double? {
        nil
    }

    func restoreScrollPosition(_ position: Double) {
        _ = position
    }

    func makePDF() async throws -> Data {
        throw MarkdownPreviewWebControllerError.unavailable
    }

    func printDocument() async throws {
        throw MarkdownPreviewWebControllerError.unavailable
    }
}

nonisolated struct MarkdownPreviewDocument: Equatable, Sendable {
    let source: MarkdownPreviewLoadedSource
    let rendered: MarkdownRenderedDocument
}

nonisolated enum MarkdownPreviewFailure: Equatable, Sendable {
    case file(MarkdownPreviewFileError)
    case unableToLoad

    var message: String {
        switch self {
        case .file(let error):
            error.localizedDescription
        case .unableToLoad:
            "The Markdown document could not be loaded."
        }
    }
}

nonisolated enum MarkdownPreviewLoadState: Equatable, Sendable {
    case empty
    case loading(filename: String)
    case loaded(MarkdownPreviewDocument)
    case failure(filename: String, MarkdownPreviewFailure)
}

nonisolated enum MarkdownPreviewDocumentActionState: Equatable, Sendable {
    case idle
    case preparingPDF
    case printing
}

enum MarkdownPreviewActionID {
    static let chooseDocument = CommandActionID(rawValue: "markdown-preview.choose")
    static let reload = CommandActionID(rawValue: "markdown-preview.reload")
    static let closeDocument = CommandActionID(rawValue: "markdown-preview.close")
    static let toggleSource = CommandActionID(rawValue: "markdown-preview.toggle-source")
    static let zoomIn = CommandActionID(rawValue: "markdown-preview.zoom-in")
    static let zoomOut = CommandActionID(rawValue: "markdown-preview.zoom-out")
    static let resetZoom = CommandActionID(rawValue: "markdown-preview.zoom-reset")
    static let toggleAutoReload = CommandActionID(rawValue: "markdown-preview.toggle-auto-reload")
    static let exportHTML = CommandActionID(rawValue: "markdown-preview.export-html")
    static let exportPDF = CommandActionID(rawValue: "markdown-preview.export-pdf")
    static let printDocument = CommandActionID(rawValue: "markdown-preview.print")
}

@Observable
@MainActor
final class MarkdownPreviewViewModel: LauncherApplicationModel {
    @ObservationIgnored private let loader: any MarkdownPreviewFileLoading
    @ObservationIgnored private let renderer: any MarkdownPreviewRendering
    @ObservationIgnored private let watcher: any MarkdownPreviewFileWatching
    @ObservationIgnored private let scrollStore: any MarkdownPreviewScrollStateStoring
    @ObservationIgnored private let webController: any MarkdownPreviewWebControlling
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var watcherTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var scrollTask: Task<Void, Never>?
    @ObservationIgnored private var scrollPersistenceTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var actionGeneration = 0
    @ObservationIgnored private var scopedResourceURL: URL?
    @ObservationIgnored private var retrySourceURL: URL?
    @ObservationIgnored private var hasSecurityScopedAccess = false
    @ObservationIgnored private var hasStopped = false

    private(set) var state: MarkdownPreviewLoadState = .empty
    private(set) var configuration: MarkdownPreviewConfiguration
    private(set) var selectedOutlineAnchor: String?
    private(set) var documentActionState: MarkdownPreviewDocumentActionState = .idle
    private(set) var htmlExportData: Data?
    private(set) var pdfExportData: Data?
    private(set) var statusMessage: String?

    var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            applySearch()
        }
    }
    var searchOptions = MarkdownPreviewSearchOptions() {
        didSet {
            guard searchOptions != oldValue else { return }
            applySearch()
        }
    }
    var showsSource: Bool {
        didSet {
            guard showsSource != oldValue, let document else { return }
            webController.setSource(document.source.markdown, isVisible: showsSource)
        }
    }
    var zoom: Double {
        didSet {
            let bounded = Self.boundedZoom(zoom)
            if bounded != zoom {
                zoom = bounded
                return
            }
            guard zoom != oldValue else { return }
            webController.setZoom(zoom)
        }
    }
    var autoReload: Bool
    var showsActionsMenu = false
    var presentsOwnActionsMenu: Bool { true }
    var showsDocumentPicker = false
    var showsHTMLExporter = false
    var showsPDFExporter = false

    init(
        loader: any MarkdownPreviewFileLoading,
        renderer: any MarkdownPreviewRendering,
        watcher: any MarkdownPreviewFileWatching,
        scrollStore: any MarkdownPreviewScrollStateStoring,
        configuration: MarkdownPreviewConfiguration = .default,
        webController: any MarkdownPreviewWebControlling,
        autoReload: Bool? = nil,
        onGoBack: @escaping () -> Void = {}
    ) {
        self.loader = loader
        self.renderer = renderer
        self.watcher = watcher
        self.scrollStore = scrollStore
        self.configuration = configuration.sanitized()
        self.webController = webController
        self.autoReload = autoReload ?? configuration.automaticallyReloads
        self.onGoBack = onGoBack
        self.showsSource = configuration.sourceViewMode == .source
        self.zoom = Self.boundedZoom(configuration.initialZoom)
    }

    convenience init(
        services: MarkdownPreviewApplicationServices,
        configuration: MarkdownPreviewConfiguration = .default,
        webController: any MarkdownPreviewWebControlling,
        autoReload: Bool? = nil,
        onGoBack: @escaping () -> Void = {}
    ) {
        self.init(
            loader: services.loader,
            renderer: services.renderer,
            watcher: services.watcher,
            scrollStore: services.scrollStore,
            configuration: configuration,
            webController: webController,
            autoReload: autoReload,
            onGoBack: onGoBack
        )
    }

    deinit {
        loadTask?.cancel()
        watcherTask?.cancel()
        actionTask?.cancel()
        if hasSecurityScopedAccess {
            scopedResourceURL?.stopAccessingSecurityScopedResource()
        }
    }

    var document: MarkdownPreviewDocument? {
        guard case .loaded(let document) = state else { return nil }
        return document
    }

    var outline: [MarkdownOutlineEntry] {
        document?.rendered.outline ?? []
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var suggestedHTMLFilename: String {
        suggestedFilename(extension: "html")
    }

    var suggestedPDFFilename: String {
        suggestedFilename(extension: "pdf")
    }

    var footerActions: [CommandActionDescriptor] {
        switch state {
        case .empty, .failure:
            return [
                CommandActionDescriptor(
                    id: MarkdownPreviewActionID.chooseDocument,
                    title: "Choose Markdown File",
                    isPrimary: true,
                    keyHint: .return
                )
            ]
        case .loading:
            return [
                CommandActionDescriptor(
                    id: MarkdownPreviewActionID.reload,
                    title: "Loading…",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: false
                )
            ]
        case .loaded:
            return [
                CommandActionDescriptor(
                    id: MarkdownPreviewActionID.reload,
                    title: "Reload",
                    isPrimary: true,
                    keyHint: CommandKeyHint(symbols: ["⌘", "R"]),
                    isEnabled: documentActionState == .idle
                ),
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.openActions,
                    title: "Actions",
                    keyHint: .commandK
                )
            ]
        }
    }

    var menuActions: [CommandActionDescriptor] {
        var actions = [
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.chooseDocument,
                title: document == nil ? "Choose Markdown File…" : "Choose Another File…",
                isEnabled: isLoading == false
            )
        ]
        guard document != nil else { return actions }
        actions.append(contentsOf: [
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.reload,
                title: "Reload",
                isEnabled: isLoading == false && documentActionState == .idle
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.toggleSource,
                title: showsSource ? "Show Rendered Preview" : "Show Source"
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.zoomIn,
                title: "Zoom In",
                isEnabled: zoom < MarkdownPreviewConfiguration.zoomRange.upperBound
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.zoomOut,
                title: "Zoom Out",
                isEnabled: zoom > MarkdownPreviewConfiguration.zoomRange.lowerBound
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.resetZoom,
                title: "Actual Size",
                isEnabled: zoom != 1
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.toggleAutoReload,
                title: autoReload ? "Disable Automatic Reload" : "Enable Automatic Reload"
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.exportHTML,
                title: "Export HTML…",
                isEnabled: documentActionState == .idle
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.exportPDF,
                title: documentActionState == .preparingPDF ? "Preparing PDF…" : "Export PDF…",
                isEnabled: documentActionState == .idle
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.printDocument,
                title: documentActionState == .printing ? "Opening Print…" : "Print…",
                isEnabled: documentActionState == .idle
            ),
            CommandActionDescriptor(
                id: MarkdownPreviewActionID.closeDocument,
                title: "Close Document",
                isEnabled: documentActionState == .idle
            ),
        ])
        return actions
    }

    func chooseDocument() {
        guard isLoading == false else { return }
        showsDocumentPicker = true
    }

    @discardableResult
    func openDroppedURLs(_ urls: [URL]) -> Bool {
        guard let sourceURL = urls.first(where: {
            MarkdownPreviewFileTypes.supports(fileExtension: $0.pathExtension)
        }) else {
            statusMessage = "Drop a supported Markdown file."
            return false
        }
        open(sourceURL)
        return true
    }

    func open(_ sourceURL: URL) {
        hasStopped = false
        showsDocumentPicker = false
        retrySourceURL = sourceURL
        replaceSecurityScopedResource(with: sourceURL)
        beginLoad(from: sourceURL)
    }

    func reload() {
        guard let sourceURL = scopedResourceURL ?? document?.source.sourceURL ?? retrySourceURL else { return }
        if scopedResourceURL == nil {
            replaceSecurityScopedResource(with: sourceURL)
        }
        beginLoad(from: sourceURL)
    }

    func closeDocument() {
        let sourceURL = document?.source.sourceURL
        let scrollPosition = configuration.remembersScrollPosition
            ? webController.currentScrollPosition()
            : nil
        invalidateCurrentWork()
        releaseSecurityScopedResource()
        retrySourceURL = nil
        resetPresentation(clearWebContent: false)
        persistScrollPositionAndClearWebContent(scrollPosition, for: sourceURL)
    }

    func setConfiguration(_ configuration: MarkdownPreviewConfiguration) {
        let sanitized = configuration.sanitized()
        guard sanitized != self.configuration else { return }
        self.configuration = sanitized
        autoReload = sanitized.automaticallyReloads
        zoom = sanitized.initialZoom
        showsSource = sanitized.sourceViewMode == .source
        reload()
    }

    func setAutoReload(_ enabled: Bool) {
        guard autoReload != enabled else { return }
        autoReload = enabled
        statusMessage = enabled ? "Automatic reload enabled." : "Automatic reload disabled."
    }

    func toggleSource() {
        guard document != nil else { return }
        showsSource.toggle()
    }

    func setZoom(_ value: Double) {
        zoom = value
    }

    func zoomIn() {
        setZoom(zoom + 0.1)
    }

    func zoomOut() {
        setZoom(zoom - 0.1)
    }

    func resetZoom() {
        setZoom(1)
    }

    func selectOutlineEntry(_ entry: MarkdownOutlineEntry) {
        guard outline.contains(entry) else { return }
        selectedOutlineAnchor = entry.anchor
        webController.scrollTo(anchor: entry.anchor)
    }

    func findNext() {
        repeatSearch(backwards: false)
    }

    func findPrevious() {
        repeatSearch(backwards: true)
    }

    func requestHTMLExport() {
        guard let document, documentActionState == .idle else { return }
        htmlExportData = Data(document.rendered.html.utf8)
        showsHTMLExporter = true
        statusMessage = "Choose where to save the self-contained HTML file."
    }

    func requestPDFExport() {
        guard document != nil, documentActionState == .idle else { return }
        beginDocumentAction(.preparingPDF)
        let generation = actionGeneration
        actionTask = Task { [weak self, webController] in
            do {
                let data = try await webController.makePDF()
                try Task.checkCancellation()
                guard let self, generation == self.actionGeneration else { return }
                self.pdfExportData = data
                self.showsPDFExporter = true
                self.documentActionState = .idle
                self.statusMessage = "Choose where to save the PDF."
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.actionGeneration else { return }
                self.documentActionState = .idle
                self.statusMessage = "The PDF could not be created. Try again after the preview loads."
            }
        }
    }

    func requestPrint() {
        guard document != nil, documentActionState == .idle else { return }
        beginDocumentAction(.printing)
        let generation = actionGeneration
        actionTask = Task { [weak self, webController] in
            do {
                try await webController.printDocument()
                try Task.checkCancellation()
                guard let self, generation == self.actionGeneration else { return }
                self.documentActionState = .idle
                self.statusMessage = "The document was sent to the print panel."
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.actionGeneration else { return }
                self.documentActionState = .idle
                self.statusMessage = "The print panel could not be opened."
            }
        }
    }

    func completeHTMLExport(_ result: Result<URL, Error>) {
        showsHTMLExporter = false
        htmlExportData = nil
        completeExport(result, successMessage: "HTML exported.")
    }

    func completePDFExport(_ result: Result<URL, Error>) {
        showsPDFExporter = false
        pdfExportData = nil
        completeExport(result, successMessage: "PDF exported.")
    }

    func moveSelection(offset: Int) {
        guard outline.isEmpty == false, offset != 0 else { return }
        let currentIndex = selectedOutlineAnchor.flatMap { anchor in
            outline.firstIndex(where: { $0.anchor == anchor })
        }
        let startIndex = currentIndex ?? (offset > 0 ? outline.count - 1 : 0)
        let nextIndex = (startIndex + offset % outline.count + outline.count) % outline.count
        selectOutlineEntry(outline[nextIndex])
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case MarkdownPreviewActionID.chooseDocument:
            chooseDocument()
        case MarkdownPreviewActionID.reload:
            reload()
        case MarkdownPreviewActionID.closeDocument:
            closeDocument()
        case MarkdownPreviewActionID.toggleSource:
            toggleSource()
        case MarkdownPreviewActionID.zoomIn:
            zoomIn()
        case MarkdownPreviewActionID.zoomOut:
            zoomOut()
        case MarkdownPreviewActionID.resetZoom:
            resetZoom()
        case MarkdownPreviewActionID.toggleAutoReload:
            setAutoReload(autoReload == false)
        case MarkdownPreviewActionID.exportHTML:
            requestHTMLExport()
        case MarkdownPreviewActionID.exportPDF:
            requestPDFExport()
        case MarkdownPreviewActionID.printDocument:
            requestPrint()
        case BuiltInCommandActionID.openActions:
            showsActionsMenu = true
        case BuiltInCommandActionID.goBack:
            goBack()
        default:
            break
        }
    }

    func handleEscape() -> Bool {
        if searchQuery.isEmpty == false {
            searchQuery = ""
            return true
        }
        if showsSource {
            showsSource = false
            return true
        }
        return false
    }

    func goBack() {
        onGoBack()
    }

    func stop() {
        guard hasStopped == false else { return }
        hasStopped = true
        let sourceURL = document?.source.sourceURL
        let scrollPosition = configuration.remembersScrollPosition
            ? webController.currentScrollPosition()
            : nil
        invalidateCurrentWork()
        releaseSecurityScopedResource()
        retrySourceURL = nil
        resetPresentation(clearWebContent: false)
        persistScrollPositionAndClearWebContent(scrollPosition, for: sourceURL)
    }

    func waitForLoadForTesting() async {
        await loadTask?.value
    }

    func waitForActionForTesting() async {
        await actionTask?.value
    }

    func waitForScrollStateForTesting() async {
        await scrollTask?.value
        await scrollPersistenceTask?.value
    }

    private func beginLoad(from sourceURL: URL) {
        let previousSourceURL = document?.source.sourceURL
        let previousScrollPosition = configuration.remembersScrollPosition
            ? webController.currentScrollPosition()
            : nil
        retrySourceURL = sourceURL
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        watcherTask?.cancel()
        actionTask?.cancel()
        scrollTask?.cancel()
        actionGeneration += 1
        documentActionState = .idle
        selectedOutlineAnchor = nil
        state = .loading(filename: sourceURL.lastPathComponent)
        statusMessage = "Loading Markdown locally…"

        loadTask = Task {
            [weak self, loader, renderer, scrollStore] in
            do {
                if self?.configuration.remembersScrollPosition == true,
                   let previousSourceURL,
                   let position = previousScrollPosition {
                    try Task.checkCancellation()
                    await scrollStore.setScrollPosition(position, for: previousSourceURL)
                }
                let source = try await loader.load(from: sourceURL)
                try Task.checkCancellation()
                guard let self, generation == self.loadGeneration else { return }
                let rendered = await renderer.render(
                    source: source,
                    configuration: self.configuration
                )
                try Task.checkCancellation()
                guard generation == self.loadGeneration else { return }

                let document = MarkdownPreviewDocument(source: source, rendered: rendered)
                self.state = .loaded(document)
                self.statusMessage = source.warnings.isEmpty
                    ? "Markdown preview ready."
                    : "Preview ready with local-image safety warnings."
                self.webController.loadHTML(
                    rendered.html,
                    baseURL: source.sourceURL.deletingLastPathComponent()
                )
                self.webController.setSource(source.markdown, isVisible: self.showsSource)
                self.webController.setZoom(self.zoom)
                self.applySearch()
                self.restoreScrollPosition(for: source.sourceURL, generation: generation)
                self.startWatching(source.sourceURL, generation: generation)
            } catch is CancellationError {
                return
            } catch let error as MarkdownPreviewFileError {
                guard let self, generation == self.loadGeneration else { return }
                self.state = .failure(
                    filename: sourceURL.lastPathComponent,
                    .file(error)
                )
                self.statusMessage = error.localizedDescription
                self.releaseSecurityScopedResource()
            } catch {
                guard let self, generation == self.loadGeneration else { return }
                self.state = .failure(
                    filename: sourceURL.lastPathComponent,
                    .unableToLoad
                )
                self.statusMessage = MarkdownPreviewFailure.unableToLoad.message
                self.releaseSecurityScopedResource()
            }
        }
    }

    private func startWatching(_ sourceURL: URL, generation: Int) {
        watcherTask?.cancel()
        watcherTask = Task { [weak self, watcher] in
            do {
                let changes = try await watcher.changes(for: sourceURL)
                for await change in changes {
                    try Task.checkCancellation()
                    guard let self,
                          generation == self.loadGeneration,
                          self.autoReload else {
                        continue
                    }
                    if change == .replacedOrRemoved {
                        self.statusMessage = "The file was removed. Waiting for it to reappear…"
                        continue
                    }
                    self.reload()
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.loadGeneration else { return }
                self.statusMessage = "Preview ready, but automatic reload is unavailable."
            }
        }
    }

    private func restoreScrollPosition(for sourceURL: URL, generation: Int) {
        guard configuration.remembersScrollPosition else { return }
        scrollTask?.cancel()
        scrollTask = Task { [weak self, scrollStore] in
            guard let position = await scrollStore.scrollPosition(for: sourceURL),
                  Task.isCancelled == false,
                  let self,
                  generation == self.loadGeneration else {
                return
            }
            self.webController.restoreScrollPosition(position)
        }
    }

    private func persistScrollPositionAndClearWebContent(
        _ position: Double?,
        for sourceURL: URL?
    ) {
        webController.loadHTML("", baseURL: nil)
        guard configuration.remembersScrollPosition,
              let sourceURL,
              let position else { return }
        scrollPersistenceTask = Task { [scrollStore] in
            await scrollStore.setScrollPosition(position, for: sourceURL)
        }
    }

    private func applySearch() {
        guard document != nil else { return }
        let normalized = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            webController.clearFind()
        } else {
            webController.find(normalized, options: searchOptions)
        }
    }

    private func repeatSearch(backwards: Bool) {
        guard document != nil else { return }
        let normalized = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            webController.clearFind()
            return
        }
        var options = searchOptions
        options.searchesBackwards = backwards
        webController.find(normalized, options: options)
    }

    private func beginDocumentAction(_ state: MarkdownPreviewDocumentActionState) {
        actionGeneration += 1
        actionTask?.cancel()
        documentActionState = state
    }

    private func completeExport(_ result: Result<URL, Error>, successMessage: String) {
        switch result {
        case .success:
            statusMessage = successMessage
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else {
                statusMessage = document == nil ? nil : "Markdown preview ready."
                return
            }
            statusMessage = "The export could not be saved. Choose another location and try again."
        }
    }

    private func suggestedFilename(extension pathExtension: String) -> String {
        let filename = document?.source.displayName ?? "Markdown Preview"
        let stem = (filename as NSString).deletingPathExtension
        return "\(stem.isEmpty ? "Markdown Preview" : stem).\(pathExtension)"
    }

    private func replaceSecurityScopedResource(with sourceURL: URL) {
        releaseSecurityScopedResource()
        scopedResourceURL = sourceURL
        hasSecurityScopedAccess = sourceURL.startAccessingSecurityScopedResource()
    }

    private func releaseSecurityScopedResource() {
        if hasSecurityScopedAccess {
            scopedResourceURL?.stopAccessingSecurityScopedResource()
        }
        hasSecurityScopedAccess = false
        scopedResourceURL = nil
    }

    private func invalidateCurrentWork() {
        loadGeneration += 1
        actionGeneration += 1
        loadTask?.cancel()
        watcherTask?.cancel()
        actionTask?.cancel()
        scrollTask?.cancel()
        loadTask = nil
        watcherTask = nil
        actionTask = nil
        scrollTask = nil
    }

    private func resetPresentation(clearWebContent: Bool = true) {
        state = .empty
        selectedOutlineAnchor = nil
        documentActionState = .idle
        searchQuery = ""
        htmlExportData = nil
        pdfExportData = nil
        showsDocumentPicker = false
        showsHTMLExporter = false
        showsPDFExporter = false
        showsActionsMenu = false
        statusMessage = nil
        webController.clearFind()
        webController.setSource("", isVisible: false)
        if clearWebContent {
            webController.loadHTML("", baseURL: nil)
        }
    }

    private static func boundedZoom(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(
            max(value, MarkdownPreviewConfiguration.zoomRange.lowerBound),
            MarkdownPreviewConfiguration.zoomRange.upperBound
        )
    }
}
