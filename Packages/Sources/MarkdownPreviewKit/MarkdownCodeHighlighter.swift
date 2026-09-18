import Foundation

enum MarkdownCodeHighlighter {
    private struct Profile {
        let keywords: Set<String>
        let lineComments: [String]
        let isCaseSensitive: Bool
    }

    static func highlight(_ source: String, language: String) -> String {
        guard let profile = profile(for: language) else {
            return MarkdownHTML.escapeText(source)
        }

        var result = ""
        var index = source.startIndex
        while index < source.endIndex {
            if let comment = profile.lineComments.first(where: {
                source[index...].hasPrefix($0)
            }) {
                let end = source[index...].firstIndex(of: "\n") ?? source.endIndex
                result += token("comment", String(source[index..<end]))
                index = end
                _ = comment
                continue
            }

            let character = source[index]
            if character == "\"" || character == "'" || character == "`" {
                let end = endOfString(in: source, from: index, quote: character)
                result += token("string", String(source[index..<end]))
                index = end
                continue
            }

            if character.isNumber {
                let end = source[index...].firstIndex(where: {
                    !$0.isNumber && !$0.isLetter && !"._".contains($0)
                }) ?? source.endIndex
                result += token("number", String(source[index..<end]))
                index = end
                continue
            }

            if isIdentifierStart(character) {
                let end = source[index...].dropFirst().firstIndex(where: {
                    !isIdentifierContinuation($0)
                }) ?? source.endIndex
                let word = String(source[index..<end])
                let lookup = profile.isCaseSensitive ? word : word.lowercased()
                result += profile.keywords.contains(lookup)
                    ? token("keyword", word)
                    : MarkdownHTML.escapeText(word)
                index = end
                continue
            }

            result += MarkdownHTML.escapeText(String(character))
            index = source.index(after: index)
        }
        return result
    }

