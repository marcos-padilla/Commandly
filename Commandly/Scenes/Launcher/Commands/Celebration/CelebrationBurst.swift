import CoreGraphics
import Foundation

/// One finite, deterministic animation. No repeating timer or random global state is needed.
nonisolated struct CelebrationBurst: Identifiable, Equatable {
    static let duration: TimeInterval = 3.2
    static let framesPerSecond = 30
    let id: UUID
    let startedAt: Date
    let frameDates: [Date]

    init(startedAt: Date, id: UUID = UUID()) {
        self.id = id
        self.startedAt = startedAt
        self.frameDates = (0...Int(Self.duration * Double(Self.framesPerSecond))).map {
            startedAt.addingTimeInterval(Double($0) / Double(Self.framesPerSecond))
        }
    }

    func elapsed(at date: Date) -> TimeInterval {
        min(Self.duration, max(0, date.timeIntervalSince(startedAt)))
    }
}

/// Original geometric confetti drawn into one Canvas; particles are never individual views.
nonisolated struct CelebrationParticle: Identifiable {
    static let catalog: [CelebrationParticle] = (0..<72).map { CelebrationParticle(id: $0) }
    let id: Int
    var colorIndex: Int { id % 4 }

    struct Frame {
        let center: CGPoint
        let size: CGSize
        let rotation: Double
        let opacity: Double
    }

    func frame(elapsed: TimeInterval, size: CGSize) -> Frame? {
        guard size.width > 0, size.height > 0, elapsed.isFinite,
              elapsed >= 0, elapsed < CelebrationBurst.duration else { return nil }
        let delay = fraction(7) * 0.2
        let time = elapsed - delay
        guard time >= 0 else { return nil }
        let horizontal = (fraction(11) - 0.5) * 0.7
        let vertical = -(0.58 + fraction(17) * 0.38)
        return Frame(
            center: CGPoint(
                x: size.width * (0.5 + horizontal * time + sin(time * 4 + Double(id)) * time * 0.008),
                y: size.height * (0.7 + vertical * time + 0.28 * time * time)
            ),
            size: CGSize(width: 4 + fraction(23) * 5, height: 3 + fraction(29) * 7),
            rotation: Double(id) + time * (fraction(31) - 0.5) * 9,
            opacity: min(1, max(0, (CelebrationBurst.duration - elapsed) / 0.8))
        )
    }

    func stillFrame(size: CGSize) -> Frame {
        let angle = Double(id) * 2.3999632297
        let radius = 0.23 + fraction(13) * 0.18
        return Frame(
            center: CGPoint(x: size.width * (0.5 + cos(angle) * radius),
                            y: size.height * (0.48 + sin(angle) * radius)),
            size: CGSize(width: 5 + fraction(23) * 4, height: 4 + fraction(29) * 5),
            rotation: angle, opacity: 0.75
        )
    }

    private func fraction(_ multiplier: Int) -> Double {
        Double((id * multiplier + 19) % 73) / 73
    }
}
