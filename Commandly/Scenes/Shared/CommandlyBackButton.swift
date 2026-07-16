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
            Image(systemName: "chevron.backward")
                .symbolVariant(.none)
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.mini)
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
