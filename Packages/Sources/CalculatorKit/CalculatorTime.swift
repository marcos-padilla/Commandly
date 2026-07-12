import Foundation

/// Clock, time-zone, timestamp, recurrence, and scheduling calculations.
enum CalculatorTime {
    struct Result: Sendable, Equatable {
        let kind: CalculatorResultKind
        let primaryValue: CalculatorValue
        let formattedPrimaryValue: String?
        let metadata: CalculatorResultMetadata
        let displayExpression: String
    }

    static func evaluate(_ input: String, context: CalculatorEvaluationContext) throws -> Result? {
        var text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("show ") { text.removeFirst("show ".count) }
        if text != "what time is it", text.hasPrefix("what time is ") { text.removeFirst("what time is ".count) }
        if ["sunrise", "sunset", "daylight duration", "golden hour"].contains(where: text.contains) {
            throw CalculatorError.unsupportedOperation
        }
        if let result = timestampOrISO(text, context: context) { return result }
        if let result = try currentTime(text, context: context) { return result }
        if let result = try timeZoneConversion(text, context: context) { return result }
        if let result = try timeZoneDifference(text, context: context) { return result }
        if let result = clockArithmetic(text, context: context) { return result }
        if let result = durationFormatting(text, context: context) { return result }
        if let result = clockFormatConversion(text, context: context) { return result }
        if let result = scheduling(text, context: context) { return result }
        if let result = recurrence(text, context: context) { return result }
        if let result = try cron(text, context: context) { return result }
        return nil
    }

    private static func currentTime(_ text: String, context: CalculatorEvaluationContext) throws -> Result? {
        if ["current time", "time now", "what time is it"].contains(text) {
            return instantResult(context.now, zone: context.timeZone, source: nil, expression: text, kind: .timeCalculation, locale: context.locale, calendar: context.calendar)
        }
        if text.range(of: #"^utc[+-]\d{1,2}(?::\d{2})?$"#, options: .regularExpression) != nil {
            let zone = try zone(text)
            return instantResult(context.now, zone: zone, source: context.timeZone, expression: text, kind: .timeZoneConversion, locale: context.locale, calendar: context.calendar)
        }
        if let groups = captures(#"^(?:current time in|time in|local time in)\s+(.+)$"#, text) {
            let zone = try zone(groups[0])
            return instantResult(context.now, zone: zone, source: context.timeZone, expression: text, kind: .timeZoneConversion, locale: context.locale, calendar: context.calendar)
        }
        if let groups = captures(#"^time in\s+(utc[+-]\d{1,2}(?::\d{2})?)$"#, text) {
            let zone = try zone(groups[0])
            return instantResult(context.now, zone: zone, source: context.timeZone, expression: text, kind: .timeZoneConversion, locale: context.locale, calendar: context.calendar)
        }
        return nil
    }

