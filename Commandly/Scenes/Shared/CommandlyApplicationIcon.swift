import AppKit
import DesignSystem
import SwiftUI

/// Displays Commandly's compiled app artwork without relying on
/// `NSApp.applicationIconImage`, which can be a generic placeholder while a
/// menu-bar app or test host is still attaching its application bundle.
struct CommandlyApplicationIcon: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let image = CommandlyApplicationArtwork.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                fallbackMark
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Commandly app icon")
    }

    private var fallbackMark: some View {
        Image(systemName: "command")
            .commandlyFont(size: size * 0.48, weight: .bold)
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [BrandPalette.accent, Color.cyan.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            )
    }
}

@MainActor
private enum CommandlyApplicationArtwork {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}
