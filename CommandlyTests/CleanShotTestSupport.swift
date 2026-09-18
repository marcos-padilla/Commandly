import CoreGraphics
import Foundation
import Infrastructure
import Synchronization
import Testing
@testable import Commandly

nonisolated final class CleanShotTestClock: Sendable {
    private struct Pending { let deadline: Date; let continuation: CheckedContinuation<Void, Error> }
    private struct State: Sendable {
        var now = Date()
        var pending: [UUID: Pending] = [:]
        var cancelled: Set<UUID> = []
        var scheduledWaiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())
    var clock: CleanShotLeaseClock {
        CleanShotLeaseClock(now: { self.state.withLock { $0.now } }, waitUntil: { try await self.wait(until: $0) })
    }
    func waitUntilScheduled() async {
        await withCheckedContinuation { continuation in
            state.withLock { value in
                if value.pending.isEmpty == false { continuation.resume() }
                else { value.scheduledWaiters.append(continuation) }
            }
        }
    }
    func advance(by seconds: TimeInterval) {
        state.withLock { value in
            value.now.addTimeInterval(seconds)
            for id in value.pending.keys where (value.pending[id]?.deadline ?? .distantFuture) <= value.now {
                value.pending.removeValue(forKey: id)?.continuation.resume()
            }
        }
    }
    func finish() {
        state.withLock { value in
            for pending in value.pending.values { pending.continuation.resume(throwing: CancellationError()) }
            value.pending.removeAll()
        }
    }
    private func wait(until deadline: Date) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                state.withLock { value in
                    if value.cancelled.remove(id) != nil || Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                    else if deadline <= value.now { continuation.resume() }
                    else { value.pending[id] = Pending(deadline: deadline, continuation: continuation) }
                    for waiter in value.scheduledWaiters { waiter.resume() }
                    value.scheduledWaiters.removeAll()
                }
            }
        } onCancel: {
            self.state.withLock { value in
                if let pending = value.pending.removeValue(forKey: id) { pending.continuation.resume(throwing: CancellationError()) }
                else { value.cancelled.insert(id) }
            }
        }
    }
}

nonisolated struct CleanShotTestFiles {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Commandly-CleanShot-Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func content(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    func permissions(_ url: URL) throws -> Int { (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0 }
}

actor CleanShotTestImageFactory {
    func image() async throws -> ScreenshotImage {
        let context = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        return try await ScreenshotImageRenderer().render(#require(context.makeImage()), kind: .window)
    }
}

@MainActor
final class CleanShotOpenerFake: CleanShotApplicationOpening {
    var destinationError: ScreenshotAnnotationError?
    var openError: ScreenshotAnnotationError?
    var blocksDestination = false
    var blocksOpen = false
    private(set) var destinationCount = 0
    private(set) var opened: [(URL, CleanShotDestination)] = []
    private var destinationPending: CheckedContinuation<Void, Never>?
    private var openPending: CheckedContinuation<Void, Never>?
    private var destinationWaiter: CheckedContinuation<Void, Never>?
    private var openWaiter: CheckedContinuation<Void, Never>?
    func destination() async throws -> CleanShotDestination {
        destinationCount += 1
        destinationWaiter?.resume(); destinationWaiter = nil
        if blocksDestination { await withCheckedContinuation { destinationPending = $0 } }
        if let destinationError { throw destinationError }
        return CleanShotDestination(applicationURL: URL(fileURLWithPath: "/Applications/CleanShot X.app"))
    }
    func open(_ url: URL, in destination: CleanShotDestination) async throws {
        try Task.checkCancellation()
        opened.append((url, destination))
        openWaiter?.resume(); openWaiter = nil
        if blocksOpen { await withCheckedContinuation { openPending = $0 } }
        if let openError { throw openError }
    }
    func waitUntilDestination() async { if destinationCount > 0 { return }; await withCheckedContinuation { destinationWaiter = $0 } }
    func waitUntilOpen() async { if opened.isEmpty == false { return }; await withCheckedContinuation { openWaiter = $0 } }
    func releaseDestination() { destinationPending?.resume(); destinationPending = nil }
    func releaseOpen() { openPending?.resume(); openPending = nil }
}
