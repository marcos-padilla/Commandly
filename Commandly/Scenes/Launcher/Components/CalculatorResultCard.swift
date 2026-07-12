import SwiftUI
import DesignSystem
import CalculatorKit

/// Distinctive two-pane calculator answer card pinned above normal launcher results.
struct CalculatorResultCard: View {
    let result: CalculatorResult
    let isSelected: Bool
    var onSelect: () -> Void
    var onConfirm: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        Button {
            onSelect()
            onConfirm()
        } label: {
            HStack(spacing: 0) {
                pane(
                    primary: questionText,
                    badge: "Question",
                    alignment: .leading
                )

                dividerWithArrow

                pane(
                    primary: result.formattedPrimaryValue,
                    badge: resultCaption,
                    alignment: .leading
                )
            }
            .padding(.horizontal, density.spacing(.md))
            .padding(.vertical, density.spacing(.md))
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            .background(cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                    .strokeBorder(
                        isSelected ? BrandPalette.accent.opacity(0.55) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, density.spacing(.xs))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Calculator result \(result.formattedPrimaryValue), expression \(questionText)"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Copies the result")
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
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 4)

            Image(systemName: "arrow.right")
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(6)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                )
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
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
            .fill(Color.primary.opacity(isSelected ? 0.10 : 0.06))
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
