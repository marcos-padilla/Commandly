import Foundation

// MARK: - Public evaluation API

/// Evaluates calculator-style queries into typed outcomes.
public protocol CalculatorEvaluating: Sendable {
    /// Evaluates `input` using the supplied evaluation `context`.
    ///
    /// Implementations must respect task cancellation and must never log
    /// expression contents or results.
    func evaluate(
        _ input: String,
        context: CalculatorEvaluationContext
    ) async -> CalculatorEvaluationOutcome
}

/// Contextual inputs that influence parsing, evaluation, and formatting.
public struct CalculatorEvaluationContext: Sendable {
    /// Locale used for number parsing and formatting.
    public var locale: Locale
    /// Calendar used for date arithmetic.
    public var calendar: Calendar
    /// Time zone used when resolving relative dates and default local times.
    public var timeZone: TimeZone
    /// Deterministic "now" for date/time calculations.
    public var now: Date
    /// Angle mode for trigonometric functions.
    public var angleMode: CalculatorAngleMode
    /// Previous answer referenced by `ans` / `answer` / `previous`.
    public var previousAnswer: Decimal?
    /// Optional exchange-rate provider for currency conversion.
    public var exchangeRateProvider: (any ExchangeRateProviding)?

    /// Creates an evaluation context.
    public init(
        locale: Locale = .current,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        now: Date = Date(),
        angleMode: CalculatorAngleMode = .radians,
        previousAnswer: Decimal? = nil,
        exchangeRateProvider: (any ExchangeRateProviding)? = nil
    ) {
        self.locale = locale
        self.calendar = calendar
        self.timeZone = timeZone
        self.now = now
        self.angleMode = angleMode
        self.previousAnswer = previousAnswer
        self.exchangeRateProvider = exchangeRateProvider
    }
}

/// Angle interpretation for trigonometric functions.
public enum CalculatorAngleMode: String, Sendable, Equatable, CaseIterable {
    /// Interpret trigonometric arguments as radians.
    case radians
    /// Interpret trigonometric arguments as degrees.
    case degrees
}

/// Result of attempting to evaluate a calculator query.
public enum CalculatorEvaluationOutcome: Sendable, Equatable {
    /// Input is not a calculator query.
    case notCalculator
    /// Input looks like a calculator query but is incomplete while typing.
    case incomplete
    /// Evaluation succeeded.
    case success(CalculatorResult)
    /// Evaluation failed with a user-facing message (no secrets).
    case failure(CalculatorUserFacingError)
}

/// Stable identifier for a calculator result.
public struct CalculatorResultID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a new random identifier.
    public static func make() -> CalculatorResultID {
        CalculatorResultID(rawValue: UUID().uuidString)
    }
}

/// High-level kind of calculator result.
public enum CalculatorResultKind: String, Sendable, Equatable, CaseIterable {
    case arithmetic
    case scientific
    case percentage
    case unitConversion
    case currencyConversion
    case dateCalculation
    case timeZoneConversion
}

/// Primary typed value produced by evaluation.
public enum CalculatorValue: Sendable, Equatable {
    case decimal(Decimal)
    case double(Double)
    case date(Date)
    case measurement(CalculatorMeasurementValue)
    case currency(CalculatorCurrencyValue)
    case timeZoneInstant(CalculatorTimeZoneValue)
}

/// Dimension-agnostic measurement payload for results.
public struct CalculatorMeasurementValue: Sendable, Equatable {
    public let value: Double
    public let unitIdentifier: String
    public let unitSymbol: String
    public let dimension: CalculatorUnitDimension
    public let formatted: String?

    public init(
        value: Double,
        unitIdentifier: String,
        unitSymbol: String,
        dimension: CalculatorUnitDimension,
        formatted: String? = nil
    ) {
        self.value = value
        self.unitIdentifier = unitIdentifier
        self.unitSymbol = unitSymbol
        self.dimension = dimension
        self.formatted = formatted
    }
}

/// Currency amount with ISO code.
public struct CalculatorCurrencyValue: Sendable, Equatable {
    public let amount: Decimal
    public let code: CurrencyCode

    public init(amount: Decimal, code: CurrencyCode) {
        self.amount = amount
        self.code = code
    }
}

/// Instant expressed in a destination time zone.
public struct CalculatorTimeZoneValue: Sendable, Equatable {
    public let instant: Date
    public let timeZoneIdentifier: String
    public let sourceTimeZoneIdentifier: String?

