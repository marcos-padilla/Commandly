import Foundation

/// Deterministic calendar calculations. Partial dates resolve to their next occurrence.
enum CalculatorCalendar {
    struct Result: Sendable, Equatable {
        let primaryValue: CalculatorValue
        let formattedPrimaryValue: String?
        let metadata: CalculatorResultMetadata
        let displayExpression: String
    }

    static func evaluate(_ input: String, context: CalculatorEvaluationContext) throws -> Result? {
        var text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("how many days until ") {
            text = "days until " + text.dropFirst("how many days until ".count)
        }
        var calendar = context.calendar
        calendar.timeZone = context.timeZone
        let today = calendar.startOfDay(for: context.now)

        if let result = currentDate(text, today: today, calendar: calendar) { return result }
        if isStandaloneDate(text) {
            guard let date = parseStandaloneDate(text, now: today, calendar: calendar, locale: context.locale) else {
                throw CalculatorError.invalidDateExpression
            }
            return dateResult(date, text, notes: ["Interpreted using locale \(context.locale.identifier) and time zone \(context.timeZone.identifier)."])
        }
        if let result = relativePeriod(text, today: today, calendar: calendar, context: context) { return result }
        if let result = weekdayNavigation(text, today: today, calendar: calendar, context: context) { return result }
        if let result = periodBoundary(text, today: today, calendar: calendar) { return result }
        if let result = try difference(text, today: today, calendar: calendar, context: context) { return result }
        if let result = try weekAndQuarter(text, today: today, calendar: calendar, context: context) { return result }
        if let result = try businessDays(text, today: today, calendar: calendar, context: context) { return result }
        if let result = try ageAndBirthday(text, today: today, calendar: calendar, context: context) { return result }
        if let result = try formattedDate(text, today: today, calendar: calendar, context: context) { return result }
        return nil
    }

    private static func currentDate(_ text: String, today: Date, calendar: Calendar) -> Result? {
        let offsets = [
            "today": 0, "today's date": 0, "current date": 0,
            "tomorrow": 1, "day after tomorrow": 2,
            "yesterday": -1, "day before yesterday": -2,
        ]
        guard let offset = offsets[text], let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
        return dateResult(date, text)
    }

