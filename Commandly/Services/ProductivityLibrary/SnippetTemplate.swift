import Foundation

/// A literal template parser. Substituted text is never parsed again or executed.
nonisolated struct SnippetTemplate: Equatable, Sendable {
    enum Failure: Error, Equatable {
        case tooLarge
        case tooManyFields
        case missingInput

        var message: String {
            switch self {
            case .tooLarge: return "This snippet is too large to expand. Use less than 1 MB of text."
            case .tooManyFields: return "Use at most 16 named input fields in a snippet."
            case .missingInput: return "Fill in each snippet field before copying."
            }
        }
    }

    private enum Part: Equatable, Sendable {
        case literal(String)
        case value(String)
        case input(String)
    }

    static let maximumBytes = 1_000_000
    private let parts: [Part]
    let fields: [String]
    let needsClipboard: Bool

    init(_ source: String) throws {
        guard source.utf8.count <= Self.maximumBytes else { throw Failure.tooLarge }
        var parts: [Part] = []
        var fields: [String] = []
        var remaining = source[...]
        var needsClipboard = false
        while let start = remaining.range(of: "{{"),
              let end = remaining[start.upperBound...].range(of: "}}") {
            if start.lowerBound > remaining.startIndex {
                parts.append(.literal(String(remaining[..<start.lowerBound])))
            }
            let token = String(remaining[start.upperBound..<end.lowerBound])
            if ["clipboard", "date", "time", "datetime", "uuid"].contains(token) {
                parts.append(.value(token))
                needsClipboard = needsClipboard || token == "clipboard"
            } else if token.hasPrefix("input:") {
                let name = String(token.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name.count <= 64, !name.contains("{"), !name.contains("\n") {
                    parts.append(.input(name))
                    if !fields.contains(name) { fields.append(name) }
                    guard fields.count <= 16 else { throw Failure.tooManyFields }
                } else {
                    parts.append(.literal(String(remaining[start.lowerBound..<end.upperBound])))
                }
            } else {
                parts.append(.literal(String(remaining[start.lowerBound..<end.upperBound])))
            }
            remaining = remaining[end.upperBound...]
        }
        if !remaining.isEmpty { parts.append(.literal(String(remaining))) }
        self.parts = parts
        self.fields = fields
        self.needsClipboard = needsClipboard
    }

    func expanded(
        clipboard: String, date: Date, uuid: UUID, inputs: [String: String] = [:],
        timeZone: TimeZone = .current
    ) throws -> String {
        guard fields.allSatisfy({ inputs[$0]?.isEmpty == false }) else { throw Failure.missingInput }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        var output = ""
        var bytes = 0
        var cached: [String: String] = ["clipboard": clipboard, "uuid": uuid.uuidString.lowercased()]
        for part in parts {
            let value: String
            switch part {
            case .literal(let text): value = text
            case .input(let name): value = inputs[name] ?? ""
            case .value(let token):
                if let existing = cached[token] {
                    value = existing
                } else {
                    switch token {
                    case "date": formatter.dateFormat = "yyyy-MM-dd"
                    case "time": formatter.dateFormat = "HH:mm"
                    default: formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    }
                    value = formatter.string(from: date)
                    cached[token] = value
                }
            }
            bytes += value.utf8.count
            guard bytes <= Self.maximumBytes else { throw Failure.tooLarge }
            output += value
        }
        return output
    }
}