    public init(instant: Date, timeZoneIdentifier: String, sourceTimeZoneIdentifier: String? = nil) {
        self.instant = instant
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
    }
}

/// Confidence that the input was a calculator query.
public enum CalculatorConfidence: String, Sendable, Equatable, Comparable, CaseIterable {
    case low
    case medium
    case high

    public static func < (lhs: CalculatorConfidence, rhs: CalculatorConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}

/// Suggested actions the host UI may expose for a result.
public enum CalculatorActionHint: String, Sendable, Equatable, CaseIterable {
    case copyResult
    case copyResultUnformatted
    case copyExpressionAndResult
    case insertIntoSearch
    case recalculateWithAnswer
    case showDetails
    case swapConversion
    case refreshCurrency
    case showRateTimestamp
    case showHistory
}

/// Safe, user-facing calculator error (never contains secrets or raw provider dumps).
public struct CalculatorUserFacingError: Error, Sendable, Equatable {
    /// Short message suitable for UI display.
    public let message: String
    /// Optional recovery hint.
    public let recoverySuggestion: String?

    public init(message: String, recoverySuggestion: String? = nil) {
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

/// Structured metadata attached to a successful result.
public struct CalculatorResultMetadata: Sendable, Equatable {
    public var baseAmount: Decimal?
    public var percentage: Decimal?
    public var percentageAmount: Decimal?
    public var total: Decimal?
    public var exchangeRate: Decimal?
    public var rateTimestamp: Date?
    public var rateIsStale: Bool?
    public var fromUnit: String?
    public var toUnit: String?
    public var fromCurrency: String?
    public var toCurrency: String?
    public var fromTimeZone: String?
    public var toTimeZone: String?
    public var angleMode: CalculatorAngleMode?
    public var notes: [String]

    public init(
        baseAmount: Decimal? = nil,
        percentage: Decimal? = nil,
        percentageAmount: Decimal? = nil,
        total: Decimal? = nil,
        exchangeRate: Decimal? = nil,
        rateTimestamp: Date? = nil,
        rateIsStale: Bool? = nil,
        fromUnit: String? = nil,
        toUnit: String? = nil,
        fromCurrency: String? = nil,
        toCurrency: String? = nil,
        fromTimeZone: String? = nil,
        toTimeZone: String? = nil,
        angleMode: CalculatorAngleMode? = nil,
        notes: [String] = []
    ) {
        self.baseAmount = baseAmount
        self.percentage = percentage
        self.percentageAmount = percentageAmount
        self.total = total
        self.exchangeRate = exchangeRate
        self.rateTimestamp = rateTimestamp
        self.rateIsStale = rateIsStale
        self.fromUnit = fromUnit
        self.toUnit = toUnit
        self.fromCurrency = fromCurrency
        self.toCurrency = toCurrency
        self.fromTimeZone = fromTimeZone
        self.toTimeZone = toTimeZone
        self.angleMode = angleMode
        self.notes = notes
    }
}

/// Successful calculator evaluation payload.
public struct CalculatorResult: Sendable, Equatable, Identifiable {
    public let id: CalculatorResultID
    public let kind: CalculatorResultKind
    public let originalInput: String
    public let normalizedInput: String
    public let displayExpression: String
    public let formattedPrimaryValue: String
    public let primaryValue: CalculatorValue
    public let metadata: CalculatorResultMetadata
    public let confidence: CalculatorConfidence
    public let actionHints: [CalculatorActionHint]

    public init(
        id: CalculatorResultID = .make(),
        kind: CalculatorResultKind,
        originalInput: String,
        normalizedInput: String,
        displayExpression: String,
        formattedPrimaryValue: String,
        primaryValue: CalculatorValue,
        metadata: CalculatorResultMetadata = CalculatorResultMetadata(),
        confidence: CalculatorConfidence,
        actionHints: [CalculatorActionHint] = [.copyResult, .copyResultUnformatted, .copyExpressionAndResult]
    ) {
        self.id = id
        self.kind = kind
        self.originalInput = originalInput
        self.normalizedInput = normalizedInput
        self.displayExpression = displayExpression
        self.formattedPrimaryValue = formattedPrimaryValue
        self.primaryValue = primaryValue
        self.metadata = metadata
        self.confidence = confidence
        self.actionHints = actionHints
    }
}

// MARK: - Internal errors

/// Internal calculator errors mapped to user-facing messages by the service.
enum CalculatorError: Error, Equatable, Sendable {
    case emptyInput
    case unexpectedCharacter(Character, SourceLocation)
    case invalidNumber(String, SourceLocation)
    case unexpectedToken(String, SourceLocation)
    case missingClosingParenthesis(SourceLocation)
    case invalidFunctionArity(name: String, expected: String)
    case unknownFunction(String)
    case unknownConstant(String)
    case divisionByZero
    case invalidDomain(function: String)
    case overflow
    case ambiguousUnit(String)
    case incompatibleUnits
    case unknownUnit(String)
    case unknownCurrency(String)
    case ambiguousCurrencySymbol(String)
    case exchangeRateUnavailable
    case staleExchangeRate
    case invalidDateExpression
    case ambiguousTimeZone(String)
    case missingPreviousAnswer
    case incompleteExpression
    case unsupportedOperation
    case cancelled
    case notCalculator

    var userFacingMessage: String {
        switch self {
        case .emptyInput:
            return "Enter a calculation."
        case .unexpectedCharacter:
            return "Unexpected character in expression."
        case .invalidNumber:
            return "Invalid number."
        case .unexpectedToken:
            return "Unexpected token in expression."
        case .missingClosingParenthesis:
            return "Missing closing parenthesis."
        case .invalidFunctionArity(let name, let expected):
            return "\(name) expects \(expected)."
        case .unknownFunction(let name):
            return "Unknown function “\(name)”."
        case .unknownConstant(let name):
            return "Unknown constant “\(name)”."
        case .divisionByZero:
            return "Cannot divide by zero."
        case .invalidDomain(let function):
            return "Invalid input for \(function)."
        case .overflow:
            return "Result is too large."
        case .ambiguousUnit(let unit):
            return "Ambiguous unit “\(unit)”. Try a more specific name."
        case .incompatibleUnits:
            return "Those units cannot be converted."
        case .unknownUnit(let unit):
            return "Unknown unit “\(unit)”."
        case .unknownCurrency(let code):
            return "Unknown currency “\(code)”."
        case .ambiguousCurrencySymbol(let symbol):
            return "Ambiguous currency symbol “\(symbol)”. Use an ISO code such as USD."
        case .exchangeRateUnavailable:
            return "Exchange rate unavailable."
        case .staleExchangeRate:
            return "Exchange rate is outdated."
        case .invalidDateExpression:
            return "Could not understand that date expression."
        case .ambiguousTimeZone(let name):
            return "Ambiguous time zone “\(name)”. Try a city or IANA identifier."
        case .missingPreviousAnswer:
            return "No previous answer available."
        case .incompleteExpression:
            return "Keep typing to finish the calculation."
        case .unsupportedOperation:
            return "That calculation is not supported."
        case .cancelled:
            return "Cancelled."
        case .notCalculator:
            return "Not a calculation."
        }
    }
}

/// Source location within the normalized input.
public struct SourceLocation: Sendable, Equatable {
    public let index: Int

    public init(index: Int) {
        self.index = index
    }
}

// MARK: - Classification

enum CalculatorIntent: Sendable, Equatable {
    case notCalculator
    case incomplete
    case arithmetic
    case scientific
    case percentage
    case unitConversion
    case currencyConversion
    case dateCalculation
    case timeZoneConversion
}

struct ClassificationResult: Sendable, Equatable {
    let intent: CalculatorIntent
    let confidence: CalculatorConfidence
}

// MARK: - Decimal helpers

enum DecimalMath {
    static let zero = Decimal(0)
    static let one = Decimal(1)
    static let hundred = Decimal(100)

    static func fromDouble(_ value: Double) -> Decimal? {
        guard value.isFinite else { return nil }
        return Decimal(value)
    }

    static func toDouble(_ value: Decimal) -> Double? {
        let number = NSDecimalNumber(decimal: value)
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite else { return nil }
        return doubleValue
    }

    static func pow(_ base: Decimal, _ exponent: Int) throws -> Decimal {
        if exponent == 0 { return DecimalMath.one }
        if base == .zero {
            if exponent < 0 { throw CalculatorError.divisionByZero }
            return .zero
        }
        var result: Decimal = 1
        let magnitude = abs(exponent)
        for _ in 0..<magnitude {
            let next = result * base
            if next == .nan {
                throw CalculatorError.overflow
            }
            result = next
        }
        if exponent < 0 {
            if result == .zero { throw CalculatorError.divisionByZero }
            return 1 / result
        }
        return result
    }

    static func isFinite(_ value: Decimal) -> Bool {
        !value.isNaN
    }
}