    private static func timestampOrISO(_ text: String, context: CalculatorEvaluationContext) -> Result? {
        if text == "unix time now" {
            return decimalResult(Decimal(Int(context.now.timeIntervalSince1970)), text, suffix: "", notes: ["Unix timestamp in seconds."])
        }
        if let groups = captures(#"^timestamp for\s+(.+?)(?:\s+at\s+(.+))?$"#, text),
           let date = parseDate(groups[0], context: context),
           let instant = combine(date: date, time: groups[1].isEmpty ? "midnight" : groups[1], zone: context.timeZone, calendar: context.calendar) {
            return decimalResult(Decimal(Int(instant.timeIntervalSince1970)), text, suffix: "", notes: ["Unix timestamp in seconds."])
        }
        if let groups = captures(#"^(\d{10,13})(?:\s+milliseconds)?\s+as (?:local time|date)$"#, text), let raw = Double(groups[0]) {
            let instant = Date(timeIntervalSince1970: groups[0].count >= 13 || text.contains("milliseconds") ? raw / 1_000 : raw)
            return instantResult(instant, zone: context.timeZone, source: nil, expression: text, kind: .timeCalculation, locale: context.locale, calendar: context.calendar)
        }
        if let groups = captures(#"^(.+?)\s+as epoch$"#, text), let date = parseDate(groups[0], context: context) {
            return decimalResult(Decimal(Int(date.timeIntervalSince1970)), text, suffix: "", notes: ["Unix timestamp in seconds."])
        }
        if let groups = captures(#"^(\d{4}-\d{2}-\d{2}t\d{2}:\d{2}:\d{2}(?:z|[+-]\d{2}:\d{2}))\s+in\s+(local time|utc)$"#, text) {
            let formatter = ISO8601DateFormatter()
            guard let instant = formatter.date(from: groups[0].uppercased()) else { return nil }
            let target = groups[1] == "utc" ? TimeZone.gmt : context.timeZone
            return instantResult(instant, zone: target, source: nil, expression: text, kind: .timeZoneConversion, locale: context.locale, calendar: context.calendar)
        }
        return nil
    }

    private static func timeZoneConversion(_ text: String, context: CalculatorEvaluationContext) throws -> Result? {
        if let groups = captures(#"^(?:(.+?)\s+at\s+)?(noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s+(.+?)(?:\s+time)?\s+(?:in|to)\s+(.+?)(?:\s+on\s+(.+))?$"#, text) {
            let fromZone = try zone(groups[2])
            let toZone = try zone(groups[3])
            var day = context.now
            if !groups[0].isEmpty { day = parseDayReference(groups[0], context: context, zone: fromZone) ?? day }
            if !groups[4].isEmpty { day = parseDayReference(groups[4], context: context, zone: fromZone) ?? day }
            guard let instant = combine(date: day, time: groups[1], zone: fromZone, calendar: context.calendar) else {
                throw CalculatorError.invalidDateExpression
            }
            return instantResult(instant, zone: toZone, source: fromZone, expression: text, kind: .timeZoneConversion, locale: context.locale, calendar: context.calendar)
        }
        if let groups = captures(#"^(noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s+(utc[+-]\d{1,2}(?::\d{2})?|gmt[+-]\d{1,2}(?::\d{2})?)\s+(?:in|to)\s+(utc(?:[+-]\d{1,2}(?::\d{2})?)?|gmt(?:[+-]\d{1,2}(?::\d{2})?)?)$"#, text) {
            let fromZone = try zone(groups[1]), toZone = try zone(groups[2])
            guard let instant = combine(date: context.now, time: groups[0], zone: fromZone, calendar: context.calendar) else { return nil }
            return instantResult(instant, zone: toZone, source: fromZone, expression: text, kind: .timeZoneConversion, locale: context.locale, calendar: context.calendar)
        }
        return nil
    }

    private static func timeZoneDifference(_ text: String, context: CalculatorEvaluationContext) throws -> Result? {
        if let groups = captures(#"^(?:time difference between|difference between)\s+(.+?)\s+and\s+(.+?)(?:\s+on\s+(.+))?$"#, text) {
            if clock(groups[0]) != nil, clock(groups[1]) != nil { return nil }
            let first = try zone(groups[0]), second = try zone(groups[1])
            let date: Date
            if groups[2].isEmpty {
                date = context.now
            } else if let day = parseDayReference(groups[2], context: context, zone: first),
                      let noon = combine(date: day, time: "noon", zone: first, calendar: context.calendar) {
                date = noon
            } else {
                date = context.now
            }
            let hours = Decimal(second.secondsFromGMT(for: date) - first.secondsFromGMT(for: date)) / 3_600
            return decimalResult(hours, text, suffix: " h", notes: ["Signed destination offset minus source offset on the requested date."])
        }
        if let groups = captures(#"^how many hours ahead is\s+(.+?)\s+from\s+(.+)$"#, text) {
            let destination = try zone(groups[0]), source = try zone(groups[1])
            let hours = Decimal(destination.secondsFromGMT(for: context.now) - source.secondsFromGMT(for: context.now)) / 3_600
            return decimalResult(hours, text, suffix: " h")
        }
        if let groups = captures(#"^utc offset for\s+(.+)$"#, text) {
            let target = try zone(groups[0])
            let seconds = target.secondsFromGMT(for: context.now)
            let hours = Decimal(seconds) / 3_600
            return decimalResult(hours, text, suffix: " h", notes: [formatOffset(seconds)])
        }
        return nil
    }

    private static func clockArithmetic(_ text: String, context: CalculatorEvaluationContext) -> Result? {
        if let groups = captures(#"^(\d+)\s+(hours?|minutes?)\s+(after|before)\s+(.+)$"#, text),
           let amount = Int(groups[0]), let base = clock(groups[3]) {
            let seconds = amount * (groups[1].hasPrefix("hour") ? 3_600 : 60) * (groups[2] == "before" ? -1 : 1)
            return clockResult(base + seconds, text, context: context)
        }
        if let groups = captures(#"^(.+?)\s+(?:\+|plus|minus|-)\s+(\d+)\s+(hours?|minutes?)$"#, text),
           let base = clock(groups[0]), let amount = Int(groups[1]) {
            let sign = text.contains(" minus ") || text.contains(" - ") ? -1 : 1
            let seconds = amount * (groups[2].hasPrefix("hour") ? 3_600 : 60) * sign
            return clockResult(base + seconds, text, context: context)
        }
        if let groups = captures(#"^(\d+)\s+hours?\s+(\d+)\s+minutes?\s+after\s+(.+)$"#, text),
           let hours = Int(groups[0]), let minutes = Int(groups[1]), let base = clock(groups[2]) {
            return clockResult(base + hours * 3_600 + minutes * 60, text, context: context)
        }
        if let groups = captures(#"^(\d+)\s+day\s+(\d+)\s+hours?\s+from now$"#, text),
           let days = Int(groups[0]), let hours = Int(groups[1]) {
            let instant = context.now.addingTimeInterval(TimeInterval(days * 86_400 + hours * 3_600))
            return instantResult(instant, zone: context.timeZone, source: nil, expression: text, kind: .timeCalculation, locale: context.locale, calendar: context.calendar)
        }
        if let groups = captures(#"^(\d+)\s+minutes?\s+before tomorrow at\s+(.+)$"#, text),
           let minutes = Int(groups[0]), let tomorrow = CalendarDate.tomorrow(context),
           let instant = combine(date: tomorrow, time: groups[1], zone: context.timeZone, calendar: context.calendar) {
            return instantResult(instant.addingTimeInterval(TimeInterval(-minutes * 60)), zone: context.timeZone, source: nil, expression: text, kind: .timeCalculation, locale: context.locale, calendar: context.calendar)
        }
        if let groups = captures(#"^(\d{1,2}:\d{2})\s*\+\s*(\d{1,2}):(\d{2})$"#, text),
           let base = clock(groups[0]), let hours = Int(groups[1]), let minutes = Int(groups[2]) {
            return clockResult(base + hours * 3_600 + minutes * 60, text, context: context)
        }
        if let groups = captures(#"^(?:time|hours|difference) between\s+(.+?)\s+and\s+(.+)$"#, text), let first = clock(groups[0]), let second = clock(groups[1]) {
            return durationBetween(first, second, text: text)
        }
        if let groups = captures(#"^how long from\s+(.+?)\s+to\s+(.+)$"#, text), let first = clock(groups[0]), let second = clock(groups[1]) {
            return durationBetween(first, second, text: text)
        }
        return nil
    }

    private static func durationFormatting(_ text: String, context: CalculatorEvaluationContext) -> Result? {
        if let groups = captures(#"^(\d+(?:\.\d+)?)\s+(minutes?|seconds?|hours?)\s+(?:as|in)\s+(hours|hours and minutes)$"#, text), let amount = Double(groups[0]) {
            let seconds = amount * (groups[1].hasPrefix("hour") ? 3_600 : groups[1].hasPrefix("minute") ? 60 : 1)
            if groups[2] == "hours" { return decimalResult(Decimal(seconds / 3_600), text, suffix: " h") }
            return durationResult(Int(seconds), text)
        }
        if let groups = captures(#"^(\d{1,2}):(\d{2}):(\d{2})\s+in seconds$"#, text),
           let h = Int(groups[0]), let m = Int(groups[1]), let s = Int(groups[2]) {
            return decimalResult(Decimal(h * 3_600 + m * 60 + s), text, suffix: " s")
        }
        _ = context
        return nil
    }

    private static func clockFormatConversion(_ text: String, context: CalculatorEvaluationContext) -> Result? {
        if let groups = captures(#"^(.+?)\s+in (24-hour time|24-hour format|military time)$"#, text), let seconds = clock(groups[0]) {
            return clockResult(seconds, text, context: context, twentyFourHour: true)
        }
        if let groups = captures(#"^(.+?)\s+in 12-hour time$"#, text), let seconds = clock(groups[0]) {
            return clockResult(seconds, text, context: context, twentyFourHour: false)
        }
        return nil
    }

    private static func scheduling(_ text: String, context: CalculatorEvaluationContext) -> Result? {
        if let groups = captures(#"^(?:meeting|duration) from\s+(.+?)\s+to\s+(.+)$"#, text), let first = clock(groups[0]), let second = clock(groups[1]) {
            return durationBetween(first, second, text: text)
        }
        if let groups = captures(#"^split\s+(\d+(?:\.\d+)?)\s+hours?\s+into\s+(\d+)-minute blocks$"#, text), let hours = Double(groups[0]), let block = Double(groups[1]), block > 0 {
            return decimalResult(Decimal(Int((hours * 60 / block).rounded(.down))), text, suffix: " blocks")
        }
        if let groups = captures(#"^how many\s+(\d+)-minute meetings fit between\s+(.+?)\s+and\s+(.+)$"#, text), let block = Int(groups[0]), let first = clock(groups[1]), let second = clock(groups[2]), block > 0 {
            let elapsed = scheduleDifference(first, second, startText: groups[1], endText: groups[2])
            return decimalResult(Decimal(elapsed / (block * 60)), text, suffix: " meetings")
        }
        if let groups = captures(#"^(\d+(?:\.\d+)?)-hour shift starting at\s+(.+?)\s+with a\s+(\d+)-minute break$"#, text), let hours = Double(groups[0]), let start = clock(groups[1]), let breakMinutes = Int(groups[2]) {
            return clockResult(start + Int(hours * 3_600) + breakMinutes * 60, text, context: context)
        }
        if let groups = captures(#"^end time for a\s+(\d+(?:\.\d+)?)-hour workday starting at\s+(.+)$"#, text), let hours = Double(groups[0]), let start = clock(groups[1]) {
            return clockResult(start + Int(hours * 3_600), text, context: context)
        }
        return nil
    }

    private static func recurrence(_ text: String, context: CalculatorEvaluationContext) -> Result? {
        if let groups = captures(#"^every\s+(\d+)\s+days? starting\s+(.+)$"#, text), let interval = Int(groups[0]), interval > 0, let start = parseDate(groups[1], context: context) {
            guard let next = nextOccurrence(start: start, intervalDays: interval, now: context.now, calendar: context.calendar) else { return nil }
            return dateResult(next, text, notes: ["Next occurrence in the requested interval."])
        }
        if let groups = captures(#"^next date in a biweekly schedule starting\s+(.+)$"#, text), let start = parseDate(groups[0], context: context),
           let next = nextOccurrence(start: start, intervalDays: 14, now: context.now, calendar: context.calendar) {
            return dateResult(next, text, notes: ["Biweekly means every 14 days."])
        }
        if let groups = captures(#"^(\d+) occurrences every\s+(\d+)\s+weeks? from\s+(.+)$"#, text), let count = Int(groups[0]), let weeks = Int(groups[1]), count > 0, let start = parseDate(groups[2], context: context),
           let final = context.calendar.date(byAdding: .day, value: (count - 1) * weeks * 7, to: start) {
            return dateResult(final, text, notes: ["Date of occurrence \(count); the start is occurrence 1."])
        }
        return nil
    }

    private static func cron(_ text: String, context: CalculatorEvaluationContext) throws -> Result? {
        var expression = text
        var wantsNext = false
        if expression.hasPrefix("what does ") { expression = String(expression.dropFirst("what does ".count)); if expression.hasSuffix(" mean") { expression = String(expression.dropLast(" mean".count)) } }
        if expression.hasPrefix("next run for ") { expression = String(expression.dropFirst("next run for ".count)); wantsNext = true }
        let fields = expression.split(separator: " ").map(String.init)
        guard fields.count == 5 else { return nil }
        guard let minute = Int(fields[0]), let hour = Int(fields[1]), (0...59).contains(minute), (0...23).contains(hour), fields[2] == "*", fields[3] == "*" else {
            throw CalculatorError.unsupportedOperation
        }
        let weekdays: Set<Int>
        switch fields[4].lowercased() {
        case "*": weekdays = Set(1...7)
        case "1-5": weekdays = [2, 3, 4, 5, 6]
        case "mon": weekdays = [2]
        default: throw CalculatorError.unsupportedOperation
        }
        let description: String
        switch fields[4].lowercased() {
        case "*": description = String(format: "At %02d:%02d every day", hour, minute)
        case "mon": description = String(format: "At %02d:%02d every Monday", hour, minute)
        default: description = String(format: "At %02d:%02d Monday through Friday", hour, minute)
        }
        if !wantsNext { return Result(kind: .timeCalculation, primaryValue: .decimal(0), formattedPrimaryValue: description, metadata: .init(notes: ["Five-field cron; interpreted in the configured time zone."]), displayExpression: text) }
        var calendar = context.calendar
        calendar.timeZone = context.timeZone
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: context.now) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour; components.minute = minute; components.second = 0
            guard let candidate = calendar.date(from: components), candidate > context.now, weekdays.contains(calendar.component(.weekday, from: candidate)) else { continue }
            return instantResult(candidate, zone: context.timeZone, source: nil, expression: text, kind: .timeCalculation, locale: context.locale, calendar: calendar, notes: [description])
        }
        throw CalculatorError.invalidDateExpression
    }

    // MARK: - Helpers

    private enum CalendarDate {
        static func tomorrow(_ context: CalculatorEvaluationContext) -> Date? {
            var calendar = context.calendar; calendar.timeZone = context.timeZone
            return calendar.date(byAdding: .day, value: 1, to: context.now)
        }
    }

    private static func zone(_ raw: String) throws -> TimeZone {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "utc" || value == "gmt" { return .gmt }
        if let groups = captures(#"^(?:utc|gmt)([+-])(\d{1,2})(?::(\d{2}))?$"#, value), let hours = Int(groups[1]), let minutes = Int(groups[2].isEmpty ? "0" : groups[2]), hours <= 14, minutes < 60 {
            let seconds = (hours * 3_600 + minutes * 60) * (groups[0] == "-" ? -1 : 1)
            guard let zone = TimeZone(secondsFromGMT: seconds) else { throw CalculatorError.ambiguousTimeZone(raw) }
            return zone
        }
        return try CalculatorDateTime.resolveTimeZone(raw)
    }

    private static func clock(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text == "noon" { return 12 * 3_600 }
        if text == "midnight" { return 0 }
        guard let groups = captures(#"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#, text), var hour = Int(groups[0]), let minute = Int(groups[1].isEmpty ? "0" : groups[1]), minute < 60 else { return nil }
        let meridiem = groups[2]
        if !meridiem.isEmpty {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm" && hour < 12 { hour += 12 }
            if meridiem == "am" && hour == 12 { hour = 0 }
        } else if hour > 23 { return nil }
        return hour * 3_600 + minute * 60
    }

    private static func combine(date: Date, time: String, zone: TimeZone, calendar: Calendar) -> Date? {
        guard let seconds = clock(time) else { return nil }
        var local = calendar; local.timeZone = zone
        var components = local.dateComponents([.year, .month, .day], from: date)
        components.hour = seconds / 3_600
        components.minute = (seconds % 3_600) / 60
        components.second = seconds % 60
        return local.date(from: components)
    }

    private static func parseDayReference(_ raw: String, context: CalculatorEvaluationContext, zone: TimeZone) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var calendar = context.calendar; calendar.timeZone = zone
        let base = calendar.startOfDay(for: context.now)
        if text == "today" { return base }
        if text == "tomorrow" { return calendar.date(byAdding: .day, value: 1, to: base) }
        let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
        if let target = weekdays[text] {
            var delta = target - calendar.component(.weekday, from: base); if delta < 0 { delta += 7 }
            return calendar.date(byAdding: .day, value: delta, to: base)
        }
        return parseDate(text, context: context, zone: zone)
    }

    private static func parseDate(_ raw: String, context: CalculatorEvaluationContext, zone: TimeZone? = nil) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var calendar = context.calendar; calendar.timeZone = zone ?? context.timeZone
        let explicitYear = text.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil
        let format: String
        if text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { format = "yyyy-MM-dd" }
        else if explicitYear { format = text.contains(",") ? "MMMM d, yyyy" : "MMMM d yyyy" }
        else { format = "MMMM d" }
        let formatter = DateFormatter(); formatter.locale = context.locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = format; formatter.isLenient = false
        guard let parsed = formatter.date(from: text) else { return nil }
        if explicitYear { return parsed }
        let month = calendar.component(.month, from: parsed), day = calendar.component(.day, from: parsed), year = calendar.component(.year, from: context.now)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func nextOccurrence(start: Date, intervalDays: Int, now: Date, calendar: Calendar) -> Date? {
        if start > now { return start }
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
        let steps = elapsed / intervalDays + 1
        return calendar.date(byAdding: .day, value: steps * intervalDays, to: start)
    }

    private static func forwardDifference(_ first: Int, _ second: Int) -> Int { second > first ? second - first : second + 86_400 - first }

    private static func scheduleDifference(_ first: Int, _ second: Int, startText: String, endText: String) -> Int {
        let hasMeridiem = startText.contains("am") || startText.contains("pm") || endText.contains("am") || endText.contains("pm")
        if !hasMeridiem, first >= 6 * 3_600, first < 12 * 3_600, second < first {
            return second + 12 * 3_600 - first
        }
        return forwardDifference(first, second)
    }

    private static func durationBetween(_ first: Int, _ second: Int, text: String) -> Result {
        durationResult(forwardDifference(first, second), text, notes: ["If the end is not later than the start, it is treated as the next day."])
    }

    private static func durationResult(_ seconds: Int, _ expression: String, notes: [String] = []) -> Result {
        let hours = seconds / 3_600, minutes = (seconds % 3_600) / 60, remaining = seconds % 60
        let formatted = remaining == 0 ? "\(hours) h \(minutes) min" : "\(hours) h \(minutes) min \(remaining) s"
        return Result(kind: .timeCalculation, primaryValue: .decimal(Decimal(seconds)), formattedPrimaryValue: formatted, metadata: .init(notes: notes + ["Primary value is total seconds."]), displayExpression: expression)
    }

    private static func clockResult(_ rawSeconds: Int, _ expression: String, context: CalculatorEvaluationContext, twentyFourHour: Bool? = nil) -> Result {
        let seconds = ((rawSeconds % 86_400) + 86_400) % 86_400
        let instant = combine(date: context.now, time: String(format: "%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60), zone: context.timeZone, calendar: context.calendar) ?? context.now
        let formatted = formatTime(instant, zone: context.timeZone, locale: context.locale, calendar: context.calendar, twentyFourHour: twentyFourHour)
        return Result(kind: .timeCalculation, primaryValue: .timeZoneInstant(.init(instant: instant, timeZoneIdentifier: context.timeZone.identifier)), formattedPrimaryValue: formatted, metadata: .init(), displayExpression: expression)
    }

    private static func instantResult(_ instant: Date, zone: TimeZone, source: TimeZone?, expression: String, kind: CalculatorResultKind, locale: Locale, calendar: Calendar, notes: [String] = []) -> Result {
        let value = CalculatorTimeZoneValue(instant: instant, timeZoneIdentifier: zone.identifier, sourceTimeZoneIdentifier: source?.identifier)
        let metadata = CalculatorResultMetadata(fromTimeZone: source?.identifier, toTimeZone: zone.identifier, notes: notes)
        return Result(kind: kind, primaryValue: .timeZoneInstant(value), formattedPrimaryValue: CalculatorFormatter.formatTimeZoneInstant(value, locale: locale, calendar: calendar), metadata: metadata, displayExpression: expression)
    }

    private static func dateResult(_ date: Date, _ expression: String, notes: [String]) -> Result {
        Result(kind: .dateCalculation, primaryValue: .date(date), formattedPrimaryValue: nil, metadata: .init(notes: notes), displayExpression: expression)
    }

    private static func decimalResult(_ value: Decimal, _ expression: String, suffix: String, notes: [String] = []) -> Result {
        Result(kind: .timeCalculation, primaryValue: .decimal(value), formattedPrimaryValue: NSDecimalNumber(decimal: value).stringValue + suffix, metadata: .init(notes: notes), displayExpression: expression)
    }

    private static func formatTime(_ date: Date, zone: TimeZone, locale: Locale, calendar: Calendar, twentyFourHour: Bool?) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = zone
        if let twentyFourHour { formatter.dateFormat = twentyFourHour ? "HH:mm" : "h:mm a" } else { formatter.timeStyle = .short; formatter.dateStyle = .none }
        return formatter.string(from: date)
    }

    private static func formatOffset(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+", absolute = abs(seconds), hours = absolute / 3_600, minutes = (absolute % 3_600) / 60
        return minutes == 0 ? "UTC\(sign)\(hours)" : String(format: "UTC%@%d:%02d", sign, hours, minutes)
    }

    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
