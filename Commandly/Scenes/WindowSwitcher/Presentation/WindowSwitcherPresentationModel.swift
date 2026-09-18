import AppKit
import CoreGraphics
import Foundation
import Infrastructure
import Observation

enum WindowSwitcherPresentationContext: Equatable, Sendable {
    case allWindows(frontmostProcessIdentifier: Int32?)
    case activeApplication(processIdentifier: Int32)
    case commandTab(frontmostProcessIdentifier: Int32?)
    case dock(processIdentifier: Int32, anchorFrame: CGRect)

    var restrictedProcessIdentifier: Int32? {
        switch self {
        case .activeApplication(let processIdentifier),
             .dock(let processIdentifier, _):
            return processIdentifier
        case .allWindows, .commandTab:
            return nil
        }
    }

    var frontmostProcessIdentifier: Int32? {
        switch self {
        case .allWindows(let processIdentifier), .commandTab(let processIdentifier):
            return processIdentifier
        case .activeApplication(let processIdentifier), .dock(let processIdentifier, _):
            return processIdentifier
        }
    }

    var isDockPreview: Bool {
        if case .dock = self { return true }
        return false
    }
}

enum WindowSwitcherLoadingPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case failed(String)
}

/// One display section used when the switcher's window set is grouped by application.
///
/// Grouping changes only presentation: every matching window remains independently selectable,
/// while keyboard traversal continues to use the flattened `visibleWindows` order.
struct WindowSwitcherApplicationGroup: Identifiable, Equatable, Sendable {
    let id: String
    let applicationName: String
    let processIdentifier: Int32
    var windows: [WindowSnapshot]
}

/// Ephemeral presentation state for one switcher session.
///
/// Window titles, search text, and thumbnails are cleared when the surface closes. The model never
/// logs or persists these values.
@Observable
@MainActor
final class WindowSwitcherPresentationModel {
    let configuration: WindowSwitcherConfiguration
    let context: WindowSwitcherPresentationContext

