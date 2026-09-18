import DesignSystem
import SwiftUI

struct CelebrationView: View {
    @Bindable var model: CelebrationViewModel
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: density.spacing(.sm)) {
                CommandlyBackButton(action: model.goBack)
                Text("Confetti").commandlyFont(size: 15, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("A moment to celebrate").commandlyFont(size: 11).foregroundStyle(.secondary)
            }
            .padding(density.spacing(.md))
            Divider()
            ZStack {
                decoration
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                VStack(spacing: density.spacing(.md)) {
                    Image(systemName: "sparkles")
                        .commandlyFont(size: 40, weight: .light)
                        .accessibilityHidden(true)
                    Text("Well done.").commandlyFont(size: 30, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text("Make a little room for a small win.")
                        .commandlyFont(size: 13).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: density.spacing(.sm)) {
                        Button("Done", action: model.goBack)
                            .keyboardShortcut(.cancelAction)
                        Button("Celebrate Again", action: model.replay)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("celebration-replay")
                    }
                    .padding(.top, density.spacing(.xs))
                    if reducesMotion {
                        Text("Still confetti · Reduce Motion is on")
                            .commandlyFont(size: 10).foregroundStyle(.secondary)
                    }
                }
                .padding(density.spacing(.lg))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confetti celebration")
        .onAppear { model.start(reducesMotion: reducesMotion) }
        .onChange(of: reducesMotion) { _, value in model.updateReducedMotion(value) }
        .onDisappear { model.stop() }
        .onExitCommand(perform: model.goBack)
    }

    @ViewBuilder private var decoration: some View {
        if model.isActive {
            if let burst = model.burst, reducesMotion == false {
                TimelineView(.explicit(burst.frameDates)) { timeline in
                    CelebrationCanvas(elapsed: burst.elapsed(at: timeline.date))
                }
                .id(burst.id)
            } else {
                CelebrationCanvas(elapsed: nil)
            }
        }
    }
}

private struct CelebrationCanvas: View {
    /// Nil draws a stationary arrangement without creating a TimelineView.
    let elapsed: TimeInterval?
    private let colors: [Color] = [
        Color(red: 0.87, green: 0.64, blue: 0.31),
        Color(red: 0.43, green: 0.64, blue: 0.86),
        Color(red: 0.40, green: 0.73, blue: 0.63),
        Color(red: 0.83, green: 0.48, blue: 0.59)
    ]

    var body: some View {
        Canvas { context, size in
            for particle in CelebrationParticle.catalog {
                let frame: CelebrationParticle.Frame?
                if let elapsed {
                    frame = particle.frame(elapsed: elapsed, size: size)
                } else {
                    frame = particle.id < 20 ? particle.stillFrame(size: size) : nil
                }
                guard let frame else { continue }
                var drawing = context
                drawing.opacity = frame.opacity
                drawing.translateBy(x: frame.center.x, y: frame.center.y)
                drawing.rotate(by: .radians(frame.rotation))
                let rect = CGRect(x: -frame.size.width / 2, y: -frame.size.height / 2,
                                  width: frame.size.width, height: frame.size.height)
                drawing.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[particle.colorIndex]))
            }
        }
    }
}
