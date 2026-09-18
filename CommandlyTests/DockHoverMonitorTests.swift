import CoreGraphics
import Foundation
import Testing
@testable import Commandly

@Suite("Dock hover monitor")
@MainActor
struct DockHoverMonitorTests {
    @Test
    func deliversResolvedHoverOnMainActor() async {
        let hoveredApplication = DockHoveredApplication(
            processIdentifier: 42,
            bundleIdentifier: "com.example.Editor",
            anchorFrame: CGRect(x: 0, y: 0, width: 40, height: 40)
        )
        let resolver = DeferredDockHoverResolver(result: hoveredApplication)
        let monitor = DockHoverMonitor(
            resolver: resolver,
            environment: makeDockHoverEnvironment(pointer: CGPoint(x: 20, y: 20)),
            pollInterval: 60
        )
        var delivered: [DockHoveredApplication] = []

        monitor.start(
            delay: 0,
            protectedFrame: { nil },
            onHover: { delivered.append($0) },
            onLeave: {}
        )
        await resolver.waitUntilRequestCount(1)
        await resolver.release()
        await yieldUntil { delivered.isEmpty == false }

        #expect(delivered == [hoveredApplication])
        monitor.stop()
    }

    @Test
    func stopRejectsAnInFlightResolutionFromAnOlderGeneration() async {
        let hoveredApplication = DockHoveredApplication(
            processIdentifier: 42,
            bundleIdentifier: "com.example.Editor",
            anchorFrame: CGRect(x: 0, y: 0, width: 40, height: 40)
        )
        let resolver = DeferredDockHoverResolver(result: hoveredApplication)
        let monitor = DockHoverMonitor(
            resolver: resolver,
            environment: makeDockHoverEnvironment(pointer: CGPoint(x: 20, y: 20)),
            pollInterval: 60
        )
        var delivered: [DockHoveredApplication] = []

        monitor.start(
            delay: 0,
            protectedFrame: { nil },
            onHover: { delivered.append($0) },
            onLeave: {}
        )
        await resolver.waitUntilRequestCount(1)
        monitor.stop()
        await resolver.release()
        await yieldUntil { await resolver.completedRequestCount() == 1 }
        for _ in 0 ..< 10 { await Task.yield() }

        #expect(delivered.isEmpty)
    }

    @Test
    func protectedFrameAvoidsStartingAccessibilityResolution() async {
        let resolver = DeferredDockHoverResolver(result: nil)
        let monitor = DockHoverMonitor(
            resolver: resolver,
            environment: makeDockHoverEnvironment(pointer: CGPoint(x: 20, y: 20)),
            pollInterval: 60
        )

        monitor.start(
            delay: 0,
            protectedFrame: { CGRect(x: 0, y: 0, width: 40, height: 40) },
            onHover: { _ in },
            onLeave: {}
        )
        for _ in 0 ..< 10 { await Task.yield() }

        #expect(await resolver.requestCount() == 0)
        monitor.stop()
    }
}

@MainActor
private func makeDockHoverEnvironment(pointer: CGPoint) -> DockHoverEnvironment {
    DockHoverEnvironment(
        isProcessTrusted: { true },
        pointerLocation: { pointer },
        processSnapshot: {
            DockHoverProcessSnapshot(
                dockProcessIdentifier: 7,
                runningApplications: [
                    DockHoverRunningApplication(
                        processIdentifier: 42,
                        bundleIdentifier: "com.example.Editor"
                    ),
                ],
                primaryDisplayHeight: 1_000
            )
        },
        now: { Date(timeIntervalSince1970: 100) }
    )
}

@MainActor
private func yieldUntil(
    _ condition: @escaping @MainActor () async -> Bool
) async {
    for _ in 0 ..< 200 {
        if await condition() { return }
        await Task.yield()
    }
}

private actor DeferredDockHoverResolver: DockHoverResolving {
    private let result: DockHoveredApplication?
    private var requests: [DockHoverResolutionRequest] = []
    private var completedRequests = 0
    private var isReleased = false
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(result: DockHoveredApplication?) {
        self.result = result
    }

    func hoveredApplication(
        for request: DockHoverResolutionRequest
    ) async -> DockHoveredApplication? {
        requests.append(request)
        resumeSatisfiedRequestWaiters()
        if isReleased == false {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        completedRequests += 1
        return result
    }

    func waitUntilRequestCount(_ expectedCount: Int) async {
        guard requests.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((expectedCount, continuation))
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func requestCount() -> Int { requests.count }

    func completedRequestCount() -> Int { completedRequests }

    private func resumeSatisfiedRequestWaiters() {
        let satisfied = requestWaiters.filter { requests.count >= $0.count }
        requestWaiters.removeAll { requests.count >= $0.count }
        satisfied.forEach { $0.continuation.resume() }
    }
}