    private static func isStandaloneDate(_ text: String) -> Bool {
        text.range(of: #"^\d{1,2}/\d{1,2}(?:/\d{4})?$"#, options: .regularExpression) != nil
            || text.range(of: #"^[a-z]+\s+\d{1,2}(?:,?\s+\d{4})?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func parseStandaloneDate(_ text: String, now: Date, calendar: Calendar, locale: Locale) -> Date? {
        if let groups = captures(#"^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?$"#, text),
           let first = Int(groups[0]), let second = Int(groups[1]) {
            let monthFirst = ["US", "CA", "PH"].contains(locale.region?.identifier ?? "")
            let month = monthFirst ? first : second
            let day = monthFirst ? second : first
            var year = Int(groups[2]) ?? calendar.component(.year, from: now)
            guard var date = validMonthDay(month: month, day: day, year: year, calendar: calendar) else { return nil }
            if groups[2].isEmpty, date < now {
                year += 1
                guard let future = validMonthDay(month: month, day: day, year: year, calendar: calendar) else { return nil }
                date = future
            }
            return date
        }
        return parseDate(text, now: now, calendar: calendar, locale: locale, futurePartial: true)
    }

    private static func relativePeriod(
        _ text: String,
        today: Date,
        calendar: Calendar,
        context: CalculatorEvaluationContext
    ) -> Result? {
        let namedOffsets: [String: DateComponents] = [
            "next week": DateComponents(day: 7), "last week": DateComponents(day: -7),
            "week after next": DateComponents(day: 14),
            "next month": DateComponents(month: 1), "last month": DateComponents(month: -1),
            "month after next": DateComponents(month: 2),
            "next year": DateComponents(year: 1), "last year": DateComponents(year: -1),
        ]
        if let components = namedOffsets[text], let date = add(components, to: today, calendar: calendar) {
            return dateResult(date, text, notes: monthEndNote(components))
        }

        if let groups = captures(#"^(\d+)\s+(days?|weeks?|months?|years?)\s+(?:from\s+(?:now|today)|after\s+today|ago)$"#, text) {
            guard let amount = Int(groups[0]) else { return nil }
            let sign = text.hasSuffix("ago") ? -1 : 1
            guard let date = add(component(amount * sign, unit: groups[1]), to: today, calendar: calendar) else { return nil }
            return dateResult(date, text, notes: groups[1].hasPrefix("month") || groups[1].hasPrefix("year") ? ["Month-end dates clamp to the last valid day."] : [])
        }

        if let groups = captures(#"^(.+?)\s+(?:\+|plus|minus|-)\s+(\d+)\s+(days?|weeks?|months?|years?)$"#, text) {
            guard let base = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale, futurePartial: false),
                  let amount = Int(groups[1]) else { return nil }
            let negative = text.contains(" minus ") || text.contains(" - ")
            guard let date = add(component(negative ? -amount : amount, unit: groups[2]), to: base, calendar: calendar) else { return nil }
            return dateResult(date, text, notes: monthEndNote(component(amount, unit: groups[2])))
        }

        if let groups = captures(#"^(\d+)\s+(days?|weeks?|months?|years?)\s+(after|before)\s+(.+)$"#, text) {
            guard let amount = Int(groups[0]),
                  let base = parseDate(groups[3], now: today, calendar: calendar, locale: context.locale, futurePartial: false) else { return nil }
            let signed = groups[2] == "before" ? -amount : amount
            guard let date = add(component(signed, unit: groups[1]), to: base, calendar: calendar) else { return nil }
            return dateResult(date, text, notes: monthEndNote(component(signed, unit: groups[1])))
        }

        if let result = multiUnitRelative(text, today: today, calendar: calendar, context: context) { return result }
        return nil
    }

    private static func multiUnitRelative(
        _ text: String,
        today: Date,
        calendar: Calendar,
        context: CalculatorEvaluationContext
    ) -> Result? {
        guard text.contains("from now") || text.contains(" after ") || text.hasSuffix("ago") else { return nil }
        let anchor: Date
        let prefix: String
        let sign: Int
        if text.hasSuffix("from now") {
            anchor = today
            prefix = String(text.dropLast("from now".count))
            sign = 1
        } else if text.hasSuffix("ago") {
            anchor = today
            prefix = String(text.dropLast("ago".count))
            sign = -1
        } else if let range = text.range(of: " after ") {
            prefix = String(text[..<range.lowerBound])
            guard let parsed = parseDate(String(text[range.upperBound...]), now: today, calendar: calendar, locale: context.locale, futurePartial: false) else { return nil }
            anchor = parsed
            sign = 1
        } else {
            return nil
        }
        let clean = prefix.replacingOccurrences(of: " and ", with: " ")
        guard let components = durationComponents(clean, sign: sign),
              let date = add(components, to: anchor, calendar: calendar) else { return nil }
        return dateResult(date, text, notes: monthEndNote(components))
    }

    private static func weekdayNavigation(
        _ text: String,
        today: Date,
        calendar: Calendar,
        context: CalculatorEvaluationContext
    ) -> Result? {
        if let groups = captures(#"^(next|last|previous|this)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$"#, text),
           let weekday = weekday(groups[1]) {
            let current = calendar.component(.weekday, from: today)
            var delta = weekday - current
            switch groups[0] {
            case "next": if delta <= 0 { delta += 7 }
            case "last", "previous": if delta >= 0 { delta -= 7 }
            default: break
            }
            guard let date = calendar.date(byAdding: .day, value: delta, to: today) else { return nil }
            return dateResult(date, text, notes: groups[0] == "next" ? ["‘Next’ excludes today."] : [])
        }
        if let groups = captures(#"^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+after\s+next$"#, text),
           let weekday = weekday(groups[0]),
           let nextWeek = calendar.date(byAdding: .day, value: 7, to: today),
           let date = nextMatchingWeekday(weekday, after: nextWeek, inclusive: true, calendar: calendar) {
            return dateResult(date, text)
        }
        if let groups = captures(#"^(first|second|third|fourth|fifth|last)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+(?:of|in)\s+(.+)$"#, text),
           let weekdayValue = weekday(groups[1]),
           let monthDate = parseMonthReference(groups[2], now: today, calendar: calendar, locale: context.locale),
           let date = nthWeekday(groups[0], weekday: weekdayValue, inMonthContaining: monthDate, calendar: calendar) {
            return dateResult(date, text)
        }
        return nil
    }

    private static func periodBoundary(_ text: String, today: Date, calendar: Calendar) -> Result? {
        if text == "start of today" { return dateResult(today, text) }
        if text == "end of today", let date = calendar.date(byAdding: .second, value: -1, to: calendar.date(byAdding: .day, value: 1, to: today) ?? today) {
            return dateResult(date, text)
        }
        guard let groups = captures(#"^(start|end|first day|last day) of (this|next) (week|month|year)$"#, text) else { return nil }
        let component: Calendar.Component = groups[2] == "week" ? .weekOfYear : groups[2] == "month" ? .month : .year
        var reference = today
        if groups[1] == "next", let next = calendar.date(byAdding: component, value: 1, to: reference) { reference = next }
        guard let interval = calendar.dateInterval(of: component, for: reference) else { return nil }
        let wantsEnd = groups[0] == "end" || groups[0] == "last day"
        let date = wantsEnd ? (calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end) : interval.start
        return dateResult(date, text, notes: component == .weekOfYear ? ["Week boundaries use the configured calendar."] : [])
    }

    private static func difference(
        _ text: String,
        today: Date,
        calendar: Calendar,
        context: CalculatorEvaluationContext
    ) throws -> Result? {
        if let groups = captures(#"^(days?|weeks?|months?|years?)\s+(until|since)\s+(.+)$"#, text) {
            let target: Date
            if groups[2] == "my birthday" || groups[2] == "my next birthday" {
                guard let birthday = context.birthdayMonthDay,
                      let date = nextBirthday(birthday, from: today, calendar: calendar) else {
                    throw CalculatorError.invalidDateExpression
                }
                target = date
            } else if groups[2] == "christmas" {
                target = nextMonthDay(month: 12, day: 25, from: today, calendar: calendar) ?? today
            } else if let date = parseDate(groups[2], now: today, calendar: calendar, locale: context.locale, futurePartial: groups[1] == "until") {
                target = date
            } else { return nil }
            let from = groups[1] == "since" ? target : today
            let to = groups[1] == "since" ? today : target
            let value = calendarDifference(groups[0], from: from, to: to, calendar: calendar)
            return decimalResult(value, text, suffix: unitSuffix(groups[0]), notes: ["Calendar difference; date boundaries use the configured time zone."])
        }
        if let groups = captures(#"^(days?|weeks?|months?|years?|time)\s+between\s+(.+?)\s+and\s+(.+)$"#, text),
           let first = parseDate(groups[1], now: today, calendar: calendar, locale: context.locale, futurePartial: false),
           let second = parseDate(groups[2], now: today, calendar: calendar, locale: context.locale, futurePartial: false) {
            let value = calendarDifference(groups[0], from: first, to: second, calendar: calendar)
            return decimalResult(abs(value), text, suffix: unitSuffix(groups[0]), notes: ["Calendar difference; elapsed whole units are reported."])
        }
        return nil
    }

    private static func weekAndQuarter(
        _ text: String,
        today: Date,
        calendar: Calendar,
        context: CalculatorEvaluationContext
    ) throws -> Result? {
        if let groups = captures(#"^(?:week number for|what week is)\s+(.+)$"#, text),
           let date = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale) {
            return decimalResult(Decimal(calendar.component(.weekOfYear, from: date)), text, suffix: "")
        }
        if let groups = captures(#"^day of year for\s+(.+)$"#, text),
           let date = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale) {
            return decimalResult(Decimal(calendar.ordinality(of: .day, in: .year, for: date) ?? 0), text, suffix: "")
        }
        if let groups = captures(#"^what is the (\d+)(?:st|nd|rd|th) day of (\d{4})$"#, text),
           let ordinal = Int(groups[0]), let year = Int(groups[1]), ordinal > 0,
           let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
           let date = calendar.date(byAdding: .day, value: ordinal - 1, to: start),
           calendar.component(.year, from: date) == year {
            return dateResult(date, text)
        }
        if text == "current quarter" || text == "next quarter" {
            let current = ((calendar.component(.month, from: today) - 1) / 3) + 1
            let quarter = text == "next quarter" ? (current % 4) + 1 : current
            let year = calendar.component(.year, from: today) + (text == "next quarter" && current == 4 ? 1 : 0)
            return Result(
                primaryValue: .decimal(Decimal(quarter)),
                formattedPrimaryValue: "Q\(quarter) \(year)",
                metadata: .init(notes: ["Calendar quarter"]),
                displayExpression: text
            )
        }
        if let groups = captures(#"^(start|end) of q([1-4])(?:\s+(\d{4}))?$"#, text),
           let quarter = Int(groups[1]) {
            let year = Int(groups[2]) ?? calendar.component(.year, from: today)
            guard let start = calendar.date(from: DateComponents(year: year, month: (quarter - 1) * 3 + 1, day: 1)) else { return nil }
            if groups[0] == "start" { return dateResult(start, text) }
            guard let after = calendar.date(byAdding: .month, value: 3, to: start), let end = calendar.date(byAdding: .second, value: -1, to: after) else { return nil }
            return dateResult(end, text)
        }
        if text == "end of fourth quarter" || text == "last day of this quarter" {
            let quarter = text == "end of fourth quarter" ? 4 : ((calendar.component(.month, from: today) - 1) / 3) + 1
            guard let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: (quarter - 1) * 3 + 1, day: 1)),
                  let after = calendar.date(byAdding: .month, value: 3, to: start),
                  let end = calendar.date(byAdding: .second, value: -1, to: after) else { return nil }
            return dateResult(end, text)
        }
        if let groups = captures(#"^(\d+) days after the start of q([1-4])$"#, text),
           let days = Int(groups[0]), let quarter = Int(groups[1]),
           let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: (quarter - 1) * 3 + 1, day: 1)),
           let date = calendar.date(byAdding: .day, value: days, to: start) {
            return dateResult(date, text)
        }
        return nil
    }

    private static func businessDays(
        _ text: String,
        today: Date,
        calendar: Calendar,
        context: CalculatorEvaluationContext
    ) throws -> Result? {
        if text == "last business day of this month" {
            guard let interval = calendar.dateInterval(of: .month, for: today),
                  var date = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
            while !isBusinessDay(date, calendar: calendar, context: context) {
                guard let prior = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
                date = prior
            }
            return dateResult(date, text, notes: businessNotes(context))
        }
        if let groups = captures(#"^(\d+)\s+(business days?|working days?|weekdays?)\s+(from now|after|before)\s*(.*)$"#, text),
           let count = Int(groups[0]) {
            let anchor: Date
            if groups[2] == "from now" { anchor = today }
            else if let parsed = parseDate(groups[3], now: today, calendar: calendar, locale: context.locale, futurePartial: false) { anchor = parsed }
            else { return nil }
            let signed = groups[2] == "before" ? -count : count
            guard let date = addBusinessDays(signed, to: anchor, calendar: calendar, context: context) else { return nil }
            return dateResult(date, text, notes: businessNotes(context))
        }
        if let groups = captures(#"^business days? between\s+(.+?)\s+and\s+(.+)$"#, text),
           let first = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale, futurePartial: false),
           let second = parseDate(groups[1], now: today, calendar: calendar, locale: context.locale, futurePartial: false) {
            let count = countBusinessDays(from: first, to: second, calendar: calendar, context: context)
            return decimalResult(Decimal(count), text, suffix: " business days", notes: businessNotes(context))
        }
        return nil
    }

    private static func ageAndBirthday(
        _ text: String,
        today: Date,
        calendar: Calendar,
        context: CalculatorEvaluationContext
    ) throws -> Result? {
        if let groups = captures(#"^(?:age if born|how old is someone born)\s+(.+)$"#, text),
           let birth = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale, futurePartial: false) {
            let age = calendar.dateComponents([.year], from: birth, to: today).year ?? 0
            return decimalResult(Decimal(age), text, suffix: " years")
        }
        if let groups = captures(#"^age on\s+(.+?)\s+if born\s+(.+)$"#, text),
           let date = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale, futurePartial: false),
           let birth = parseDate(groups[1], now: today, calendar: calendar, locale: context.locale, futurePartial: false) {
            let age = calendar.dateComponents([.year], from: birth, to: date).year ?? 0
            return decimalResult(Decimal(age), text, suffix: " years")
        }
        if let groups = captures(#"^next birthday if born\s+(.+)$"#, text),
           let birth = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale, futurePartial: false) {
            let values = calendar.dateComponents([.month, .day], from: birth)
            guard let next = nextBirthday(values, from: today, calendar: calendar) else { return nil }
            return dateResult(next, text)
        }
        if text == "days until my next birthday" {
            guard let birthday = context.birthdayMonthDay, let date = nextBirthday(birthday, from: today, calendar: calendar) else {
                throw CalculatorError.invalidDateExpression
            }
            let days = calendar.dateComponents([.day], from: today, to: date).day ?? 0
            return decimalResult(Decimal(days), text, suffix: " days")
        }
        if text == "what day of the week is my birthday this year" {
            guard let birthday = context.birthdayMonthDay,
                  let month = birthday.month, let day = birthday.day,
                  let date = validMonthDay(month: month, day: day, year: calendar.component(.year, from: today), calendar: calendar) else {
                throw CalculatorError.invalidDateExpression
            }
            let formatter = DateFormatter()
            formatter.locale = context.locale
            formatter.calendar = calendar
            formatter.timeZone = context.timeZone
            formatter.dateFormat = "EEEE"
            return Result(primaryValue: .date(date), formattedPrimaryValue: formatter.string(from: date), metadata: .init(), displayExpression: text)
        }
        return nil
    }

    private static func formattedDate(
        _ text: String,
        today: Date,
        calendar: Calendar,
        context: CalculatorEvaluationContext
    ) throws -> Result? {
        if let groups = captures(#"^(?:timestamp\s+)?(\d{10,13})(?:\s+milliseconds)?\s+as date$"#, text),
           let raw = Double(groups[0]) {
            let seconds = groups[0].count >= 13 || text.contains("milliseconds") ? raw / 1_000 : raw
            return dateResult(Date(timeIntervalSince1970: seconds), text)
        }
        if let groups = captures(#"^format\s+(.+?)\s+as iso$"#, text),
           let date = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale, futurePartial: false) {
            return Result(primaryValue: .date(date), formattedPrimaryValue: isoDate(date, calendar: calendar), metadata: .init(), displayExpression: text)
        }
        if let groups = captures(#"^(.+?)\s+(?:as unix timestamp|as epoch)$"#, text),
           let date = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale, futurePartial: false) {
            let timestamp = Decimal(Int(date.timeIntervalSince1970))
            return decimalResult(timestamp, text, suffix: "")
        }
        if let groups = captures(#"^(.+?)\s+in (us|short|medium|long) format$"#, text),
           let date = parseDate(groups[0], now: today, calendar: calendar, locale: context.locale, futurePartial: false) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = context.timeZone
            formatter.locale = groups[1] == "us" ? Locale(identifier: "en_US") : context.locale
            formatter.dateStyle = groups[1] == "long" ? .long : groups[1] == "medium" ? .medium : .short
            formatter.timeStyle = .none
            return Result(primaryValue: .date(date), formattedPrimaryValue: formatter.string(from: date), metadata: .init(), displayExpression: text)
        }
        return nil
    }

    // MARK: - Calendar helpers

    private static func add(_ components: DateComponents, to date: Date, calendar: Calendar) -> Date? {
        var result = date
        if let years = components.year, years != 0 { result = addMonthsClamped(years * 12, to: result, calendar: calendar) ?? result }
        if let months = components.month, months != 0 { result = addMonthsClamped(months, to: result, calendar: calendar) ?? result }
        var remainder = DateComponents()
        remainder.day = (components.day ?? 0) + (components.weekOfYear ?? 0) * 7
        return calendar.date(byAdding: remainder, to: result)
    }

    private static func addMonthsClamped(_ months: Int, to date: Date, calendar: Calendar) -> Date? {
        let originalDay = calendar.component(.day, from: date)
        guard let first = calendar.date(from: DateComponents(
            year: calendar.component(.year, from: date), month: calendar.component(.month, from: date), day: 1,
            hour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date),
            second: calendar.component(.second, from: date)
        )), let targetFirst = calendar.date(byAdding: .month, value: months, to: first),
           let range = calendar.range(of: .day, in: .month, for: targetFirst) else { return nil }
        return calendar.date(bySetting: .day, value: min(originalDay, range.count), of: targetFirst)
    }

    private static func component(_ amount: Int, unit: String) -> DateComponents {
        switch unit.prefix(3) {
        case "day": return DateComponents(day: amount)
        case "wee": return DateComponents(day: amount * 7)
        case "mon": return DateComponents(month: amount)
        default: return DateComponents(year: amount)
        }
    }

    private static func durationComponents(_ text: String, sign: Int) -> DateComponents? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s+(years?|months?|weeks?|days?)"#, options: .caseInsensitive) else { return nil }
        var result = DateComponents()
        var matchCount = 0
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: nsRange) {
            guard let amountRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text),
                  let amount = Int(text[amountRange]) else { continue }
            matchCount += 1
            switch text[unitRange].prefix(3) {
            case "yea": result.year = (result.year ?? 0) + amount * sign
            case "mon": result.month = (result.month ?? 0) + amount * sign
            case "wee": result.day = (result.day ?? 0) + amount * 7 * sign
            default: result.day = (result.day ?? 0) + amount * sign
            }
        }
        return matchCount > 0 ? result : nil
    }

    private static func monthEndNote(_ value: DateComponents) -> [String] {
        value.month != nil || value.year != nil ? ["Month-end and leap-day results clamp to the last valid day."] : []
    }

    private static func parseDate(
        _ raw: String,
        now: Date,
        calendar: Calendar,
        locale: Locale,
        futurePartial: Bool = true
    ) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "today" || text == "now" { return now }
        if text == "tomorrow" { return calendar.date(byAdding: .day, value: 1, to: now) }
        if text == "yesterday" { return calendar.date(byAdding: .day, value: -1, to: now) }
        if let weekdayValue = weekday(text) { return nextMatchingWeekday(weekdayValue, after: now, inclusive: true, calendar: calendar) }
        let format: String
        if text.range(of: #"^\d{4}-\d{1,2}-\d{1,2}$"#, options: .regularExpression) != nil {
            format = "yyyy-MM-dd"
        } else if text.range(of: #"^\d{1,2}/\d{1,2}/\d{4}$"#, options: .regularExpression) != nil {
            format = "M/d/yyyy"
        } else if text.range(of: #"^\d{1,2}/\d{1,2}$"#, options: .regularExpression) != nil {
            format = "M/d"
        } else if text.range(of: #"^[a-z]+\s+\d{1,2},?\s+\d{4}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            format = text.contains(",") ? "MMMM d, yyyy" : "MMMM d yyyy"
        } else if text.range(of: #"^[a-z]+\s+\d{4}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            format = "MMMM yyyy"
        } else if text.range(of: #"^[a-z]+\s+\d{1,2}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            format = "MMMM d"
        } else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        let hasExplicitYear = text.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil
        formatter.dateFormat = format
        guard let parsed = formatter.date(from: text) else { return nil }
        if hasExplicitYear { return parsed }
        let month = calendar.component(.month, from: parsed)
        let day = calendar.component(.day, from: parsed)
        let year = calendar.component(.year, from: now)
        guard let current = validMonthDay(month: month, day: day, year: year, calendar: calendar) else { return nil }
        if !futurePartial || current >= calendar.startOfDay(for: now) { return current }
        return validMonthDay(month: month, day: day, year: year + 1, calendar: calendar)
    }

    private static func parseMonthReference(_ text: String, now: Date, calendar: Calendar, locale: Locale) -> Date? {
        if text == "next month" { return calendar.date(byAdding: .month, value: 1, to: now) }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM"
        guard let parsed = formatter.date(from: text), let month = Optional(calendar.component(.month, from: parsed)) else { return nil }
        var year = calendar.component(.year, from: now)
        if month < calendar.component(.month, from: now) { year += 1 }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    private static func validMonthDay(month: Int, day: Int, year: Int, calendar: Calendar) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func nextMonthDay(month: Int, day: Int, from date: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: date)
        if let current = validMonthDay(month: month, day: day, year: year, calendar: calendar), current >= date { return current }
        return validMonthDay(month: month, day: day, year: year + 1, calendar: calendar)
    }

    private static func weekday(_ name: String) -> Int? {
        ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7][name]
    }

    private static func nextMatchingWeekday(_ target: Int, after date: Date, inclusive: Bool, calendar: Calendar) -> Date? {
        let current = calendar.component(.weekday, from: date)
        var delta = target - current
        if delta < 0 || (!inclusive && delta == 0) { delta += 7 }
        return calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: date))
    }

