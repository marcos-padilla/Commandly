import AppKit
import Foundation

enum OfflineToolKind: String, CaseIterable, Identifiable, Sendable {
    case emoji
    case textCase
    case color
    case dictionary
    case fonts
    case typing

    var id: String { rawValue }

    var commandID: String {
        switch self {
        case .emoji: return "tools.emoji-search"
        case .textCase: return "tools.text-case"
        case .color: return "tools.color"
        case .dictionary: return "tools.dictionary"
        case .fonts: return "tools.fonts"
        case .typing: return "tools.typing-practice"
        }
    }

    var title: String {
        switch self {
        case .emoji: return "Emoji Search"
        case .textCase: return "Convert Text Case"
        case .color: return "Color Tools"
        case .dictionary: return "Dictionary"
        case .fonts: return "Search Fonts"
        case .typing: return "Typing Practice"
        }
    }

    var subtitle: String {
        switch self {
        case .emoji: return "Find and copy common Unicode emoji"
        case .textCase: return "Transform text between common naming styles"
        case .color: return "Pick and convert colors locally"
        case .dictionary: return "Look up definitions in macOS dictionaries"
        case .fonts: return "Browse and preview installed font families"
        case .typing: return "Practice accuracy and speed without an account"
        }
    }

    var systemImage: String {
        switch self {
        case .emoji: return "face.smiling"
        case .textCase: return "textformat"
        case .color: return "eyedropper"
        case .dictionary: return "character.book.closed"
        case .fonts: return "textformat.size"
        case .typing: return "keyboard"
        }
    }

    var keywords: [String] {
        switch self {
        case .emoji: return ["symbol", "unicode", "smile", "reaction"]
        case .textCase: return ["uppercase", "lowercase", "camel", "snake", "kebab"]
        case .color: return ["picker", "hex", "rgb", "hsl", "eyedropper"]
        case .dictionary: return ["definition", "word", "meaning", "spell"]
        case .fonts: return ["typeface", "typography", "installed"]
        case .typing: return ["wpm", "practice", "keyboard", "accuracy"]
        }
    }
}

struct EmojiCatalogEntry: Identifiable, Equatable, Sendable {
    let symbol: String
    let name: String
    var id: String { symbol }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return needle.isEmpty || symbol == needle || name.lowercased().contains(needle)
    }
}

enum EmojiCatalog {
    // A deliberately local, curated catalog. Names come from Unicode scalar metadata shipped by macOS.
    private static let symbols = """
    😀 😃 😄 😁 😆 😅 😂 🤣 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😋 😛 😜 🤪 🤨 🧐 🤓 😎 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 🤗 🤔 🫡 🤭 🫢 🤫 🤥 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🤑 🤠 😈 👿 👻 💀 ☠️ 👽 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾
    👋 🤚 🖐️ ✋ 🖖 🫱 🫲 🫳 🫴 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🧠 👀 👁️ 👄 🫦
    ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❤️‍🔥 ❤️‍🩹 💕 💞 💓 💗 💖 💘 💝 💟 ❣️ 💯 💢 💥 💫 💦 💨 🕳️ 💬 🗨️ 🗯️ 💭 💤
    🌱 🌿 ☘️ 🍀 🌵 🌴 🌳 🌲 🌸 🌼 🌻 🌞 🌙 ⭐ 🌟 ✨ ⚡ 🔥 🌈 ☀️ ☁️ ❄️ ☔ 🌊
    🍎 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍒 🍑 🥭 🍍 🥝 🍅 🥑 🍕 🍔 🍟 🌮 🍣 🍪 🎂 ☕ 🍵 🥤
    ⚽ 🏀 🏈 ⚾ 🎾 🏐 🎱 🏓 🥊 🏆 🥇 🎯 🎮 🎲 🎸 🎧 🎤 🎬 🎨 📚 ✏️ 💡 🔧 🔨 ⚙️ 🧰
    🚗 🚕 🚌 🚲 ✈️ 🚀 🚁 🚢 🚂 🗺️ 🏠 🏢 🏥 🏫 ⛺ 🏖️ 🏔️ 🌋 🗽
    ✅ ❌ ⚠️ ℹ️ ❓ ❗ ➕ ➖ ✖️ ➗ ♻️ 🔒 🔓 🔑 🔔 🔕 📌 📍 📎 🖇️ ✂️ 🗑️ 📦 🎁 📅 ⏰ ⏱️ ⌛ 🔍 💻 🖥️ ⌨️ 🖱️ 📱 📷 🎥 🔋 🔌
    """

