import CoreGraphics
import Foundation
import Infrastructure
import ScreenCaptureKit
import SecurityKit

enum WindowThumbnailQuality: String, CaseIterable, Sendable {
    case efficient
    case balanced
    case sharp

    var scale: CGFloat {
        switch self {
        case .efficient: 0.6
        case .balanced: 1
        case .sharp: 1.5
        }
    }
}

@MainActor
protocol WindowThumbnailProviding: AnyObject {
    func setMaximumEntryCount(_ count: Int)

    func hasCaptureAuthorization() async -> Bool

    func thumbnail(
        for window: WindowSnapshot,
        maximumSize: CGSize,
        quality: WindowThumbnailQuality,
        cacheLifetime: TimeInterval,
        forceRefresh: Bool
    ) async -> CGImage?

    func clear()
}

/// Bounded, memory-only ScreenCaptureKit thumbnails.
///
/// Capture is optional: permission denial returns `nil` and leaves the switcher usable with the
/// source application's icon. Images and window metadata are discarded on session teardown.
@MainActor
final class ScreenCaptureWindowThumbnailService: WindowThumbnailProviding {
    private struct CacheKey: Hashable {
        let snapshotID: WindowID
        let captureWindowID: UInt32
    }

    private struct CacheEntry {
        let image: CGImage
        let capturedAt: Date
    }

    private let permissionService: any PermissionServicing
    private let now: () -> Date
    private var maximumEntryCount: Int
    private var cache: [CacheKey: CacheEntry] = [:]
    private var recency: [CacheKey] = []
    private var shareableContentCache: (content: SCShareableContent, loadedAt: Date)?

    init(
        permissionService: any PermissionServicing,
        maximumEntryCount: Int = 36,
        now: @escaping () -> Date = Date.init
    ) {
        self.permissionService = permissionService
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.now = now
    }

    func thumbnail(
        for window: WindowSnapshot,
        maximumSize: CGSize,
        quality: WindowThumbnailQuality,
        cacheLifetime: TimeInterval,
        forceRefresh: Bool = false
    ) async -> CGImage? {
        guard let windowID = window.captureWindowID,
              maximumSize.width > 0,
              maximumSize.height > 0,
              await hasCaptureAuthorization() else {
            return nil
        }
        let cacheKey = CacheKey(snapshotID: window.id, captureWindowID: windowID)

        if forceRefresh == false,
           let cached = cache[cacheKey],
           now().timeIntervalSince(cached.capturedAt) <= max(0, cacheLifetime) {
            markRecentlyUsed(cacheKey)
            return cached.image
        }

        do {
            try Task.checkCancellation()
            let content = try await shareableContent()
            try Task.checkCancellation()
            guard let shareableWindow = content.windows.first(where: {
                $0.windowID == windowID
                    && $0.owningApplication?.processID == window.processIdentifier
            }) else {
                cache[cacheKey] = nil
                recency.removeAll { $0 == cacheKey }
                return nil
            }

            let sourceSize = shareableWindow.frame.size
            let fitScale = min(
                maximumSize.width / max(sourceSize.width, 1),
                maximumSize.height / max(sourceSize.height, 1)
            )
            let outputScale = min(max(fitScale, 0.1) * quality.scale, 2)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(sourceSize.width * outputScale))
            configuration.height = max(1, Int(sourceSize.height * outputScale))
            configuration.showsCursor = false
            configuration.scalesToFit = true
            let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            try Task.checkCancellation()
            insert(image, for: cacheKey)
            return image
        } catch is CancellationError {
            return nil
        } catch {
            // ScreenCaptureKit failures may reflect revocation, protected content, or a window
            // closing mid-capture. The title/icon fallback remains available without logging any
            // private window metadata or provider error body.
            return nil
        }
    }

    func hasCaptureAuthorization() async -> Bool {
        let isAuthorized = await permissionService.state(for: .screenRecording) == .authorized
        if isAuthorized == false {
            clear()
        }
        return isAuthorized
    }

    func setMaximumEntryCount(_ count: Int) {
        maximumEntryCount = max(0, count)
        if maximumEntryCount == 0 {
            clear()
            return
        }
        while recency.count > maximumEntryCount, let oldest = recency.first {
            recency.removeFirst()
            cache[oldest] = nil
        }
    }

    func clear() {
        cache.removeAll(keepingCapacity: false)
        recency.removeAll(keepingCapacity: false)
        shareableContentCache = nil
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let cached = shareableContentCache,
           now().timeIntervalSince(cached.loadedAt) < 1 {
            return cached.content
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: false
        )
        shareableContentCache = (content, now())
        return content
    }

    private func insert(_ image: CGImage, for key: CacheKey) {
        guard maximumEntryCount > 0 else { return }
        cache[key] = CacheEntry(image: image, capturedAt: now())
        markRecentlyUsed(key)
        while recency.count > maximumEntryCount, let oldest = recency.first {
            recency.removeFirst()
            cache[oldest] = nil
        }
    }

    private func markRecentlyUsed(_ key: CacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

@MainActor
final class InMemoryWindowThumbnailService: WindowThumbnailProviding {
    var images: [WindowID: CGImage] = [:]
    var isCaptureAuthorized = true
    private(set) var requests: [WindowID] = []

    func setMaximumEntryCount(_ count: Int) {}

    func hasCaptureAuthorization() async -> Bool {
        isCaptureAuthorized
    }

    func thumbnail(
        for window: WindowSnapshot,
        maximumSize: CGSize,
        quality: WindowThumbnailQuality,
        cacheLifetime: TimeInterval,
        forceRefresh: Bool
    ) async -> CGImage? {
        requests.append(window.id)
        return images[window.id]
    }

    func clear() {
        images.removeAll()
    }
}