    private(set) var phase: WindowSwitcherLoadingPhase = .idle
    private(set) var windows: [WindowSnapshot] = []
    private(set) var selectedID: WindowID?
    private(set) var thumbnails: [WindowID: CGImage] = [:]
    private(set) var statusMessage: String?
    var query = ""
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            onPinChanged(isPinned)
        }
    }

    @ObservationIgnored
    private let queryService: any WindowQuerying
    @ObservationIgnored
    private let controlService: any WindowControlling
    @ObservationIgnored
    private let thumbnailService: any WindowThumbnailProviding
    @ObservationIgnored
    private var displayFrame: CGRect?
    @ObservationIgnored
    private let onRequestDismiss: (Bool) -> Void
    @ObservationIgnored
    private let onContentChanged: () -> Void
    @ObservationIgnored
    private let onPinChanged: (Bool) -> Void
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?
    @ObservationIgnored
    private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored
    private var livePreviewTask: Task<Void, Never>?
    @ObservationIgnored
    private var actionTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private let initialSelectionOffset: Int
    private var pendingSelectionOffset = 0
    private var activatesSelectionWhenReady = false
    private var hasCompletedInitialLoad = false

    init(
        configuration: WindowSwitcherConfiguration,
        context: WindowSwitcherPresentationContext,
        queryService: any WindowQuerying,
        controlService: any WindowControlling,
        thumbnailService: any WindowThumbnailProviding,
        displayFrame: CGRect?,
        initialSelectionOffset: Int,
        onRequestDismiss: @escaping (Bool) -> Void,
        onContentChanged: @escaping () -> Void = {},
        onPinChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.context = context
        self.queryService = queryService
        self.controlService = controlService
        self.thumbnailService = thumbnailService
        self.displayFrame = displayFrame
        self.initialSelectionOffset = initialSelectionOffset
        self.onRequestDismiss = onRequestDismiss
        self.onContentChanged = onContentChanged
        self.onPinChanged = onPinChanged
        thumbnailService.setMaximumEntryCount(configuration.thumbnailCacheLimit)
    }

    var visibleWindows: [WindowSnapshot] {
        Self.filteredAndSorted(
            windows,
            query: query,
            configuration: configuration,
            restrictedProcessIdentifier: context.restrictedProcessIdentifier
        )
    }

    var selectedWindow: WindowSnapshot? {
        visibleWindows.first(where: { $0.id == selectedID })
    }

    var applicationGroups: [WindowSwitcherApplicationGroup] {
        guard configuration.filterMode == .applications else { return [] }

        var groups: [WindowSwitcherApplicationGroup] = []
        var groupIndexByID: [String: Int] = [:]
        for window in visibleWindows {
            let groupID = window.bundleIdentifier.map { "bundle:\($0)" }
                ?? "process:\(window.processIdentifier)"
            if let index = groupIndexByID[groupID] {
                groups[index].windows.append(window)
            } else {
                groupIndexByID[groupID] = groups.count
                groups.append(WindowSwitcherApplicationGroup(
                    id: groupID,
                    applicationName: window.applicationName,
                    processIdentifier: window.processIdentifier,
                    windows: [window]
                ))
            }
        }
        return groups
    }

    var searchSummary: String {
        let count = visibleWindows.count
        return count == 1 ? "1 window" : "\(count) windows"
    }

    func load() {
        startLoad(preservingStatusMessage: false)
    }

    private func startLoad(preservingStatusMessage: Bool) {
        generation &+= 1
        let expectedGeneration = generation
        loadTask?.cancel()
        thumbnailTask?.cancel()
        livePreviewTask?.cancel()
        phase = .loading
        if preservingStatusMessage == false {
            statusMessage = nil
        }
        let options = makeQueryOptions()

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshots = try await queryService.windows(options: options)
                try Task.checkCancellation()
                guard expectedGeneration == generation else { return }
                windows = snapshots
                let initialOffset = hasCompletedInitialLoad ? 0 : initialSelectionOffset
                repairSelection(offset: initialOffset + pendingSelectionOffset)
                pendingSelectionOffset = 0
                hasCompletedInitialLoad = true
                phase = visibleWindows.isEmpty ? .empty : .ready
                pruneThumbnails()
                onContentChanged()
                guard expectedGeneration == generation else { return }
                if activatesSelectionWhenReady, selectedWindow != nil {
                    activatesSelectionWhenReady = false
                    activateSelection()
                    return
                }
                beginThumbnailLoading(generation: expectedGeneration)
            } catch is CancellationError {
                return
            } catch {
                guard expectedGeneration == generation else { return }
                windows = []
                selectedID = nil
                phase = .failed(
                    "Window access is unavailable. Grant Accessibility access in Settings."
                )
                onContentChanged()
            }
        }
    }

    func refresh(preservingStatusMessage: Bool = true) {
        let preservedSelection = selectedID
        startLoad(preservingStatusMessage: preservingStatusMessage)
        if let preservedSelection { selectedID = preservedSelection }
    }

    /// Updates the display used by the current-display filter after active-window placement is
    /// resolved from the first public-API query.
    func updateDisplayFrame(
        _ frame: CGRect?,
        refreshesWindowSet: Bool
    ) {
        guard Self.equalFrames(displayFrame, frame) == false else { return }
        displayFrame = frame
        if refreshesWindowSet {
            refresh(preservingStatusMessage: true)
        }
    }

    func moveSelection(offset: Int) {
        let items = visibleWindows
        guard items.isEmpty == false else {
            if phase == .loading {
                pendingSelectionOffset += offset
            }
            return
        }
        let index = selectedID.flatMap { selectedID in
            items.firstIndex(where: { $0.id == selectedID })
        } ?? 0
        selectedID = items[(index + offset + items.count) % items.count].id
        statusMessage = nil
    }

    func select(_ id: WindowID) {
        guard visibleWindows.contains(where: { $0.id == id }) else { return }
        selectedID = id
        statusMessage = nil
    }

    func setQuery(_ value: String) {
        guard configuration.allowsSearch else { return }
        query = value
        repairSelection(offset: 0)
        onContentChanged()
    }

    func appendSearchText(_ value: String) {
        guard configuration.allowsSearch, value.isEmpty == false else { return }
        setQuery(query + value)
    }

    func deleteSearchBackward() {
        guard query.isEmpty == false else { return }
        query.removeLast()
        repairSelection(offset: 0)
        onContentChanged()
    }

    func clearSearch() {
        guard query.isEmpty == false else { return }
        query = ""
        repairSelection(offset: 0)
        onContentChanged()
    }

    func activateSelection() {
        perform(.activate, dismissAfterSuccess: true)
    }

    /// Activates immediately when discovery is ready, or remembers a modifier-release commit that
    /// arrived while the first cancellable query was still in flight.
    func activateSelectionOrDefer() -> Bool {
        if selectedWindow != nil {
            activateSelection()
            return true
        }
        guard phase == .loading else { return false }
        activatesSelectionWhenReady = true
        return true
    }

    func perform(_ action: WindowAction, dismissAfterSuccess: Bool = false) {
        guard let window = selectedWindow else { return }
        statusMessage = nil
        let selectedID = window.id
        let expectedGeneration = generation
        actionTask?.cancel()
        actionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await controlService.perform(action, on: selectedID)
                try Task.checkCancellation()
                guard expectedGeneration == generation else { return }
                if dismissAfterSuccess {
                    onRequestDismiss(true)
                    return
                }
                statusMessage = Self.completionMessage(for: action)
                refresh(preservingStatusMessage: true)
            } catch is CancellationError {
                return
            } catch {
                guard expectedGeneration == generation else { return }
                statusMessage = Self.failureMessage(for: action)
            }
        }
    }

    func cancel() {
        onRequestDismiss(false)
    }

    func stop() {
        generation &+= 1
        let releasedWindowIDs = Set(windows.map(\.id))
        loadTask?.cancel()
        thumbnailTask?.cancel()
        livePreviewTask?.cancel()
        actionTask?.cancel()
        loadTask = nil
        thumbnailTask = nil
        livePreviewTask = nil
        actionTask = nil
        thumbnailService.clear()
        thumbnails.removeAll(keepingCapacity: false)
        windows.removeAll(keepingCapacity: false)
        selectedID = nil
        query = ""
        statusMessage = nil
        pendingSelectionOffset = 0
        activatesSelectionWhenReady = false
        phase = .idle
        if releasedWindowIDs.isEmpty == false,
           let sessionReleaser = queryService as? any WindowSessionReleasing {
            Task {
                await sessionReleaser.releaseWindowSession(windowIDs: releasedWindowIDs)
            }
        }
    }

    func clearThumbnails() {
        thumbnailTask?.cancel()
        livePreviewTask?.cancel()
        thumbnailTask = nil
        livePreviewTask = nil
        thumbnailService.clear()
        thumbnails.removeAll(keepingCapacity: false)
    }

    private func repairSelection(offset: Int) {
        let items = visibleWindows
        guard items.isEmpty == false else {
            selectedID = nil
            return
        }
        if let selectedID, items.contains(where: { $0.id == selectedID }) {
            return
        }
        let focusedIndex = items.firstIndex(where: \.isFocused) ?? 0
        let normalizedOffset = offset % items.count
        selectedID = items[(focusedIndex + normalizedOffset + items.count) % items.count].id
    }

    private func beginThumbnailLoading(generation expectedGeneration: UInt64) {
        guard configuration.showsThumbnails, thumbnailRequestLimit > 0 else {
            clearThumbnails()
            return
        }
        let requestedWindows = thumbnailCandidateWindows
        thumbnailTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await thumbnailService.hasCaptureAuthorization() else {
                clearThumbnails()
                return
            }
            for window in requestedWindows {
                guard Task.isCancelled == false,
                      expectedGeneration == generation else {
                    return
                }
                if let image = await thumbnailService.thumbnail(
                    for: window,
                    maximumSize: thumbnailMaximumSize,
                    quality: nativeThumbnailQuality,
                    cacheLifetime: 30,
                    forceRefresh: false
                ) {
                    guard expectedGeneration == generation else { return }
                    thumbnails[window.id] = image
                    pruneThumbnails()
                } else if await thumbnailService.hasCaptureAuthorization() == false {
                    clearThumbnails()
                    return
                }
            }
            beginLivePreviewRefresh(generation: expectedGeneration)
        }
    }

    private func beginLivePreviewRefresh(generation expectedGeneration: UInt64) {
        guard configuration.usesLivePreviews,
              configuration.showsThumbnails else {
            return
        }
        livePreviewTask?.cancel()
        livePreviewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            while Task.isCancelled == false, expectedGeneration == generation {
                do {
                    try await clock.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                guard await thumbnailService.hasCaptureAuthorization() else {
                    clearThumbnails()
                    return
                }
                guard let selectedWindow,
                      let image = await thumbnailService.thumbnail(
                          for: selectedWindow,
                          maximumSize: thumbnailMaximumSize,
                          quality: nativeThumbnailQuality,
                          cacheLifetime: 0,
                          forceRefresh: true
                      ), expectedGeneration == generation else {
                    continue
                }
                thumbnails[selectedWindow.id] = image
                pruneThumbnails()
            }
        }
    }

    private var thumbnailRequestLimit: Int {
        min(24, max(0, configuration.thumbnailCacheLimit))
    }

    private var thumbnailCandidateWindows: [WindowSnapshot] {
        guard thumbnailRequestLimit > 0 else { return [] }
        var candidates: [WindowSnapshot] = []
        if let selectedWindow {
            candidates.append(selectedWindow)
        }
        for window in visibleWindows where candidates.contains(where: { $0.id == window.id }) == false {
            guard candidates.count < thumbnailRequestLimit else { break }
            candidates.append(window)
        }
        return candidates
    }

    private func pruneThumbnails() {
        let retainedIDs = Set(thumbnailCandidateWindows.map(\.id))
        let staleIDs = thumbnails.keys.filter { retainedIDs.contains($0) == false }
        for id in staleIDs {
            thumbnails[id] = nil
        }
    }

    private var thumbnailMaximumSize: CGSize {
        switch configuration.itemSize {
        case .compact: return CGSize(width: 210, height: 132)
        case .regular: return CGSize(width: 280, height: 176)
        case .large: return CGSize(width: 360, height: 226)
        }
    }

    private var nativeThumbnailQuality: WindowThumbnailQuality {
        switch configuration.thumbnailQuality {
        case .efficient: return .efficient
        case .balanced: return .balanced
        case .detailed: return .sharp
        }
    }

    private func makeQueryOptions() -> WindowQueryOptions {
        let bundleIdentifiers = Set(configuration.exclusionTerms.filter {
            $0.contains(".") && $0.contains(" ") == false
        })
        return WindowQueryOptions(
            includeMinimized: configuration.includesMinimizedWindows,
            includeHidden: configuration.includesHiddenApplications,
            includeWindowless: configuration.includesWindowlessApplications,
            currentDesktopOnly: configuration.limitsToCurrentDesktop,
            currentDisplayFrame: configuration.limitsToCurrentDisplay ? displayFrame : nil,
            excludedBundleIdentifiers: bundleIdentifiers,
            excludedTitleTerms: configuration.exclusionTerms
        )
    }

    static func filteredAndSorted(
        _ windows: [WindowSnapshot],
        query: String,
        configuration: WindowSwitcherConfiguration,
        restrictedProcessIdentifier: Int32?
    ) -> [WindowSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let excludedBundleIdentifiers = Set(configuration.exclusionTerms.filter {
            $0.contains(".") && $0.contains(" ") == false
        })
        let filtered = windows.filter { window in
            if let restrictedProcessIdentifier,
               window.processIdentifier != restrictedProcessIdentifier {
                return false
            }
            if let bundleIdentifier = window.bundleIdentifier,
               excludedBundleIdentifiers.contains(bundleIdentifier) {
                return false
            }
            if configuration.exclusionTerms.contains(where: { term in
                window.applicationName.localizedCaseInsensitiveContains(term)
                    || window.title.localizedCaseInsensitiveContains(term)
            }) {
                return false
            }
            guard normalizedQuery.isEmpty == false else { return true }
            return window.applicationName.localizedCaseInsensitiveContains(normalizedQuery)
                || window.title.localizedCaseInsensitiveContains(normalizedQuery)
        }

        return filtered.enumerated().sorted { left, right in
            let lhs = left.element
            let rhs = right.element
            switch configuration.sortOrder {
            case .recentlyUsed:
                if lhs.isFocused != rhs.isFocused { return lhs.isFocused }
                return left.offset < right.offset
            case .applicationName:
                let comparison = lhs.applicationName.localizedCaseInsensitiveCompare(
                    rhs.applicationName
                )
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .windowTitle:
                let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.applicationName.localizedCaseInsensitiveCompare(rhs.applicationName)
                    == .orderedAscending
            }
        }.map(\.element)
    }

    private static func completionMessage(for action: WindowAction) -> String {
        switch action {
        case .close: return "Close requested."
        case .toggleMinimized: return "Window state updated."
        case .toggleFullScreen: return "Full-screen state updated."
        case .zoom: return "Window zoomed."
        case .center: return "Window centered."
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return "Window arranged."
        case .quit: return "Quit requested."
        case .activate: return "Window activated."
        }
    }

    private static func failureMessage(for action: WindowAction) -> String {
        switch action {
        case .activate: return "That window is no longer available."
        case .close: return "The window could not be closed."
        case .toggleMinimized: return "The window does not support minimizing."
        case .toggleFullScreen: return "The window does not support full screen."
        case .zoom, .center, .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            return "The window could not be arranged."
        case .quit: return "The application did not quit."
        }
    }

    private static func equalFrames(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): CGRectEqualToRect(lhs, rhs)
        default: false
        }
    }
}
