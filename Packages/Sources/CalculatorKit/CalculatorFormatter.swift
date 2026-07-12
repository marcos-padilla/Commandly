import Foundation

/// Locale-aware formatting for calculator results.
enum CalculatorFormatter {
    static func formatDecimal(_ value: Decimal, locale: Locale, maximumFractionDigits: Int = 10) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    static func formatDouble(_ value: Double, locale: Locale, maximumFractionDigits: Int = 10) -> String {
        guard value.isFinite else { return "∞" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func formatUnformatted(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func formatDate(_ date: Date, locale: Locale, calendar: Calendar, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func formatTimeZoneInstant(
        _ value: CalculatorTimeZoneValue,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        guard let zone = TimeZone(identifier: value.timeZoneIdentifier) else {
            return ISO8601DateFormatter().string(from: value.instant)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let formatted = formatter.string(from: value.instant)
        let abbrev = zone.abbreviation(for: value.instant) ?? zone.identifier
        return "\(formatted) \(abbrev)"
    }

    static func formatMeasurement(_ value: CalculatorMeasurementValue, locale: Locale) -> String {
        if let formatted = value.formatted {
            return formatted
        }
        let number = formatDouble(value.value, locale: locale, maximumFractionDigits: 6)
        return "\(number) \(value.unitSymbol)"
    }

    static func formatCurrency(_ value: CalculatorCurrencyValue, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = value.code.rawValue
        return formatter.string(from: NSDecimalNumber(decimal: value.amount))
            ?? "\(formatDecimal(value.amount, locale: locale)) \(value.code.rawValue)"
    }

    static func formatPrimary(_ value: CalculatorValue, context: CalculatorEvaluationContext) -> String {
        switch value {
        case .decimal(let decimal):
            return formatDecimal(decimal, locale: context.locale)
        case .double(let double):
            return formatDouble(double, locale: context.locale)
        case .date(let date):
            return formatDate(date, locale: context.locale, calendar: context.calendar, timeZone: context.timeZone)
        case .measurement(let measurement):
            return formatMeasurement(measurement, locale: context.locale)
        case .currency(let currency):
            return formatCurrency(currency, locale: context.locale)
        case .timeZoneInstant(let instant):
            return formatTimeZoneInstant(instant, locale: context.locale, calendar: context.calendar)
        }
    }
}
