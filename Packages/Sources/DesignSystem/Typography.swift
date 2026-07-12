import SwiftUI

/// Multipliers applied to base point sizes for Commandly content text.
public enum CommandlyTextScale: Sendable {
    /// Default reading size.
    public static let standard: CGFloat = 1.0
    /// Comfortably larger body and chrome type (~20% up).
    public static let larger: CGFloat = 1.2
}

private struct CommandlyTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = CommandlyTextScale.standard
}

public extension EnvironmentValues {
    /// Relative scale for Commandly UI type. `1` is the design baseline.
    var commandlyTextScale: CGFloat {
        get { self[CommandlyTextScaleKey.self] }
        set { self[CommandlyTextScaleKey.self] = newValue }
    }
}

/// Applies a scaled system font that respects `commandlyTextScale`.
public struct CommandlyScaledFontModifier: ViewModifier {
    @Environment(\.commandlyTextScale) private var textScale

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    public init(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) {
        self.size = size
        self.weight = weight
        self.design = design
    }

    public func body(content: Content) -> some View {
        content.font(.system(size: size * textScale, weight: weight, design: design))
    }
}

public extension View {
    /// Sets the Commandly text scale for this subtree.
    func commandlyTextScale(_ scale: CGFloat) -> some View {
        environment(\.commandlyTextScale, scale)
    }

    /// System font whose point size scales with `commandlyTextScale`.
    func commandlyFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(CommandlyScaledFontModifier(size: size, weight: weight, design: design))
    }
}
