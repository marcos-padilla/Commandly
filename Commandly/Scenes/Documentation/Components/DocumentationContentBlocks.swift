import DesignSystem
import SwiftUI

struct DocumentationSectionCard: View {
    let section: DocumentationSection

    var body: some View {
        DocumentationGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(section.title)
                    .commandlyFont(size: 16.5, weight: .semibold)
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
                .commandlyFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(BrandPalette.accentSoft)
                            .accessibilityHidden(true)
                        Text(item)
                            .commandlyFont(size: 11.5)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .steps(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .commandlyFont(size: 9.5, weight: .bold)
                            .foregroundStyle(BrandPalette.accentSoft)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(BrandPalette.accent.opacity(0.13)))
                        Text(item)
                            .commandlyFont(size: 11.5)
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                    }
                }
            }

        case .shortcuts(let shortcuts):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    DocumentationShortcutRow(
                        title: shortcut.title,
                        keys: shortcut.keys,
                        detail: shortcut.detail
                    )
                }
            }

        case .examples(let examples):
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(examples) { example in
                    DocumentationExampleCard(example: example)
                }
            }

        case .callout(let callout):
            DocumentationCalloutView(callout: callout)
        }
    }
}

struct DocumentationGlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(SettingsPalette.card)
            }
            .glassEffect(
                .regular.tint(BrandPalette.accent.opacity(0.025)),
                in: .rect(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(SettingsPalette.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.07), radius: 16, y: 7)
    }
}

struct DocumentationSectionHeading: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .commandlyFont(size: 11.5, weight: .medium)
                if let detail {
                    Text(detail)
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(SettingsPalette.border, lineWidth: 1)
                        }
                }
            }
            .accessibilityLabel(spokenKeys)
        }
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

private struct DocumentationExampleCard: View {
    let example: DocumentationExample

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(example.input)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)

            if let output = example.output {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .commandlyFont(size: 8, weight: .semibold)
                        .foregroundStyle(BrandPalette.accentSoft)
                        .accessibilityHidden(true)
                    Text(output)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if let detail = example.detail {
                Text(detail)
                    .commandlyFont(size: 9.5)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(SettingsPalette.border, lineWidth: 1)
        }
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(BrandPalette.accentSoft)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(callout.title)
                    .commandlyFont(size: 11.5, weight: .semibold)
                Text(callout.text)
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(BrandPalette.accent.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
    }
}

struct DocumentationBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .commandlyFont(size: 8.5, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct DocumentationMetadataPill: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(BrandPalette.accentSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .commandlyFont(size: 7.5, weight: .semibold)
                    .foregroundStyle(.quaternary)
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
    }
}

struct DocumentationInlineNotice: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).commandlyFont(size: 11, weight: .semibold)
                Text(text).commandlyFont(size: 10).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}
