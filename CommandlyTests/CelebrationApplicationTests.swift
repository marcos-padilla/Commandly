import CommandKit
import CoreGraphics
import Foundation
import Testing
@testable import Commandly

struct CelebrationApplicationTests {
    @Test func burstScheduleAndParticleWorkAreFinite() throws {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let burst = CelebrationBurst(startedAt: start)
        #expect(burst.frameDates.count == 97)
        #expect(burst.frameDates.first == start)
        let end = try #require(burst.frameDates.last)
        #expect(abs(end.timeIntervalSince(start) - CelebrationBurst.duration) < 0.001)
        #expect(zip(burst.frameDates, burst.frameDates.dropFirst()).allSatisfy { pair in pair.0 < pair.1 })
        #expect(burst.elapsed(at: start.addingTimeInterval(-1)) == 0)
        #expect(burst.elapsed(at: start.addingTimeInterval(100)) == CelebrationBurst.duration)
        #expect(CelebrationParticle.catalog.count == 72)
        #expect(Set(CelebrationParticle.catalog.map(\.id)).count == 72)
        let size = CGSize(width: 720, height: 360)
        for particle in CelebrationParticle.catalog {
            #expect(particle.frame(elapsed: -1, size: size) == nil)
            #expect(particle.frame(elapsed: .infinity, size: size) == nil)
            #expect(particle.frame(elapsed: CelebrationBurst.duration, size: size) == nil)
            #expect(particle.frame(elapsed: 1, size: .zero) == nil)
            let frame = try #require(particle.frame(elapsed: 1, size: size))
            #expect(frame.center.x.isFinite && frame.center.y.isFinite && frame.rotation.isFinite)
            #expect(frame.size.width > 0 && frame.size.height > 0)
            #expect((0...1).contains(frame.opacity))
            #expect((0..<4).contains(particle.colorIndex))
            let still = particle.stillFrame(size: size)
            #expect((0...size.width).contains(still.center.x))
            #expect((0...size.height).contains(still.center.y))
        }
    }

    @Test @MainActor func replayReplacesTheBurstAndRepeatedAppearanceDoesNotRestartIt() throws {
        let clock = CelebrationTestClock()
        let model = CelebrationViewModel(now: { clock.now }, onGoBack: {})
        #expect(model.isActive == false)
        #expect(model.burst == nil)
        model.start(reducesMotion: false)
        let first = try #require(model.burst)
        model.start(reducesMotion: false)
        #expect(model.burst?.id == first.id)
        clock.now = clock.now.addingTimeInterval(20)
        model.perform(CelebrationActionID.replay)
        let second = try #require(model.burst)
        #expect(second.id != first.id)
        #expect(second.startedAt == clock.now)
        #expect(second.frameDates.count == first.frameDates.count)
        #expect(model.footerActions.first?.id == CelebrationActionID.replay)
        #expect(model.footerActions.first?.isPrimary == true)
        model.stop()
        #expect(model.isActive == false)
        #expect(model.burst == nil)
        model.replay()
        model.start(reducesMotion: false)
        #expect(model.burst == nil)
    }

    @Test @MainActor func reducedMotionNeverSchedulesFramesAndStopsAnExistingBurst() {
        let model = CelebrationViewModel(onGoBack: {})
        model.start(reducesMotion: true)
        #expect(model.isActive)
        #expect(model.reducesMotion)
        #expect(model.burst == nil)
        model.replay()
        #expect(model.burst == nil)
        model.updateReducedMotion(false)
        #expect(model.burst == nil)
        model.replay()
        #expect(model.burst != nil)
        model.updateReducedMotion(true)
        #expect(model.burst == nil)
        model.stop()
    }

    @Test @MainActor func escapeStopsImmediatelyAndCloseRequestsNavigationOnlyOnce() {
        let navigation = CelebrationTestNavigation()
        let model = CelebrationViewModel(onGoBack: { navigation.backCount += 1 })
        model.start(reducesMotion: false)
        #expect(model.handleEscape() == false)
        #expect(model.burst == nil)
        #expect(model.isActive == false)
        #expect(navigation.backCount == 0)
        let closing = CelebrationViewModel(onGoBack: { navigation.backCount += 1 })
        closing.start(reducesMotion: false)
        closing.perform(CelebrationActionID.close)
        closing.goBack()
        #expect(navigation.backCount == 1)
        #expect(closing.burst == nil)
    }

    @Test @MainActor func registeredConfettiToolPresentsAnIsolatedStoppableSession() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        #expect(registry.children(of: CelebrationApplication.id).map(\.id) == [CelebrationApplication.celebrateToolID])
        let application = CelebrationApplication()
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:])
        )
        guard case .present(let session) = application.launch(
            toolID: CelebrationApplication.celebrateToolID, arguments: CommandArguments(), in: context
        ) else {
            Issue.record("Expected celebration tool to present its native session")
            return
        }
        let model = try #require(session.model(as: CelebrationViewModel.self))
        #expect(model.burst == nil)
        model.start(reducesMotion: false)
        #expect(model.burst != nil)
        session.stop()
        #expect(model.burst == nil)
        guard case .message = application.launch(
            toolID: CommandID(rawValue: "celebration.missing"), arguments: CommandArguments(), in: context
        ) else {
            Issue.record("Unknown tools must not play a celebration")
            return
        }
    }
}

@MainActor
private final class CelebrationTestClock {
    var now = Date(timeIntervalSinceReferenceDate: 10_000)
}

@MainActor
private final class CelebrationTestNavigation {
    var backCount = 0
}
