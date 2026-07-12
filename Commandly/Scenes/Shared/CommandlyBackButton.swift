import SwiftUI
import DesignSystem

/// Shared back control used in launcher command surfaces (top-leading chrome).
struct CommandlyBackButton: View {
    var accessibilityLabel: String = "Back"
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .commandlyFont(size: 13, weight: .semibold)
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.14 : 0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(isHovered ? 0.20 : 0.08),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: BrandPalette.accent.opacity(isHovered ? 0.28 : 0),
                    radius: isHovered ? 10 : 0,
                    y: isHovered ? 2 : 0
                )
                .scaleEffect(isHovered ? 1.07 : 1)
        }
        .buttonStyle(CommandlyBackButtonStyle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private struct CommandlyBackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

#Preview {
    CommandlyBackButton(action: {})
        .padding()
}
