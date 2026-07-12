import Foundation

/// Production calculator service: classify → normalize → specialized path or parse/eval → format.
public struct CalculatorService: CalculatorEvaluating {
    private let classifier: CalculatorClassifier
    private let normalizer: CalculatorNormalizer
    private let lexer: CalculatorLexer

    /// Creates a calculator service.
    public init() {
        self.classifier = CalculatorClassifier()
        self.normalizer = CalculatorNormalizer()
        self.lexer = CalculatorLexer()
    }

    public func evaluate(
        _ input: String,
        context: CalculatorEvaluationContext
    ) async -> CalculatorEvaluationOutcome {
        do {
            try Task.checkCancellation()

            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .notCalculator
            }

            // Normalize before classification so NL aliases ("plus", "×") participate.
            let normalized = normalizer.normalize(trimmed, context: context)
            try Task.checkCancellation()

            let classification = classifier.classify(normalized.text)
            if classification.intent == .notCalculator {
                // Re-check original for specialized NL date/tz phrases that normalizer may alter.
                let originalClassification = classifier.classify(trimmed)
                if originalClassification.intent == .notCalculator {
                    return .notCalculator
                }
                return try await route(
                    intent: originalClassification.intent,
                    confidence: originalClassification.confidence,
                    normalized: normalized,
                    context: context
                )
            }
            if classification.intent == .incomplete {
                return .incomplete
            }

            return try await route(
                intent: classification.intent,
                confidence: classification.confidence,
                normalized: normalized,
                context: context
            )
        } catch is CancellationError {
            return .failure(CalculatorUserFacingError(message: CalculatorError.cancelled.userFacingMessage))
        } catch let error as CalculatorError {
            if error == .cancelled {
                return .incomplete
            }
            if error == .incompleteExpression {
                return .incomplete
            }
            if error == .notCalculator {
                return .notCalculator
            }
            return .failure(CalculatorUserFacingError(message: error.userFacingMessage))
        } catch {
            return .failure(CalculatorUserFacingError(message: "Something went wrong evaluating that calculation."))
        }
    }

    private func route(
        intent: CalculatorIntent,
        confidence: CalculatorConfidence,
        normalized: NormalizedInput,
        context: CalculatorEvaluationContext
    ) async throws -> CalculatorEvaluationOutcome {
        switch intent {
        case .notCalculator:
            return .notCalculator
        case .incomplete:
            return .incomplete
        case .currencyConversion:
            return try await evaluateCurrency(normalized, context: context, confidence: confidence)
        case .unitConversion:
            return try evaluateUnits(normalized, context: context, confidence: confidence)
        case .dateCalculation:
            return try evaluateDate(normalized, context: context, confidence: confidence)
        case .timeZoneConversion:
            return try evaluateTimeZone(normalized, context: context, confidence: confidence)
        case .percentage, .arithmetic, .scientific:
            return try evaluateExpression(
                normalized,
                context: context,
                confidence: confidence,
                preferredKind: intent
            )
        }
    }

    // MARK: - Paths

    private func evaluateExpression(
        _ normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence,
        preferredKind: CalculatorIntent
    ) throws -> CalculatorEvaluationOutcome {
        try Task.checkCancellation()

        // Tip / tax / discount / "of" phrases.
        if let phrase = PercentagePhraseParser.parse(normalized.text) {
            let output = try CalculatorArithmetic.evaluate(phrase.expression, context: context, phraseTag: phrase.tag)
            return .success(makeDecimalResult(
                output: output,
                normalized: normalized,
                context: context,
                confidence: confidence
            ))
        }

        // Detect incomplete after normalization.
        if isIncompleteSyntax(normalized.text) {
            return .incomplete
        }

        let tokens = try lexer.tokenize(normalized.text, locale: context.locale)
        var parser = CalculatorParser()
        let expression = try parser.parse(tokens)
        let output = try CalculatorArithmetic.evaluate(expression, context: context, phraseTag: nil)

        var adjusted = output
        if preferredKind == .scientific || output.usedScientific {
            adjusted = CalculatorArithmetic.EvaluationOutput(
                value: output.value,
                kind: .scientific,
                metadata: {
                    var meta = output.metadata
                    meta.angleMode = context.angleMode
                    return meta
                }(),
                usedScientific: true
            )
        }

        return .success(makeDecimalResult(
            output: adjusted,
            normalized: normalized,
            context: context,
            confidence: confidence
        ))
    }

    private func evaluateCurrency(
        _ normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence
    ) async throws -> CalculatorEvaluationOutcome {
        guard let provider = context.exchangeRateProvider else {
            throw CalculatorError.exchangeRateUnavailable
        }
        // Ambiguous $
        if normalized.text.contains("$") && !normalized.text.uppercased().contains("USD") {
            throw CalculatorError.ambiguousCurrencySymbol("$")
        }
        let conversion = try await CalculatorCurrency.evaluate(normalized.text, provider: provider)
        let primary = CalculatorValue.currency(conversion.value)
        var hints: [CalculatorActionHint] = [
            .copyResult, .copyResultUnformatted, .copyExpressionAndResult,
            .swapConversion, .refreshCurrency, .showRateTimestamp, .showDetails,
        ]
        if conversion.metadata.rateIsStale == true {
            hints.append(.refreshCurrency)
        }
        return .success(
            CalculatorResult(
                kind: .currencyConversion,
                originalInput: normalized.original,
                normalizedInput: normalized.text,
                displayExpression: conversion.displayExpression,
                formattedPrimaryValue: CalculatorFormatter.formatPrimary(primary, context: context),
                primaryValue: primary,
                metadata: conversion.metadata,
                confidence: confidence,
                actionHints: hints
            )
        )
    }

    private func evaluateUnits(
        _ normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence
    ) throws -> CalculatorEvaluationOutcome {
        let conversion = try CalculatorUnits.evaluate(normalized.text, locale: context.locale)
        let primary = CalculatorValue.measurement(conversion.value)
        return .success(
            CalculatorResult(
                kind: .unitConversion,
                originalInput: normalized.original,
                normalizedInput: normalized.text,
                displayExpression: conversion.displayExpression,
                formattedPrimaryValue: CalculatorFormatter.formatPrimary(primary, context: context),
                primaryValue: primary,
                metadata: conversion.metadata,
                confidence: confidence,
                actionHints: [.copyResult, .copyResultUnformatted, .copyExpressionAndResult, .swapConversion, .showDetails]
            )
        )
    }

    private func evaluateDate(
        _ normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence
    ) throws -> CalculatorEvaluationOutcome {
        let result = try CalculatorDateTime.evaluateDate(normalized.text, context: context)

        if let dayNote = result.metadata.notes.first(where: { $0.hasPrefix("dayCount:") }) {
            let countText = String(dayNote.dropFirst("dayCount:".count))
            let count = Decimal(string: countText) ?? 0
            let primary = CalculatorValue.decimal(count)
            return .success(
                CalculatorResult(
                    kind: .dateCalculation,
                    originalInput: normalized.original,
                    normalizedInput: normalized.text,
                    displayExpression: result.displayExpression,
                    formattedPrimaryValue: CalculatorFormatter.formatDecimal(count, locale: context.locale),
                    primaryValue: primary,
                    metadata: result.metadata,
                    confidence: confidence,
                    actionHints: [.copyResult, .copyExpressionAndResult, .showDetails]
                )
            )
        }

        if let weekNote = result.metadata.notes.first(where: { $0.hasPrefix("weekCount:") }) {
            let countText = String(weekNote.dropFirst("weekCount:".count))
            let count = Decimal(string: countText) ?? 0
            let primary = CalculatorValue.decimal(count)
            return .success(
                CalculatorResult(
                    kind: .dateCalculation,
                    originalInput: normalized.original,
                    normalizedInput: normalized.text,
                    displayExpression: result.displayExpression,
                    formattedPrimaryValue: CalculatorFormatter.formatDecimal(count, locale: context.locale),
                    primaryValue: primary,
                    metadata: result.metadata,
                    confidence: confidence,
                    actionHints: [.copyResult, .copyExpressionAndResult, .showDetails]
                )
            )
        }

        let primary = CalculatorValue.date(result.date)
        return .success(
            CalculatorResult(
                kind: .dateCalculation,
                originalInput: normalized.original,
                normalizedInput: normalized.text,
                displayExpression: result.displayExpression,
                formattedPrimaryValue: CalculatorFormatter.formatPrimary(primary, context: context),
                primaryValue: primary,
                metadata: result.metadata,
                confidence: confidence,
                actionHints: [.copyResult, .copyExpressionAndResult, .showDetails]
            )
        )
    }

    private func evaluateTimeZone(
        _ normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence
    ) throws -> CalculatorEvaluationOutcome {
        let result = try CalculatorDateTime.evaluateTimeZone(normalized.text, context: context)

        if let offsetNote = result.metadata.notes.first(where: { $0.hasPrefix("offsetHours:") }) {
            let countText = String(offsetNote.dropFirst("offsetHours:".count))
            let count = Decimal(string: countText) ?? 0
            let primary = CalculatorValue.decimal(count)
            return .success(
                CalculatorResult(
                    kind: .timeZoneConversion,
                    originalInput: normalized.original,
                    normalizedInput: normalized.text,
                    displayExpression: result.displayExpression,
                    formattedPrimaryValue: CalculatorFormatter.formatDecimal(count, locale: context.locale) + " h",
                    primaryValue: primary,
                    metadata: result.metadata,
                    confidence: confidence,
                    actionHints: [.copyResult, .showDetails, .swapConversion]
                )
            )
        }

        let primary = CalculatorValue.timeZoneInstant(result.value)
        return .success(
            CalculatorResult(
                kind: .timeZoneConversion,
                originalInput: normalized.original,
                normalizedInput: normalized.text,
                displayExpression: result.displayExpression,
                formattedPrimaryValue: CalculatorFormatter.formatPrimary(primary, context: context),
                primaryValue: primary,
                metadata: result.metadata,
                confidence: confidence,
                actionHints: [.copyResult, .copyExpressionAndResult, .showDetails, .swapConversion]
            )
        )
    }

    private func makeDecimalResult(
        output: CalculatorArithmetic.EvaluationOutput,
        normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence
    ) -> CalculatorResult {
        let primary = CalculatorValue.decimal(output.value)
        var hints: [CalculatorActionHint] = [
            .copyResult, .copyResultUnformatted, .copyExpressionAndResult,
            .insertIntoSearch, .recalculateWithAnswer, .showDetails,
        ]
        if output.kind == .percentage {
            hints.append(.showDetails)
        }
        return CalculatorResult(
            kind: output.kind,
            originalInput: normalized.original,
            normalizedInput: normalized.text,
            displayExpression: normalized.displayExpression,
            formattedPrimaryValue: CalculatorFormatter.formatPrimary(primary, context: context),
            primaryValue: primary,
            metadata: output.metadata,
            confidence: confidence,
            actionHints: hints
        )
    }

    private func isIncompleteSyntax(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let last = trimmed.last, "+-*/^(".contains(last) {
            return true
        }
        let open = trimmed.filter { $0 == "(" }.count
        let close = trimmed.filter { $0 == ")" }.count
        return open > close
    }
}
