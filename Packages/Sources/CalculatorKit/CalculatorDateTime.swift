import Foundation

/// Date arithmetic and time-zone conversion.
enum CalculatorDateTime {
    struct DateResult: Sendable, Equatable {
        let date: Date
        let metadata: CalculatorResultMetadata
        let displayExpression: String
        let kind: CalculatorResultKind
    }

    struct TimeZoneResult: Sendable, Equatable {
        let value: CalculatorTimeZoneValue
        let metadata: CalculatorResultMetadata
        let displayExpression: String
    }

    // MARK: - Place / zone detection

    static func looksLikePlaceOrZone(_ input: String) -> Bool {
        let lowered = input.lowercased()
        if zoneAliasMap.keys.contains(where: { lowered.contains($0) }) {
            return true
        }
        // IANA-looking token
        if lowered.range(of: #"[a-z]+/[a-z_]+"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    // MARK: - Date evaluation

    static func evaluateDate(_ text: String, context: CalculatorEvaluationContext) throws -> DateResult {
        var calendar = context.calendar
        calendar.timeZone = context.timeZone
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let now = context.now

        // N days/weeks/months/years from now/today
        if let match = match(#"^(\d+)\s+(days?|weeks?|months?|years?)\s+from\s+(now|today)$"#, in: lowered) {
            let amount = Int(match.g1) ?? 0
            let unit = match.g2
            var components = DateComponents()
            switch unit.prefix(3) {
            case "day": components.day = amount
            case "wee": components.day = amount * 7
            case "mon": components.month = amount
            case "yea": components.year = amount
            default: break
            }
            guard let date = calendar.date(byAdding: components, to: now) else {
                throw CalculatorError.invalidDateExpression
            }
            return DateResult(
                date: date,
                metadata: CalculatorResultMetadata(notes: ["Relative to now"]),
                displayExpression: text.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .dateCalculation
            )
        }

        // N days after/before <date>
        if let match = match(#"^(\d+)\s+days?\s+(after|before)\s+(.+)$"#, in: lowered) {
            let amount = Int(match.g1) ?? 0
            let direction = match.g2
            guard let base = parseDate(match.g3, calendar: calendar, now: now, locale: context.locale) else {
                throw CalculatorError.invalidDateExpression
            }
            let delta = direction == "after" ? amount : -amount
            guard let date = calendar.date(byAdding: .day, value: delta, to: base) else {
                throw CalculatorError.invalidDateExpression
            }
            return DateResult(
                date: date,
                metadata: CalculatorResultMetadata(),
                displayExpression: text.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .dateCalculation
            )
        }

        // days until <date>
        if let match = match(#"^days?\s+until\s+(.+)$"#, in: lowered) {
            guard let target = parseDate(match.g1, calendar: calendar, now: now, locale: context.locale) else {
                throw CalculatorError.invalidDateExpression
            }
            let start = calendar.startOfDay(for: now)
            let end = calendar.startOfDay(for: target)
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            // Encode day count as date metadata + use a sentinel via notes; service maps to decimal.
            var metadata = CalculatorResultMetadata()
            metadata.notes.append("dayCount:\(days)")
            // Use now as primary date placeholder; service will detect dayCount.
            return DateResult(
                date: target,
                metadata: metadata,
                displayExpression: text.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .dateCalculation
            )
        }

        // weeks between A and B
        if let match = match(#"^weeks?\s+between\s+(.+?)\s+and\s+(.+)$"#, in: lowered) {
            guard let a = parseDate(match.g1, calendar: calendar, now: now, locale: context.locale),
                  let b = parseDate(match.g2, calendar: calendar, now: now, locale: context.locale)
            else {
                throw CalculatorError.invalidDateExpression
            }
            let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0)
            let weeks = days / 7
            var metadata = CalculatorResultMetadata()
            metadata.notes.append("weekCount:\(weeks)")
            return DateResult(
                date: b,
                metadata: metadata,
                displayExpression: text.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .dateCalculation
            )
        }

        // next/last weekday
        if let match = match(#"^(next|last)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$"#, in: lowered) {
            let direction = match.g1
            guard let weekday = weekdayNumber(match.g2) else {
                throw CalculatorError.invalidDateExpression
            }
            let date = try nextWeekday(weekday, direction: direction, from: now, calendar: calendar)
            return DateResult(
                date: date,
                metadata: CalculatorResultMetadata(),
                displayExpression: text.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .dateCalculation
            )
        }

        if lowered == "end of this month" {
            guard let interval = calendar.dateInterval(of: .month, for: now),
                  let end = calendar.date(byAdding: .second, value: -1, to: interval.end)
            else {
                throw CalculatorError.invalidDateExpression
            }
            return DateResult(date: end, metadata: .init(), displayExpression: "end of this month", kind: .dateCalculation)
        }

        if lowered == "start of next year" {
            let year = calendar.component(.year, from: now) + 1
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            guard let date = calendar.date(from: components) else {
                throw CalculatorError.invalidDateExpression
            }
            return DateResult(date: date, metadata: .init(), displayExpression: "start of next year", kind: .dateCalculation)
        }

        throw CalculatorError.invalidDateExpression
    }

    // MARK: - Time zone evaluation

    static func evaluateTimeZone(_ text: String, context: CalculatorEvaluationContext) throws -> TimeZoneResult {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = match(#"^current time in\s+(.+)$"#, in: lowered) {
            let zone = try resolveTimeZone(match.g1)
            return TimeZoneResult(
                value: CalculatorTimeZoneValue(
                    instant: context.now,
                    timeZoneIdentifier: zone.identifier,
                    sourceTimeZoneIdentifier: context.timeZone.identifier
                ),
                metadata: CalculatorResultMetadata(
                    fromTimeZone: context.timeZone.identifier,
                    toTimeZone: zone.identifier
                ),
                displayExpression: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // 5pm New York in Tokyo / 9:30 am miami to london / noon pst in est
        if let match = match(
            #"^(noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)?|\d{1,2}:\d{2})\s+(.+?)\s+(?:in|to)\s+(.+)$"#,
            in: lowered
        ) {
            let timeText = match.g1
            let fromName = match.g2.trimmingCharacters(in: .whitespacesAndNewlines)
            let toName = match.g3.trimmingCharacters(in: .whitespacesAndNewlines)
            let fromZone = try resolveTimeZone(fromName)
            let toZone = try resolveTimeZone(toName)
            let instant = try combine(timeText: timeText, on: context.now, in: fromZone, calendar: context.calendar)
            return TimeZoneResult(
                value: CalculatorTimeZoneValue(
                    instant: instant,
                    timeZoneIdentifier: toZone.identifier,
                    sourceTimeZoneIdentifier: fromZone.identifier
                ),
                metadata: CalculatorResultMetadata(
                    fromTimeZone: fromZone.identifier,
                    toTimeZone: toZone.identifier
                ),
                displayExpression: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if let match = match(#"^time difference between\s+(.+?)\s+and\s+(.+)$"#, in: lowered) {
            let a = try resolveTimeZone(match.g1)
            let b = try resolveTimeZone(match.g2)
            let offsetA = a.secondsFromGMT(for: context.now)
            let offsetB = b.secondsFromGMT(for: context.now)
            let hours = Decimal(offsetB - offsetA) / 3600
            var metadata = CalculatorResultMetadata(fromTimeZone: a.identifier, toTimeZone: b.identifier)
            metadata.notes.append("offsetHours:\(hours)")
            return TimeZoneResult(
                value: CalculatorTimeZoneValue(
                    instant: context.now,
                    timeZoneIdentifier: b.identifier,
                    sourceTimeZoneIdentifier: a.identifier
                ),
                metadata: metadata,
                displayExpression: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        throw CalculatorError.invalidDateExpression
    }

    // MARK: - Helpers

    private static let ambiguousAbbreviations: Set<String> = [
        "cst", "ist", "bst", "pst", "est", "mst", "ast", "cdt", "edt", "mdt", "pdt",
    ]

    private static let zoneAliasMap: [String: String] = [
        "new york": "America/New_York",
        "nyc": "America/New_York",
        "tokyo": "Asia/Tokyo",
        "london": "Europe/London",
        "miami": "America/New_York",
        "madrid": "Europe/Madrid",
        "sydney": "Australia/Sydney",
        "paris": "Europe/Paris",
        "berlin": "Europe/Berlin",
        "chicago": "America/Chicago",
        "los angeles": "America/Los_Angeles",
        "la": "America/Los_Angeles",
        "san francisco": "America/Los_Angeles",
        "utc": "UTC",
        "gmt": "GMT",
        "singapore": "Asia/Singapore",
        "hong kong": "Asia/Hong_Kong",
        "dubai": "Asia/Dubai",
        "toronto": "America/Toronto",
        "vancouver": "America/Vancouver",
    ]

    static func resolveTimeZone(_ raw: String) throws -> TimeZone {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ambiguousAbbreviations.contains(name) {
            throw CalculatorError.ambiguousTimeZone(raw)
        }
        if let identifier = zoneAliasMap[name], let zone = TimeZone(identifier: identifier) {
            return zone
        }
        // Try as IANA directly (preserve original casing for path).
        if let zone = TimeZone(identifier: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return zone
        }
        // Title-case city words
        if let identifier = zoneAliasMap[name], let zone = TimeZone(identifier: identifier) {
            return zone
        }
        throw CalculatorError.ambiguousTimeZone(raw)
    }

    private static func combine(timeText: String, on day: Date, in zone: TimeZone, calendar: Calendar) throws -> Date {
        var calendar = calendar
        calendar.timeZone = zone

        let trimmed = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        var hour = 0
        var minute = 0

        if trimmed == "noon" {
            hour = 12
        } else if trimmed == "midnight" {
            hour = 0
        } else {
            let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#
            guard let match = match(pattern, in: trimmed) else {
                throw CalculatorError.invalidDateExpression
            }
            hour = Int(match.g1) ?? 0
            minute = Int(match.g2.isEmpty ? "0" : match.g2) ?? 0
            let meridiem = match.g3
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components) else {
            throw CalculatorError.invalidDateExpression
        }
        return date
    }

    private static func parseDate(_ text: String, calendar: Calendar, now: Date, locale: Locale) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.calendar = calendar

        let formats = [
            "MMMM d yyyy",
            "MMMM d, yyyy",
            "MMM d yyyy",
            "MMM d, yyyy",
            "MMMM d",
            "MMM d",
            "d MMMM yyyy",
            "yyyy-MM-dd",
            "M/d/yyyy",
            "M/d",
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                // If year missing, pick next occurrence on/after today (future-oriented).
                if !format.contains("y") {
                    return futureOriented(date, from: now, calendar: calendar)
                }
                return date
            }
        }
        return nil
    }

    /// Dates without a year resolve to the next matching month/day on or after `now`.
    private static func futureOriented(_ partial: Date, from now: Date, calendar: Calendar) -> Date {
        let month = calendar.component(.month, from: partial)
        let day = calendar.component(.day, from: partial)
        let year = calendar.component(.year, from: now)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        if let candidate = calendar.date(from: components) {
            if calendar.startOfDay(for: candidate) >= calendar.startOfDay(for: now) {
                return candidate
            }
        }
        components.year = year + 1
        return calendar.date(from: components) ?? partial
    }

    private static func weekdayNumber(_ name: String) -> Int? {
        switch name {
        case "sunday": return 1
        case "monday": return 2
        case "tuesday": return 3
        case "wednesday": return 4
        case "thursday": return 5
        case "friday": return 6
        case "saturday": return 7
        default: return nil
        }
    }

    private static func nextWeekday(_ weekday: Int, direction: String, from now: Date, calendar: Calendar) throws -> Date {
        let current = calendar.component(.weekday, from: now)
        var delta = weekday - current
        if direction == "next" {
            if delta <= 0 { delta += 7 }
        } else {
            if delta >= 0 { delta -= 7 }
        }
        guard let date = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now)) else {
            throw CalculatorError.invalidDateExpression
        }
        return date
    }

    private struct RegexMatch: Sendable {
        let g1: String
        let g2: String
        let g3: String
    }

    private static func match(_ pattern: String, in text: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        func group(_ index: Int) -> String {
            guard index < match.numberOfRanges,
                  let r = Range(match.range(at: index), in: text),
                  match.range(at: index).location != NSNotFound
            else {
                return ""
            }
            return String(text[r])
        }
        return RegexMatch(g1: group(1), g2: group(2), g3: group(3))
    }
}
