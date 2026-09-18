import CoreGraphics
import Infrastructure
import Testing
@testable import Commandly

@Suite("Window Switcher thumbnail lifetime")
@MainActor
struct WindowSwitcherThumbnailTests {
    @Test func modelBoundsAndPrunesImagesAcrossWindowRefreshes() async throws {
        var configuration = WindowSwitcherConfiguration.default
        configuration.thumbnailCacheLimit = 2
        configuration.showsThumbnails = true
        configuration.usesLivePreviews = false
        let firstCatalog = (1 ... 4).map(snapshot)
        let secondCatalog = (5 ... 8).map(snapshot)
        let queryService = InMemoryWindowService(windows: firstCatalog)
        let thumbnailService = InMemoryWindowThumbnailService()
        let image = try makeImage()
        thumbnailService.images = Dictionary(uniqueKeysWithValues:
            (firstCatalog + secondCatalog).map { ($0.id, image) })
        let model = makeModel(
            configuration: configuration,
            queryService: queryService,
            thumbnailService: thumbnailService
        )
        defer { model.stop() }

        model.load()
        #expect(await eventually { model.thumbnails.count == 2 })
        #expect(model.thumbnails.count <= configuration.thumbnailCacheLimit)

        await queryService.replaceWindows(secondCatalog)
        model.refresh()
        #expect(await eventually {
            model.phase == .ready
                && model.windows.map(\.id) == secondCatalog.map(\.id)
                && model.thumbnails.count == 2
        })
        #expect(Set(model.thumbnails.keys).isSubset(of: Set(secondCatalog.map(\.id))))
        #expect(model.thumbnails.count <= configuration.thumbnailCacheLimit)
    }

    @Test func revokedCaptureAuthorizationPurgesDisplayedImages() async throws {
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = true
        configuration.usesLivePreviews = false
        let catalog = [snapshot(1)]
        let queryService = InMemoryWindowService(windows: catalog)
        let thumbnailService = InMemoryWindowThumbnailService()
        thumbnailService.images[catalog[0].id] = try makeImage()
        let model = makeModel(
            configuration: configuration,
            queryService: queryService,
            thumbnailService: thumbnailService
        )
        defer { model.stop() }

        model.load()
        #expect(await eventually { model.thumbnails.isEmpty == false })

        thumbnailService.isCaptureAuthorized = false
        model.refresh()

        #expect(await eventually { model.phase == .ready && model.thumbnails.isEmpty })
    }

    private func makeModel(
        configuration: WindowSwitcherConfiguration,
        queryService: InMemoryWindowService,
        thumbnailService: InMemoryWindowThumbnailService
    ) -> WindowSwitcherPresentationModel {
        WindowSwitcherPresentationModel(
            configuration: configuration,
            context: .allWindows(frontmostProcessIdentifier: nil),
            queryService: queryService,
            controlService: queryService,
            thumbnailService: thumbnailService,
            displayFrame: nil,
            initialSelectionOffset: 0,
            onRequestDismiss: { _ in }
        )
    }

    private func snapshot(_ index: Int) -> WindowSnapshot {
        let processIdentifier = Int32(1_000 + index)
        return WindowSnapshot(
            id: WindowID(rawValue: "window-\(index)", processIdentifier: processIdentifier),
            processIdentifier: processIdentifier,
            bundleIdentifier: "com.example.window-\(index)",
            applicationName: "Application \(index)",
            title: "Window \(index)",
            frame: CGRect(
                x: CGFloat(index * 20),
                y: CGFloat(index * 20),
                width: 640,
                height: 480
            ),
            isMinimized: false,
            isHidden: false,
            isOnCurrentDesktop: true,
            isFocused: index == 1 || index == 5,
            captureWindowID: UInt32(index)
        )
    }

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0 ..< 400 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}
