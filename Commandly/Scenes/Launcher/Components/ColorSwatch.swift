import DesignSystem
import SwiftUI

/// Checkerboard makes transparency visible in both root results and the focused editor.
struct ColorSwatch: View {
    let color: CommandlyColor

    var body: some View {
        Canvas { context, size in
            let side = 10.0
            for row in 0 ..< Int(ceil(size.height / side)) {
                for column in 0 ..< Int(ceil(size.width / side)) {
                    let rect = CGRect(x: Double(column) * side, y: Double(row) * side, width: side, height: side)
                    context.fill(Path(rect), with: .color((row + column).isMultiple(of: 2) ? .white : .gray.opacity(0.4)))
                }
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: color.nsColor)))
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
        .overlay(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue).strokeBorder(Color.primary.opacity(0.15)))
        .accessibilityLabel("Color preview")
        .accessibilityValue(color.formatted(.hexWithAlpha))
    }
}
