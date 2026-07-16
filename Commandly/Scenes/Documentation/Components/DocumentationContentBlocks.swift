import DesignSystem
import SwiftUI

struct DocumentationSectionCard: View {
    let section: DocumentationSection

    var body: some View {
        DocumentationSurfaceCard {
            VStack(alignment: .leading, spacing: Spacing.md.rawValue) {
                Text(section.title)
                    .commandlyFont(size: 16, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)

                ForEach(section.blocks) { block in
                    DocumentationBlockView(block: block)
                }
            }
        }
        .accessibilityIdentifier("documentation.section.\(section.id)")
    }
}

private struct DocumentationBlockView: View {
    let block: DocumentationBlock

    @ViewBuilder
    var body: some View {
        switch block.content {
        case .paragraph(let text):
            Text(text)
                .commandlyFont(size: 12.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2.5)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs.rawValue) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(item)
                            .commandlyFont(size: 12)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                }
            }

        case .steps(let items):
            VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: Spacing.sm.rawValue) {
                        Text("\(index + 1).")
                            .commandlyFont(size: 10.5, weight: .semibold)
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .trailing)
                            .accessibilityHidden(true)
                        Text(item)
                            .commandlyFont(size: 12)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                            .padding(.top, 3)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1), \(item)")
                }
            }

        case .shortcuts(let shortcuts):
            VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                ForEach(shortcuts) { shortcut in
                    DocumentationShortcutRow(
                        title: shortcut.title,
                        keys: shortcut.keys,
                        detail: shortcut.detail
                    )
                }
            }

        case .examples(let examples):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                    DocumentationExampleRow(example: example)

                    if index < examples.count - 1 {
                        Divider()
                            .overlay(DocumentationVisualStyle.separator)
                            .padding(.horizontal, Spacing.sm.rawValue)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(DocumentationVisualStyle.field)
            }

        case .callout(let callout):
            DocumentationCalloutView(callout: callout)
        }
    }
}

/// A flat documentation group separated by a single hairline.
///
/// The renderer avoids nesting cards. Spacing and separators carry the article hierarchy,
/// leaving Liquid Glass to the window's elevated navigation controls.
struct DocumentationSurfaceCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xl.rawValue)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DocumentationVisualStyle.separator)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
    }
}

struct DocumentationSectionHeading: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: icon)
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(title)
        }
        .commandlyFont(size: 13, weight: .semibold)
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isHeader)
    }
}

struct DocumentationShortcutRow: View {
    let title: String
    let keys: [String]
    let detail: String?

    var body: some View {
        HStack(spacing: Spacing.sm.rawValue) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .commandlyFont(size: 12, weight: .medium)
                if let detail {
                    Text(detail)
                        .commandlyFont(size: 10)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: Spacing.xs.rawValue)
            HStack(spacing: 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .frame(minWidth: 21, minHeight: 21)
                        .padding(.horizontal, 2)
                        .background {
                            RoundedRectangle(
                                cornerRadius: CornerRadius.sm.rawValue,
                                style: .continuous
                            )
                                .fill(DocumentationVisualStyle.field)
                        }
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: CornerRadius.sm.rawValue,
                                style: .continuous
                            )
                                .strokeBorder(DocumentationVisualStyle.separator, lineWidth: 1)
                        }
                }
            }
            .accessibilityLabel(spokenKeys)
        }
        .padding(.vertical, 1)
    }

    private var spokenKeys: String {
        keys.map { key in
            switch key {
            case "⌘": return "Command"
            case "⌥": return "Option"
            case "⌃": return "Control"
            case "⇧": return "Shift"
            case "↩", "Return": return "Return"
            case "Esc": return "Escape"
            case "↑": return "Up Arrow"
            case "↓": return "Down Arrow"
            case "←": return "Left Arrow"
            case "→": return "Right Arrow"
            case "?": return "Question Mark"
            default: return key
            }
        }.joined(separator: " ")
    }
}

private struct DocumentationExampleRow: View {
    let example: DocumentationExample

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            Text(example.input)
                .commandlyFont(size: 11.5, weight: .medium, design: .monospaced)
                .textSelection(.enabled)
                .foregroundStyle(.primary)

            if let output = example.output {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .commandlyFont(size: 8, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(output)
                        .commandlyFont(size: 11, weight: .semibold, design: .monospaced)
                        .textSelection(.enabled)
                }
            }

            if let detail = example.detail {
                Text(detail)
                    .commandlyFont(size: 10)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(Spacing.sm.rawValue)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
    }
}

private struct DocumentationCalloutView: View {
    let callout: DocumentationCallout

    private var icon: String {
        switch callout.kind {
        case .tip: return "lightbulb.fill"
        case .privacy: return "lock.shield.fill"
        case .permission: return "hand.raised.fill"
        case .limitation: return "info.circle.fill"
        case .important: return "exclamationmark.circle.fill"
        }
    }

    private var tint: CommandlyTint {
        callout.kind.documentationTint
    }

    private var iconColor: Color {
        switch callout.kind {
        case .tip:
            return CommandlyTint.orange.color
        default:
            return tint.color
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm.rawValue) {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconColor)
                .frame(width: 21)
            VStack(alignment: .leading, spacing: 3) {
                Text(callout.title)
                    .commandlyFont(size: 12, weight: .semibold)
                Text(callout.text)
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(Spacing.sm.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(DocumentationVisualStyle.field)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(iconColor)
                .frame(width: 2)
                .padding(.vertical, Spacing.xs.rawValue)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DocumentationBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(label)
        }
        .commandlyFont(size: 8.5, weight: .semibold)
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

struct DocumentationMetadataPill: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: icon)
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .commandlyFont(size: 7.5, weight: .semibold)
                    .foregroundStyle(.quaternary)
                Text(value)
                    .commandlyFont(size: 10.5, weight: .semibold, design: .rounded)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DocumentationInlineNotice: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .symbolVariant(.fill)
                .foregroundStyle(CommandlyTint.orange.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .commandlyFont(size: 11.5, weight: .semibold)
                Text(text)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(Spacing.sm.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(DocumentationVisualStyle.field)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(CommandlyTint.orange.color)
                .frame(width: 2)
                .padding(.vertical, Spacing.xs.rawValue)
        }
        .accessibilityElement(children: .combine)
    }
}
