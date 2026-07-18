import CoreGraphics
import Foundation
import Infrastructure
import Synchronization
import Testing
@testable import Commandly

struct ApplicationCacheTests {
    @Test @MainActor
    func iconCacheSharesOneDecodedImageAcrossBundleAndPathRequests() async throws {
        let image = try makeTestImage(size: 2)
        let probe = ApplicationIconLoaderProbe(
            now: Date(timeIntervalSince1970: 100),
            image: image
        )
        let cache = ApplicationIconCache(
            now: { probe.now },
            loader: { probe.load($0) }
        )
        let bundleRequest = try #require(
            ApplicationIconRequest(bundleIdentifier: "com.example.Editor")
        )
        let pathRequest = try #require(
            ApplicationIconRequest(path: "/Applications/Editor.app")
        )

        let bundleImage = await cache.image(for: bundleRequest)
        let pathImage = await cache.image(for: pathRequest)

        #expect(bundleImage?.width == 2)
        #expect(pathImage?.width == 2)
        #expect(probe.loadCount == 1)
        #expect(probe.loadRanOnMainThread == false)
    }

    @Test
    func iconCacheBoundsFailuresAndCanInvalidateASuccessImmediately() async throws {
        let firstImage = try makeTestImage(size: 2)
        let replacementImage = try makeTestImage(size: 3)
        let probe = ApplicationIconLoaderProbe(
            now: Date(timeIntervalSince1970: 200),
            image: nil
        )
        let cache = ApplicationIconCache(
            cacheLifetime: 300,
            failureRetryInterval: 10,
            now: { probe.now },
            loader: { probe.load($0) }
        )
        let request = try #require(
            ApplicationIconRequest(bundleIdentifier: "com.example.NewlyInstalled")
        )

        let firstMiss = await cache.image(for: request)
        let cachedMiss = await cache.image(for: request)
        #expect(firstMiss == nil)
        #expect(cachedMiss == nil)
        #expect(probe.loadCount == 1)

        probe.setImage(firstImage)
        let boundedMiss = await cache.image(for: request)
        #expect(boundedMiss == nil)
        #expect(probe.loadCount == 1)

        probe.advance(by: 10)
        let installedImage = await cache.image(for: request)
        #expect(installedImage?.width == 2)
        #expect(probe.loadCount == 2)

        probe.setImage(replacementImage)
        await cache.invalidate(bundleIdentifier: "com.example.NewlyInstalled")
        let refreshedImage = await cache.image(for: request)
        #expect(refreshedImage?.width == 3)
        #expect(probe.loadCount == 3)
    }

    @Test
    func installedApplicationQueryRefreshesAfterTTLAndExplicitInvalidation() async {
        let first = InstalledApplication(
            bundleIdentifier: "com.example.First",
            name: "First",
            path: "/Applications/First.app"
        )
        let second = InstalledApplication(
            bundleIdentifier: "com.example.Second",
            name: "Second",
            path: "/Applications/Second.app"
        )
        let third = InstalledApplication(
            bundleIdentifier: "com.example.Third",
            name: "Third",
            path: "/Applications/Third.app"
        )
        let probe = InstalledApplicationScannerProbe(
            now: Date(timeIntervalSince1970: 300),
            applications: [first]
        )
        let query = WorkspaceInstalledApplicationQuery(
            cacheLifetime: 30,
            now: { probe.now },
            scanner: { probe.scan() }
        )

        #expect(await query.installedApplications() == [first])
        probe.setApplications([second])
        #expect(await query.installedApplications() == [first])
        #expect(probe.scanCount == 1)

        probe.advance(by: 30)
        #expect(await query.installedApplications() == [second])
        #expect(probe.scanCount == 2)

        probe.setApplications([third])
        await query.invalidateCache()
        #expect(await query.installedApplications() == [third])
        #expect(probe.scanCount == 3)
    }

    @Test
    func iconCacheEvictsLeastRecentlyUsedImagesAtItsCapacity() async throws {
        let image = try makeTestImage(size: 2)
        let probe = ApplicationIconCapacityProbe(
            now: Date(timeIntervalSince1970: 400),
            image: image
        )
        let cache = ApplicationIconCache(
            cacheLifetime: 300,
            maximumEntryCount: 2,
            now: { probe.now },
            loader: { probe.load($0) }
        )
        let first = try #require(ApplicationIconRequest(path: "/Applications/First.app"))
        let second = try #require(ApplicationIconRequest(path: "/Applications/Second.app"))
        let third = try #require(ApplicationIconRequest(path: "/Applications/Third.app"))

        #expect(await cache.image(for: first) != nil)
        probe.advance(by: 1)
        #expect(await cache.image(for: second) != nil)
        probe.advance(by: 1)
        // Refresh the first entry so the second becomes least recently used.
        #expect(await cache.image(for: first) != nil)
        probe.advance(by: 1)
        #expect(await cache.image(for: third) != nil)
        #expect(probe.loadCount == 3)

        probe.advance(by: 1)
        #expect(await cache.image(for: second) != nil)
        #expect(probe.loadCount == 4)
    }

    private func makeTestImage(size: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try #require(context.makeImage())
    }
}

