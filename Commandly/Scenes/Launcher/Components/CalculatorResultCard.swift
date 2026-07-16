import SwiftUI
import DesignSystem
import CalculatorKit
import CommandKit

/// Distinctive two-pane calculator answer card pinned above normal launcher results.
struct CalculatorResultCard: View {
    let result: CalculatorResult
    let isSelected: Bool
    let actions: [CommandActionDescriptor]
    var onSelect: () -> Void
    var onEditQuestion: () -> Void
    var onCopyAnswer: () -> Void
    var onAction: (CommandActionID) -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onSelect()
                onEditQuestion()
            } label: {
                pane(
                    primary: questionText,
                    badge: "Edit Question",
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit calculation question")
            .accessibilityValue(questionText)
            .accessibilityHint("Moves the question to the search field for editing")

            dividerWithArrow

            ZStack(alignment: .bottomTrailing) {
                Button {
                    onSelect()
                    onCopyAnswer()
                } label: {
                    pane(
                        primary: result.formattedPrimaryValue,
                        badge: resultCaption,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy calculator answer")
                .accessibilityValue(result.formattedPrimaryValue)
                .accessibilityHint("Copies the answer without closing Commandly")

                Menu {
                    ForEach(actions) { action in
                        Button(action.title) {
                            onAction(action.id)
                        }
                        .disabled(action.isEnabled == false)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .commandlyFont(size: 14, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Calculator actions")
                .accessibilityLabel("Calculator actions")
                .padding(.trailing, 2)
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.md))
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous))
        .padding(.horizontal, density.spacing(.xs))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var questionText: String {
        if result.displayExpression.isEmpty == false {
            return result.displayExpression
        }
        return result.originalInput
    }

    private var resultCaption: String {
        CalculatorResultCaption.caption(for: result)
    }

    private var dividerWithArrow: some View {
        ZStack {
            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(width: 1)
                .padding(.vertical, 4)

            Image(systemName: "arrow.right")
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(4)
        }
        .frame(width: 28)
        .padding(.horizontal, density.spacing(.xs))
    }

    private func pane(primary: String, badge: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: density.spacing(.xs)) {
            Text(primary)
                .commandlyFont(size: 22, weight: .semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))

            Text(badge)
                .commandlyFont(size: 11, weight: .medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
            .fill(Color.primary.opacity(isSelected ? 0.105 : 0.035))
    }
}

/// Secondary caption under the numeric result (word form when practical).
enum CalculatorResultCaption {
    static func caption(for result: CalculatorResult) -> String {
        if case .decimal(let value) = result.primaryValue,
           let words = NumberToWords.english(for: value) {
            return words.capitalized
        }
        if case .measurement(let measurement) = result.primaryValue {
            return measurement.unitSymbol
        }
        if case .currency(let currency) = result.primaryValue {
            return currency.code.rawValue
        }
        if case .date = result.primaryValue {
            return "Date"
        }
        if case .timeZoneInstant = result.primaryValue {
            return "Time"
        }
        return result.kind.rawValue
            .replacingOccurrences(of: "Conversion", with: "")
            .replacingOccurrences(of: "Calculation", with: "")
            .capitalized
    }
}

/// Small integer → English words helper for calculator captions.
enum NumberToWords {
    static func english(for decimal: Decimal) -> String? {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard rounded == decimal else { return nil }
        let number = NSDecimalNumber(decimal: rounded).intValue
        guard number >= 0, number <= 9999 else { return nil }
        return words(number)
    }

    private static func words(_ n: Int) -> String {
        let ones = [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
            "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
            "seventeen", "eighteen", "nineteen",
        ]
        let tens = [
            "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        ]
        if n < 20 { return ones[n] }
        if n < 100 {
            let t = n / 10
            let o = n % 10
            return o == 0 ? tens[t] : "\(tens[t])-\(ones[o])"
        }
        if n < 1000 {
            let h = n / 100
            let rest = n % 100
            return rest == 0 ? "\(ones[h]) hundred" : "\(ones[h]) hundred \(words(rest))"
        }
        let th = n / 1000
        let rest = n % 1000
        return rest == 0 ? "\(words(th)) thousand" : "\(words(th)) thousand \(words(rest))"
    }
}