    static let entries: [EmojiCatalogEntry] = symbols
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
        .map { symbol in
            let scalarNames = symbol.unicodeScalars.compactMap { scalar -> String? in
                guard let name = scalar.properties.name else { return nil }
                guard name.contains("VARIATION SELECTOR") == false,
                      name.contains("ZERO WIDTH JOINER") == false else {
                    return nil
                }
                return name
                    .replacingOccurrences(of: "FACE WITH ", with: "")
                    .replacingOccurrences(of: "SIGN", with: "")
                    .replacingOccurrences(of: "EMOJI MODIFIER FITZPATRICK TYPE-", with: "skin tone ")
            }
            let name = scalarNames.joined(separator: " · ").lowercased().capitalized
            return EmojiCatalogEntry(symbol: symbol, name: name.isEmpty ? "Emoji" : name)
        }
}

enum TextCaseStyle: String, CaseIterable, Identifiable, Sendable {
    case uppercase
    case lowercase
    case title
    case sentence
    case camel
    case pascal
    case snake
    case kebab
    case constant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .title: return "Title Case"
        case .sentence: return "Sentence case"
        case .camel: return "camelCase"
        case .pascal: return "PascalCase"
        case .snake: return "snake_case"
        case .kebab: return "kebab-case"
        case .constant: return "CONSTANT_CASE"
        }
    }
}

enum TextCaseConverter {
    static func convert(_ text: String, to style: TextCaseStyle) -> String {
        switch style {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .title:
            return text.capitalized
        case .sentence:
            let lowered = text.lowercased()
            guard let first = lowered.first else { return "" }
            return String(first).uppercased() + lowered.dropFirst()
        case .camel:
            let parts = words(in: text)
            guard let first = parts.first else { return "" }
            return first.lowercased() + parts.dropFirst().map(capitalizedWord).joined()
        case .pascal:
            return words(in: text).map(capitalizedWord).joined()
        case .snake:
            return words(in: text).map { $0.lowercased() }.joined(separator: "_")
        case .kebab:
            return words(in: text).map { $0.lowercased() }.joined(separator: "-")
        case .constant:
            return words(in: text).map { $0.uppercased() }.joined(separator: "_")
        }
    }

    private static func words(in text: String) -> [String] {
        let camelSeparated = text.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return camelSeparated
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
    }

    private static func capitalizedWord(_ value: String) -> String {
        guard let first = value.first else { return "" }
        return String(first).uppercased() + value.dropFirst().lowercased()
    }
}

struct TypingPracticeResult: Equatable, Sendable {
    let wordsPerMinute: Int
    let accuracyPercent: Int
}

enum TypingPracticeEngine {
    static let prompt = "Small, deliberate steps turn ambitious ideas into dependable tools."

    static func result(typed: String, elapsed: TimeInterval) -> TypingPracticeResult {
        let expected = Array(prompt)
        let actual = Array(typed)
        let matches = zip(expected, actual).filter(==).count
        let denominator = max(expected.count, actual.count, 1)
        let accuracy = Int((Double(matches) / Double(denominator) * 100).rounded())
        let minutes = max(elapsed / 60, 1.0 / 60.0)
        let wpm = Int((Double(actual.count) / 5 / minutes).rounded())
        return TypingPracticeResult(wordsPerMinute: wpm, accuracyPercent: accuracy)
    }
}
