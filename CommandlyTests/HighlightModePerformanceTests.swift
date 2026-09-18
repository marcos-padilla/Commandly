import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Highlight Mode performance")
@MainActor
struct HighlightModePerformanceTests {
    @Test func continuousRenderingExistsOnlyDuringClickAnimation() {
        let model = HighlightOverlayModel(configuration: .default)
        #expect(model.requiresContinuousRendering == false)

        model.showKeyText("⌘K")
        #expect(model.requiresContinuousRendering == false)

        let pulse = model.recordClick(
            at: CGPoint(x: 100, y: 100),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(model.requiresContinuousRendering)

        model.removeClick(id: pulse.id)
        #expect(model.requiresContinuousRendering == false)
    }
}