    private static func endOfString(
        in source: String,
        from start: String.Index,
        quote: Character
    ) -> String.Index {
        var index = source.index(after: start)
        var isEscaped = false
        while index < source.endIndex {
            let character = source[index]
            index = source.index(after: index)
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == quote {
                break
            }
        }
        return index
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$"
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private static func token(_ kind: String, _ value: String) -> String {
        "<span class=\"syntax-\(kind)\">\(MarkdownHTML.escapeText(value))</span>"
    }

    private static func profile(for rawLanguage: String) -> Profile? {
        let language = rawLanguage.lowercased()
        switch language {
        case "swift":
            return cStyle([
                "actor", "any", "as", "associatedtype", "async", "await", "break", "case",
                "catch", "class", "continue", "default", "defer", "deinit", "do", "else",
                "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func",
                "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
                "nil", "nonisolated", "open", "operator", "private", "protocol", "public",
                "repeat", "rethrows", "return", "self", "some", "static", "struct", "subscript",
                "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where",
                "while",
            ])
        case "c", "h", "cpp", "c++", "cc", "cxx", "objective-c", "objc", "java", "kotlin", "kt":
            return cStyle([
                "abstract", "auto", "boolean", "break", "byte", "case", "catch", "char", "class",
                "const", "continue", "default", "do", "double", "else", "enum", "extends", "false",
                "final", "finally", "float", "for", "fun", "goto", "if", "implements", "import",
                "inline", "instanceof", "int", "interface", "long", "namespace", "native", "new",
                "null", "override", "package", "private", "protected", "public", "return", "short",
                "signed", "sizeof", "static", "struct", "super", "switch", "synchronized", "template",
                "this", "throw", "throws", "transient", "true", "try", "typedef", "typename", "union",
                "unsigned", "using", "virtual", "void", "volatile", "when", "while",
            ])
        case "javascript", "js", "jsx", "typescript", "ts", "tsx":
            return cStyle([
                "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
                "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally",
                "for", "from", "function", "get", "if", "implements", "import", "in", "instanceof",
                "interface", "let", "new", "null", "of", "private", "protected", "public", "return",
                "set", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof",
                "undefined", "var", "void", "while", "with", "yield",
            ])
        case "csharp", "c#", "cs":
            return cStyle([
                "abstract", "as", "async", "await", "base", "bool", "break", "byte", "case", "catch",
                "char", "checked", "class", "const", "continue", "decimal", "default", "delegate", "do",
                "double", "else", "enum", "event", "explicit", "extern", "false", "finally", "fixed",
                "float", "for", "foreach", "get", "if", "implicit", "in", "int", "interface", "internal",
                "is", "lock", "long", "namespace", "new", "null", "object", "operator", "out", "override",
                "params", "private", "protected", "public", "readonly", "record", "ref", "return", "sbyte",
                "sealed", "set", "short", "sizeof", "stackalloc", "static", "string", "struct", "switch",
                "this", "throw", "true", "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort",
                "using", "virtual", "void", "volatile", "while",
            ])
        case "go", "golang":
            return cStyle([
                "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
                "false", "for", "func", "go", "goto", "if", "import", "interface", "map", "nil", "package",
                "range", "return", "select", "struct", "switch", "true", "type", "var",
            ])
        case "rust", "rs":
            return cStyle([
                "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
                "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move",
                "mut", "pub", "ref", "return", "self", "static", "struct", "super", "trait", "true", "type",
                "unsafe", "use", "where", "while",
            ])
        case "dart", "scala":
            return cStyle([
                "abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const",
                "continue", "def", "default", "do", "dynamic", "else", "enum", "extends", "extension", "false",
                "final", "finally", "for", "given", "if", "implements", "import", "in", "interface", "lazy",
                "match", "mixin", "new", "null", "object", "override", "package", "private", "protected",
                "public", "return", "sealed", "static", "super", "switch", "this", "throw", "trait", "true",
                "try", "type", "val", "var", "void", "while", "with", "yield",
            ])
        case "python", "py":
            return profile([
                "and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del",
                "elif", "else", "except", "false", "finally", "for", "from", "global", "if", "import", "in",
                "is", "lambda", "match", "none", "nonlocal", "not", "or", "pass", "raise", "return", "true",
                "try", "while", "with", "yield",
            ], comments: ["#"], caseSensitive: true)
        case "ruby", "rb", "perl", "lua", "elixir", "haskell":
            return profile([
                "alias", "and", "begin", "case", "class", "def", "do", "else", "elsif", "end", "false", "for",
                "fun", "function", "if", "import", "in", "let", "module", "nil", "not", "of", "or", "private",
                "raise", "require", "rescue", "return", "then", "true", "unless", "until", "use", "when",
                "where", "while", "yield",
            ], comments: language == "haskell" ? ["--"] : ["#", "--"], caseSensitive: true)
        case "bash", "sh", "shell", "zsh", "fish", "powershell", "ps1":
            return profile([
                "break", "case", "continue", "do", "done", "elif", "else", "end", "esac", "fi", "for",
                "foreach", "function", "if", "in", "select", "then", "until", "while",
            ], comments: ["#"], caseSensitive: true)
        case "sql", "mysql", "postgres", "postgresql":
            return profile([
                "all", "alter", "and", "as", "asc", "begin", "between", "by", "case", "check", "column",
                "commit", "constraint", "create", "database", "default", "delete", "desc", "distinct", "drop",
                "else", "end", "exists", "false", "foreign", "from", "full", "group", "having", "in", "index",
                "inner", "insert", "into", "is", "join", "key", "left", "like", "limit", "not", "null", "on",
                "or", "order", "outer", "primary", "references", "right", "rollback", "select", "set", "table",
                "then", "true", "union", "unique", "update", "values", "view", "when", "where", "with",
            ], comments: ["--"], caseSensitive: false)
        case "json", "jsonc":
            return profile(["false", "null", "true"], comments: language == "jsonc" ? ["//"] : [], caseSensitive: true)
        case "yaml", "yml", "toml", "ini", "r", "rscript":
            return profile([
                "false", "inf", "na", "nan", "null", "true",
            ], comments: ["#"], caseSensitive: false)
        case "php":
            return cStyle([
                "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone",
                "const", "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "endfor",
                "endforeach", "endif", "endswitch", "endwhile", "extends", "false", "final", "finally", "for",
                "foreach", "function", "global", "if", "implements", "include", "instanceof", "interface", "isset",
                "namespace", "new", "null", "or", "private", "protected", "public", "require", "return", "static",
                "switch", "throw", "trait", "true", "try", "unset", "use", "var", "while", "xor", "yield",
            ])
        case "html", "xml", "css", "scss", "less", "markdown", "md":
            return profile([
                "color", "display", "false", "flex", "grid", "important", "none", "null", "position", "true",
                "var",
            ], comments: [], caseSensitive: false)
        default:
            return nil
        }
    }

    private static func cStyle(_ keywords: Set<String>) -> Profile {
        profile(keywords, comments: ["//"], caseSensitive: true)
    }

    private static func profile(
        _ keywords: Set<String>,
        comments: [String],
        caseSensitive: Bool
    ) -> Profile {
        Profile(keywords: keywords, lineComments: comments, isCaseSensitive: caseSensitive)
    }
}
