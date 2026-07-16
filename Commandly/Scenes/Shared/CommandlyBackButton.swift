import SwiftUI
import DesignSystem

/// Shared back control used in launcher command surfaces (top-leading chrome).
struct CommandlyBackButton: View {
    var accessibilityLabel: String = "Back"
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .commandlyFont(size: 13, weight: .semibold)
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 9))
        .controlSize(.small)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : CommandlyMotion.hover) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

#Preview {
    CommandlyBackButton(action: {})
        .padding()
}