private nonisolated final class ApplicationIconCapacityProbe: Sendable {
    private nonisolated struct State: Sendable {
        var now: Date
        let image: CGImage
        var loadCount = 0
    }

    private let state: Mutex<State>

    init(now: Date, image: CGImage) {
        state = Mutex(State(now: now, image: image))
    }

    var now: Date {
        state.withLock { $0.now }
    }

    var loadCount: Int {
        state.withLock { $0.loadCount }
    }

    func load(_ request: ApplicationIconRequest) -> LoadedApplicationIcon? {
        guard case .path(let path) = request else { return nil }
        return state.withLock { state in
            state.loadCount += 1
            return LoadedApplicationIcon(canonicalPath: path, image: state.image)
        }
    }

    func advance(by interval: TimeInterval) {
        state.withLock { $0.now = $0.now.addingTimeInterval(interval) }
    }
}

private nonisolated final class ApplicationIconLoaderProbe: Sendable {
    private nonisolated struct State: Sendable {
        var now: Date
        var image: CGImage?
        var loadCount = 0
        var loadRanOnMainThread = false
    }

    private let state: Mutex<State>

    init(now: Date, image: CGImage?) {
        self.state = Mutex(State(now: now, image: image))
    }

    var now: Date {
        state.withLock { $0.now }
    }

    var loadCount: Int {
        state.withLock { $0.loadCount }
    }

    var loadRanOnMainThread: Bool {
        state.withLock { $0.loadRanOnMainThread }
    }

    func load(_ request: ApplicationIconRequest) -> LoadedApplicationIcon? {
        _ = request
        return state.withLock { state in
            state.loadCount += 1
            state.loadRanOnMainThread = Thread.isMainThread
            guard let image = state.image else { return nil }
            return LoadedApplicationIcon(
                canonicalPath: "/Applications/Editor.app",
                image: image
            )
        }
    }

    func setImage(_ image: CGImage?) {
        state.withLock { $0.image = image }
    }

    func advance(by interval: TimeInterval) {
        state.withLock { $0.now = $0.now.addingTimeInterval(interval) }
    }
}

private nonisolated final class InstalledApplicationScannerProbe: Sendable {
    private nonisolated struct State: Sendable {
        var now: Date
        var applications: [InstalledApplication]
        var scanCount = 0
    }

    private let state: Mutex<State>

    init(now: Date, applications: [InstalledApplication]) {
        self.state = Mutex(State(now: now, applications: applications))
    }

    var now: Date {
        state.withLock { $0.now }
    }

    var scanCount: Int {
        state.withLock { $0.scanCount }
    }

    func scan() -> [InstalledApplication] {
        state.withLock { state in
            state.scanCount += 1
            return state.applications
        }
    }

    func setApplications(_ applications: [InstalledApplication]) {
        state.withLock { $0.applications = applications }
    }

    func advance(by interval: TimeInterval) {
        state.withLock { $0.now = $0.now.addingTimeInterval(interval) }
    }
}