    private static func nthWeekday(_ ordinal: String, weekday: Int, inMonthContaining date: Date, calendar: Calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        if ordinal == "last" {
            guard let final = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
            let delta = (calendar.component(.weekday, from: final) - weekday + 7) % 7
            return calendar.date(byAdding: .day, value: -delta, to: final)
        }
        let number = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5][ordinal] ?? 1
        guard let first = nextMatchingWeekday(weekday, after: interval.start, inclusive: true, calendar: calendar),
              let result = calendar.date(byAdding: .day, value: (number - 1) * 7, to: first), result < interval.end else { return nil }
        return result
    }

    private static func calendarDifference(_ unit: String, from: Date, to: Date, calendar: Calendar) -> Decimal {
        let a = calendar.startOfDay(for: from), b = calendar.startOfDay(for: to)
        switch unit.prefix(3) {
        case "wee": return Decimal((calendar.dateComponents([.day], from: a, to: b).day ?? 0) / 7)
        case "mon": return Decimal(calendar.dateComponents([.month], from: a, to: b).month ?? 0)
        case "yea": return Decimal(calendar.dateComponents([.year], from: a, to: b).year ?? 0)
        default: return Decimal(calendar.dateComponents([.day], from: a, to: b).day ?? 0)
        }
    }

    private static func unitSuffix(_ unit: String) -> String {
        unit == "time" ? " days" : " \(unit)"
    }

    private static func isBusinessDay(_ date: Date, calendar: Calendar, context: CalculatorEvaluationContext) -> Bool {
        if context.weekendWeekdays.contains(calendar.component(.weekday, from: date)) { return false }
        let day = calendar.startOfDay(for: date)
        return !context.businessDayHolidays.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    private static func addBusinessDays(_ count: Int, to date: Date, calendar: Calendar, context: CalculatorEvaluationContext) -> Date? {
        var result = calendar.startOfDay(for: date)
        var remaining = abs(count)
        let step = count < 0 ? -1 : 1
        while remaining > 0 {
            guard let next = calendar.date(byAdding: .day, value: step, to: result) else { return nil }
            result = next
            if isBusinessDay(result, calendar: calendar, context: context) { remaining -= 1 }
        }
        return result
    }

    private static func countBusinessDays(from: Date, to: Date, calendar: Calendar, context: CalculatorEvaluationContext) -> Int {
        let start = min(from, to), end = max(from, to)
        var cursor = calendar.startOfDay(for: start)
        var count = 0
        while cursor < calendar.startOfDay(for: end) {
            if isBusinessDay(cursor, calendar: calendar, context: context) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return count
    }

    private static func businessNotes(_ context: CalculatorEvaluationContext) -> [String] {
        ["Uses configured weekend weekdays: \(context.weekendWeekdays.sorted()).",
         context.businessDayHolidays.isEmpty ? "No holiday calendar was supplied." : "Uses \(context.businessDayHolidays.count) explicitly supplied holiday date(s)."]
    }

    private static func nextBirthday(_ components: DateComponents, from date: Date, calendar: Calendar) -> Date? {
        guard let month = components.month, let day = components.day else { return nil }
        let year = calendar.component(.year, from: date)
        if let current = validMonthDay(month: month, day: day, year: year, calendar: calendar), current > date { return current }
        return validMonthDay(month: month, day: day, year: year + 1, calendar: calendar)
    }

    private static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    private static func dateResult(_ date: Date, _ expression: String, notes: [String] = []) -> Result {
        Result(primaryValue: .date(date), formattedPrimaryValue: nil, metadata: .init(notes: notes), displayExpression: expression)
    }

    private static func decimalResult(_ value: Decimal, _ expression: String, suffix: String, notes: [String] = []) -> Result {
        let formatted = NSDecimalNumber(decimal: value).stringValue + suffix
        return Result(primaryValue: .decimal(value), formattedPrimaryValue: formatted, metadata: .init(notes: notes), displayExpression: expression)
    }

    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
