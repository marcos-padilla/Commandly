import AppKit
import DesignSystem
import SwiftUI

/// Menu bar glyph for the Commandly status item.
///
/// It stays the plain Commandly mark until a Keep Awake session is running, then becomes the
/// chosen active icon in the chosen tint — the only place the session is visible when no window
/// is open.
///
/// The status item is a one-point-wide window that renegotiates its size whenever its content
/// changes, so this view is deliberately rigid: one `Image`, never a branch between two different
/// view types, and an image object that is identical across body passes while the session state
/// is unchanged. Handing SwiftUI a freshly built image each pass makes the window resize, which
/// invalidates the hosting view, which rebuilds the label — a loop AppKit ends by throwing.
struct StatusBarIconLabel: View {
    @Bindable var keepAwake: KeepAwakeCoordinator

    var body: some View {
        // No frame and no imposed size. The status item's window is sized by what this label
        // reports, so asking for dimensions it cannot be given leaves SwiftUI and AppKit
        // negotiating a size they never agree on. The symbol configuration below is the only
        // thing that decides how big the glyph is, exactly as a plain `Label` would.
        Image(nsImage: StatusBarIconImage.image(symbolName: symbolName, tint: tintColor))
            .accessibilityLabel(accessibilityLabel)
    }

    private var isShowingSession: Bool {
        keepAwake.isActive && keepAwake.isPausedForScreenLock == false
    }

    private var symbolName: String {
        isShowingSession ? keepAwake.settings.activeIcon.symbolName : "command"
    }

    private var tintColor: NSColor? {
        guard isShowingSession else { return nil }
        return keepAwake.settings.activeIconTint.menuBarColor
    }

    private var accessibilityLabel: String {
        isShowingSession ? "Commandly, Keep Awake is on" : "Commandly"
    }
}

/// Builds and caches the status item's symbol.
///
/// Images are cached by symbol and tint so an unchanged session hands SwiftUI the same object
/// every time. The key space is the handful of active icons times the handful of tints, so the
/// cache is small and never needs eviction.
@MainActor
enum StatusBarIconImage {
    /// Point size the glyph is rendered at, which is what gives it its natural menu bar size.
    private static let pointSize: CGFloat = 15
    /// Used when even the fallback symbol is missing, so the view always has an image to draw.
    private static let blank = NSImage(size: NSSize(width: pointSize, height: pointSize))

    private struct Key: Hashable {
        let symbolName: String
        /// Kept as a name rather than the color, so two equal colors share one entry.
        let tintName: String?
    }

    private static var cache: [Key: NSImage] = [:]

    /// The menu bar image for one session state. Always returns an image.
    ///
    /// A `nil` tint keeps the image a template so macOS draws it in the menu bar's own color and
    /// it inverts correctly with the menu bar's appearance; a tint turns it into a colored image,
    /// which is what makes an active session stand out.
    static func image(symbolName: String, tint: NSColor?) -> NSImage {
        let key = Key(symbolName: symbolName, tintName: tint?.description)
        if let cached = cache[key] { return cached }

        let image = make(symbolName: symbolName, tint: tint)
            ?? make(symbolName: "command", tint: tint)
            ?? blank
        cache[key] = image
        return image
    }

    private static func make(symbolName: String, tint: NSColor?) -> NSImage? {
        guard let base = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        ) else {
            return nil
        }

        var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let tint {
            configuration = configuration.applying(
                NSImage.SymbolConfiguration(paletteColors: [tint])
            )
        }
        guard let image = base.withSymbolConfiguration(configuration) else { return nil }

        // The symbol keeps the size its configuration produced. Overriding it here would hand the
        // status item a size it may not be able to honor.
        image.isTemplate = tint == nil
        return image
    }
}

extension KeepAwakeIconTint {
    /// AppKit color used for the tinted menu bar glyph.
    var menuBarColor: NSColor? {
        switch self {
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .untinted: return nil
        }
    }
}
