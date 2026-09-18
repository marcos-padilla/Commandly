import CommandKit
import Foundation
import Infrastructure
import Observation

nonisolated struct LogoFilterOption: Identifiable, Equatable, Sendable {
    static let allID = "all"
    static let favoritesID = "favorites"
    static let categoryPrefix = "category:"

    let id: String
    let title: String
    let count: Int

    static func category(_ category: String, count: Int) -> LogoFilterOption {
        LogoFilterOption(
            id: categoryPrefix + category,
            title: category,
            count: count
        )
    }
}

enum LogosActionID {
    static let copySVG = CommandActionID(rawValue: "logos.copy-svg")
    static let copyURL = CommandActionID(rawValue: "logos.copy-url")
    static let download = CommandActionID(rawValue: "logos.download")
    static let toggleFavorite = CommandActionID(rawValue: "logos.toggle-favorite")
    static let refresh = CommandActionID(rawValue: "logos.refresh")
}

enum LogosLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(SVGLServiceError)
}

private enum LogoAssetOperation: Sendable {
    case copySVG
    case copyURL
    case download
}

@Observable
@MainActor
final class LogosViewModel: LauncherApplicationModel {
    @ObservationIgnored let artworkService: any SVGLServicing
    @ObservationIgnored private let favoritesStore: any LogoFavoritesStoring
    @ObservationIgnored private let pasteboard: any PasteboardAccessing
    @ObservationIgnored private let exporter: any LogoFileExporting
    @ObservationIgnored private let onGoBack: () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var favoriteTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var operationGeneration = 0

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            resolveSelection()
        }
    }
    var filterID = LogoFilterOption.allID {
        didSet {
            guard filterID != oldValue else { return }
            resolveSelection()
        }
    }
    var variant: LogoVariant = .light
    var showsActionsMenu = false
    private(set) var logos: [LogoAsset] = []
    private(set) var favoriteIDs: Set<Int> = []
    private(set) var selectedID: Int?
    private(set) var loadState: LogosLoadState = .idle
    private(set) var isPerformingAction = false
    private(set) var shouldScrollToSelection = false
    private(set) var categoryFilterOptions: [LogoFilterOption] = []
    var statusMessage: String?

    init(
        service: any SVGLServicing,
        favoritesStore: any LogoFavoritesStoring,
        pasteboard: any PasteboardAccessing,
        exporter: any LogoFileExporting,
        onGoBack: @escaping () -> Void = {}
    ) {
        self.artworkService = service
        self.favoritesStore = favoritesStore
        self.pasteboard = pasteboard
        self.exporter = exporter
        self.onGoBack = onGoBack
    }

    deinit {
        loadTask?.cancel()
        operationTask?.cancel()
        favoriteTask?.cancel()
    }

    var filterOptions: [LogoFilterOption] {
        return [
            LogoFilterOption(id: LogoFilterOption.allID, title: "All Logos", count: logos.count),
            LogoFilterOption(
                id: LogoFilterOption.favoritesID,
                title: "Favorites",
                count: favoriteIDs.count
            )
        ] + categoryFilterOptions
    }

    var activeFilterTitle: String {
        filterOptions.first(where: { $0.id == filterID })?.title ?? "All Logos"
    }

    var filteredLogos: [LogoAsset] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return logos.filter { logo in
            let matchesFilter: Bool
            if filterID == LogoFilterOption.favoritesID {
                matchesFilter = favoriteIDs.contains(logo.id)
            } else if filterID.hasPrefix(LogoFilterOption.categoryPrefix) {
                let category = String(filterID.dropFirst(LogoFilterOption.categoryPrefix.count))
                matchesFilter = logo.categories.contains {
                    $0.caseInsensitiveCompare(category) == .orderedSame
                }
            } else {
                matchesFilter = true
            }
            guard matchesFilter else { return false }
            guard needle.isEmpty == false else { return true }
            return logo.title.localizedCaseInsensitiveContains(needle)
                || logo.categories.contains {
                    $0.localizedCaseInsensitiveContains(needle)
                }
        }
    }

    var selectedLogo: LogoAsset? {
        filteredLogos.first(where: { $0.id == selectedID }) ?? filteredLogos.first
    }

    var selectedAssetURL: URL? {
        selectedLogo?.routes.url(for: variant)
    }

    var footerActions: [CommandActionDescriptor] {
        guard selectedLogo != nil else {
            return [
                CommandActionDescriptor(
                    id: LogosActionID.refresh,
                    title: loadState == .loading ? "Refreshing…" : "Refresh",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: loadState != .loading
                )
            ]
        }
        return [
            CommandActionDescriptor(
                id: LogosActionID.copySVG,
                title: "Copy SVG",
                isPrimary: true,
                keyHint: .return,
                isEnabled: isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: LogosActionID.download,
                title: "Download",
                isEnabled: isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK,
                isEnabled: isPerformingAction == false
            )
        ]
    }

    var menuActions: [CommandActionDescriptor] {
        guard let selectedLogo else {
            return [
                CommandActionDescriptor(
                    id: LogosActionID.refresh,
                    title: "Refresh Catalog",
                    isEnabled: loadState != .loading
                )
            ]
        }
        return [
            CommandActionDescriptor(
                id: LogosActionID.copySVG,
                title: "Copy SVG",
                isEnabled: isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: LogosActionID.copyURL,
                title: "Copy SVG URL",
                isEnabled: isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: LogosActionID.download,
                title: "Download SVG…",
                isEnabled: isPerformingAction == false
            ),
            CommandActionDescriptor(
                id: LogosActionID.toggleFavorite,
                title: favoriteIDs.contains(selectedLogo.id)
                    ? "Remove from Favorites"
                    : "Add to Favorites"
            ),
            CommandActionDescriptor(
                id: LogosActionID.refresh,
                title: "Refresh Catalog",
                isEnabled: loadState != .loading && isPerformingAction == false
            )
        ]
    }

    func load(forceRefresh: Bool = false) {
        guard forceRefresh || loadState == .idle || loadState.isFailure else { return }
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadState = .loading
        statusMessage = nil

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                async let catalog = artworkService.catalog(forceRefresh: forceRefresh)
                async let storedFavorites = favoritesStore.favoriteIDs()
                let (loadedLogos, loadedFavorites) = try await (catalog, storedFavorites)
                guard Task.isCancelled == false, loadGeneration == generation else { return }
                logos = loadedLogos
                favoriteIDs = loadedFavorites.intersection(Set(loadedLogos.map(\.id)))
                categoryFilterOptions = Self.makeCategoryFilterOptions(from: loadedLogos)
                loadState = loadedLogos.isEmpty ? .empty : .loaded
                resolveSelection()
                if forceRefresh {
                    statusMessage = "Logo catalog refreshed."
                }
            } catch is CancellationError {
                guard loadGeneration == generation else { return }
                loadState = logos.isEmpty ? .idle : .loaded
            } catch let error as SVGLServiceError {
                guard loadGeneration == generation else { return }
                loadState = .failed(error)
                statusMessage = error.errorDescription
            } catch {
                guard loadGeneration == generation else { return }
                loadState = .failed(.catalogUnavailable)
                statusMessage = SVGLServiceError.catalogUnavailable.errorDescription
            }
        }
    }

    func select(_ id: Int) {
        guard filteredLogos.contains(where: { $0.id == id }) else { return }
        selectedID = id
        shouldScrollToSelection = false
        statusMessage = nil
        showsActionsMenu = false
    }

    func moveSelection(offset: Int) {
        guard let nextID = LauncherListSelection.nextID(
            in: filteredLogos,
            selectedID: selectedID,
            offset: offset,
            id: \.id
        ) else { return }
        selectedID = nextID
        shouldScrollToSelection = true
        statusMessage = nil
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case LogosActionID.copySVG:
            begin(.copySVG)
        case LogosActionID.copyURL:
            begin(.copyURL)
        case LogosActionID.download:
            begin(.download)
        case LogosActionID.toggleFavorite:
            toggleFavorite()
        case LogosActionID.refresh:
            load(forceRefresh: true)
        case BuiltInCommandActionID.openActions:
            showsActionsMenu = true
        case BuiltInCommandActionID.goBack:
            goBack()
        default:
            break
        }
    }

    func handleEscape() -> Bool {
        if query.isEmpty == false {
            query = ""
            return true
        }
        if filterID != LogoFilterOption.allID {
            filterID = LogoFilterOption.allID
            return true
        }
        return false
    }

    func goBack() {
        onGoBack()
    }

    func stop() {
        loadGeneration += 1
        operationGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        operationTask?.cancel()
        operationTask = nil
        favoriteTask?.cancel()
        favoriteTask = nil
        isPerformingAction = false
    }

    func waitForLoadForTesting() async {
        await loadTask?.value
    }

    func waitForOperationForTesting() async {
        await operationTask?.value
        await favoriteTask?.value
    }

    private func resolveSelection() {
        selectedID = LauncherListSelection.resolvedID(
            in: filteredLogos,
            selectedID: selectedID,
            id: \.id
        )
        shouldScrollToSelection = true
    }

    private func toggleFavorite() {
        guard let logo = selectedLogo else { return }
        let isFavorite = favoriteIDs.contains(logo.id) == false
        if isFavorite {
            favoriteIDs.insert(logo.id)
        } else {
            favoriteIDs.remove(logo.id)
        }
        resolveSelection()
        statusMessage = isFavorite ? "Added to favorites." : "Removed from favorites."
        favoriteTask?.cancel()
        favoriteTask = Task { [favoritesStore] in
            await favoritesStore.setFavorite(isFavorite, id: logo.id)
        }
    }

    private func begin(_ operation: LogoAssetOperation) {
        guard let logo = selectedLogo,
              let url = logo.routes.url(for: variant) else {
            statusMessage = SVGLServiceError.invalidAssetURL.errorDescription
            return
        }
        operationGeneration += 1
        let generation = operationGeneration
        operationTask?.cancel()
        isPerformingAction = true
        showsActionsMenu = false
        statusMessage = nil

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch operation {
                case .copyURL:
                    await pasteboard.writeString(url.absoluteString)
                    try Task.checkCancellation()
                    guard operationGeneration == generation else { return }
                    statusMessage = "SVG URL copied."
                case .copySVG:
                    let data = try await artworkService.svgData(from: url)
                    try Task.checkCancellation()
                    guard let source = String(data: data, encoding: .utf8) else {
                        throw SVGLServiceError.invalidSVG
                    }
                    await pasteboard.writeString(source)
                    try Task.checkCancellation()
                    guard operationGeneration == generation else { return }
                    statusMessage = "SVG copied."
                case .download:
                    let data = try await artworkService.svgData(from: url)
                    try Task.checkCancellation()
                    let didExport = try await exporter.export(
                        svg: data,
                        suggestedFileName: fileName(for: logo)
                    )
                    try Task.checkCancellation()
                    guard operationGeneration == generation else { return }
                    statusMessage = didExport ? "SVG downloaded." : "Download cancelled."
                }
                isPerformingAction = false
            } catch is CancellationError {
                guard operationGeneration == generation else { return }
                isPerformingAction = false
            } catch let error as LocalizedError {
                guard operationGeneration == generation else { return }
                isPerformingAction = false
                statusMessage = error.errorDescription ?? "The logo action failed."
            } catch {
                guard operationGeneration == generation else { return }
                isPerformingAction = false
                statusMessage = "The logo action failed."
            }
        }
    }

    private func fileName(for logo: LogoAsset) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let base = logo.title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let safeBase = base.isEmpty ? "logo" : base
        let suffix = logo.routes.hasAppearanceVariants ? "-\(variant.rawValue)" : ""
        return safeBase + suffix + ".svg"
    }

    private static func makeCategoryFilterOptions(
        from logos: [LogoAsset]
    ) -> [LogoFilterOption] {
        let counts = logos.reduce(into: [String: Int]()) { result, logo in
            for category in logo.categories {
                result[category, default: 0] += 1
            }
        }
        return counts.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { LogoFilterOption.category($0, count: counts[$0] ?? 0) }
    }
}

private extension LogosLoadState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
