import AppKit

/// Plays optional local feedback after the Shelf accepts a drop.
@MainActor
final class NativeShelfDropFeedbackPlayer: ShelfDropFeedbackPlaying {
    private let sound: NSSound?

    init(sound: NSSound? = NSSound(named: NSSound.Name("Pop"))) {
        self.sound = sound
    }

    func playDropAccepted() {
        sound?.stop()
        sound?.play()
    }
}

/// Silent Shelf feedback for tests and previews.
@MainActor
struct NoOpShelfDropFeedbackPlayer: ShelfDropFeedbackPlaying {
    init() {}

    func playDropAccepted() {}
}
