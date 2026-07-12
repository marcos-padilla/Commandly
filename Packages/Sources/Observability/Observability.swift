import OSLog

/// Logging categories for Commandly.
public enum LogCategory: String, Sendable, CaseIterable {
    case application
    case lifecycle
    case commands
    case search
    case persistence
    case security
    case extensions
    case performance
    case userInterface = "ui"
}

/// Structured logger facade over `OSLog`.
///
/// Never pass clipboard contents, secrets, tokens, file contents,
/// private URLs, credentials, or complete search history to these APIs.
public struct AppLogger: Sendable {
    private let logger: os.Logger

    /// Creates a logger for the given category.
    public init(category: LogCategory, subsystem: String = "com.businessmate360.Commandly") {
        self.logger = os.Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// Logs a debug message.
    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    /// Logs an informational message.
    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// Logs a warning.
    public func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    /// Logs an error message without sensitive payloads.
    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

/// Factory for category loggers.
public enum Loggers {
    public static let application = AppLogger(category: .application)
    public static let lifecycle = AppLogger(category: .lifecycle)
    public static let commands = AppLogger(category: .commands)
    public static let search = AppLogger(category: .search)
    public static let persistence = AppLogger(category: .persistence)
    public static let security = AppLogger(category: .security)
    public static let extensions = AppLogger(category: .extensions)
    public static let performance = AppLogger(category: .performance)
    public static let userInterface = AppLogger(category: .userInterface)
}
