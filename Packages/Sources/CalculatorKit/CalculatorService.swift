import Foundation

/// Production calculator service: classify → normalize → specialized path or parse/eval → format.
public struct CalculatorService: CalculatorEvaluating {
    private let classifier: CalculatorClassifier
    private let normalizer: CalculatorNormalizer
    private let lexer: CalculatorLexer
    private let suggestionEngine: CalculatorSuggestionEngine

    /// Creates a calculator service.
    public init() {
        self.classifier = CalculatorClassifier()
        self.normalizer = CalculatorNormalizer()
        self.lexer = CalculatorLexer()
        self.suggestionEngine = CalculatorSuggestionEngine()
    }

    public func evaluate(
        _ input: String,
        context: CalculatorEvaluationContext
    ) async -> CalculatorEvaluationOutcome {
        await evaluate(input, context: context, allowsPrediction: true)
    }

    public func suggestion(
        for input: String,
        context: CalculatorEvaluationContext
    ) async -> CalculatorSuggestion? {
        guard Task.isCancelled == false else { return nil }
        return suggestionEngine.suggestion(for: input)
    }

    private func evaluate(
        _ input: String,
        context: CalculatorEvaluationContext,
        allowsPrediction: Bool
    ) async -> CalculatorEvaluationOutcome {
        do {
            try Task.checkCancellation()

            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .notCalculator
            }

            if trimmed.range(of: #"^\d{2}/\d{2}(?:/\d{4})?$"#, options: .regularExpression) != nil {
                let direct = NormalizedInput(original: trimmed, text: trimmed, displayExpression: trimmed)
                return try evaluateDate(direct, context: context, confidence: .high)
            }

            // Normalize before classification so NL aliases ("plus", "×") participate.
            let normalized = normalizer.normalize(trimmed, context: context)
            try Task.checkCancellation()

            let classification = classifier.classify(normalized.text)
            if classification.intent == .notCalculator {
                // Re-check original for specialized NL date/tz phrases that normalizer may alter.
                let originalClassification = classifier.classify(trimmed)
                if originalClassification.intent == .notCalculator {
                    return await predictedOutcome(for: trimmed, context: context, fallback: .notCalculator, allowed: allowsPrediction)
                }
                return try await route(
                    intent: originalClassification.intent,
                    confidence: originalClassification.confidence,
                    normalized: normalized,
                    context: context
                )
            }
            if classification.intent == .incomplete {
                return await predictedOutcome(for: trimmed, context: context, fallback: .incomplete, allowed: allowsPrediction)
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
                return await predictedOutcome(for: input, context: context, fallback: .incomplete, allowed: allowsPrediction)
            }
            if error == .notCalculator {
                return await predictedOutcome(for: input, context: context, fallback: .notCalculator, allowed: allowsPrediction)
            }
            let fallback = CalculatorEvaluationOutcome.failure(CalculatorUserFacingError(message: error.userFacingMessage))
            return await predictedOutcome(for: input, context: context, fallback: fallback, allowed: allowsPrediction)
        } catch {
            return .failure(CalculatorUserFacingError(message: "Something went wrong evaluating that calculation."))
        }
    }

    private func predictedOutcome(
        for input: String,
        context: CalculatorEvaluationContext,
        fallback: CalculatorEvaluationOutcome,
        allowed: Bool
    ) async -> CalculatorEvaluationOutcome {
        guard allowed, let suggestion = suggestionEngine.suggestion(for: input),
              suggestion.completedInput.caseInsensitiveCompare(input.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame else {
            return fallback
        }
        let candidate = await evaluate(suggestion.completedInput, context: context, allowsPrediction: false)
        guard case .success(let result) = candidate else { return fallback }
        var metadata = result.metadata
        metadata.notes.append("Live preview inferred from “\(suggestion.completedInput)”.")
        return .success(CalculatorResult(
            kind: result.kind,
            originalInput: input,
            normalizedInput: result.normalizedInput,
            displayExpression: result.displayExpression,
            formattedPrimaryValue: result.formattedPrimaryValue,
            primaryValue: result.primaryValue,
            metadata: metadata,
            confidence: suggestion.confidence,
            actionHints: result.actionHints,
            suggestion: suggestion
        ))
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
        case .financial:
            return try evaluateFinancial(normalized, context: context, confidence: confidence)
        case .unitConversion:
            return try evaluateUnits(normalized, context: context, confidence: confidence)
        case .dateCalculation:
            return try evaluateDate(normalized, context: context, confidence: confidence)
        case .timeZoneConversion:
            return try evaluateTimeZone(normalized, context: context, confidence: confidence)
        case .calculationSuite:
            return try evaluateCalculationSuite(normalized, context: context, confidence: confidence)
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

        if let specialized = CalculatorUtilities.advanced(
            normalized.original,
            lowered: normalized.original.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        ) {
            return .success(CalculatorResult(
                kind: specialized.kind,
                originalInput: normalized.original,
                normalizedInput: normalized.text,
                displayExpression: specialized.displayExpression,
                formattedPrimaryValue: specialized.formattedPrimaryValue
                    ?? CalculatorFormatter.formatPrimary(specialized.primaryValue, context: context),
                primaryValue: specialized.primaryValue,
                metadata: specialized.metadata,
                confidence: confidence,
                actionHints: [.copyResult, .copyResultUnformatted, .copyExpressionAndResult, .showDetails]
            ))
        }

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

        // Number separators are canonicalized by the normalizer; tokenize the
        // resulting grammar with a stable decimal point and comma arguments.
        let tokens = try lexer.tokenize(normalized.text, locale: Locale(identifier: "en_US_POSIX"))
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
        let conversion = try await CalculatorCurrency.evaluate(normalized.text, provider: provider, locale: context.locale)
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

    private func evaluateFinancial(
        _ normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence
    ) throws -> CalculatorEvaluationOutcome {
        let financial = try CalculatorFinance.evaluate(normalized.text, context: context)
        guard DecimalMath.isFinite(financial.value) else { throw CalculatorError.overflow }
        let primary = CalculatorValue.decimal(financial.value)
        return .success(CalculatorResult(
            kind: .financial,
            originalInput: normalized.original,
            normalizedInput: normalized.text,
            displayExpression: financial.displayExpression,
            formattedPrimaryValue: CalculatorFormatter.formatPrimary(primary, context: context),
            primaryValue: primary,
            metadata: financial.metadata,
            confidence: confidence,
            actionHints: [.copyResult, .copyResultUnformatted, .copyExpressionAndResult, .showDetails]
        ))
    }

    private func evaluateUnits(
        _ normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence
    ) throws -> CalculatorEvaluationOutcome {
        if normalized.text.lowercased().range(
            of: #"^[-+]?\d+(?:\.\d+)?\s*(?:m|oz|gal|ton|c)$"#,
            options: .regularExpression
        ) != nil {
            throw CalculatorError.ambiguousUnit(normalized.original)
        }
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
        if let result = try CalculatorCalendar.evaluate(normalized.original, context: context) {
            return .success(CalculatorResult(
                kind: .dateCalculation,
                originalInput: normalized.original,
                normalizedInput: normalized.text,
                displayExpression: result.displayExpression,
                formattedPrimaryValue: result.formattedPrimaryValue
                    ?? CalculatorFormatter.formatPrimary(result.primaryValue, context: context),
                primaryValue: result.primaryValue,
                metadata: result.metadata,
                confidence: confidence,
                actionHints: [.copyResult, .copyResultUnformatted, .copyExpressionAndResult, .showDetails]
            ))
        }
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
        if let result = try CalculatorTime.evaluate(normalized.original, context: context) {
            return .success(CalculatorResult(
                kind: result.kind,
                originalInput: normalized.original,
                normalizedInput: normalized.text,
                displayExpression: result.displayExpression,
                formattedPrimaryValue: result.formattedPrimaryValue
                    ?? CalculatorFormatter.formatPrimary(result.primaryValue, context: context),
                primaryValue: result.primaryValue,
                metadata: result.metadata,
                confidence: confidence,
                actionHints: [.copyResult, .copyResultUnformatted, .copyExpressionAndResult, .showDetails]
            ))
        }
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

    private func evaluateCalculationSuite(
        _ normalized: NormalizedInput,
        context: CalculatorEvaluationContext,
        confidence: CalculatorConfidence
    ) throws -> CalculatorEvaluationOutcome {
        let result = try CalculatorUtilities.evaluate(normalized.original, context: context)
        return .success(CalculatorResult(
            kind: result.kind,
            originalInput: normalized.original,
            normalizedInput: normalized.text,
            displayExpression: result.displayExpression,
            formattedPrimaryValue: result.formattedPrimaryValue
                ?? CalculatorFormatter.formatPrimary(result.primaryValue, context: context),
            primaryValue: result.primaryValue,
            metadata: result.metadata,
            confidence: confidence,
            actionHints: [.copyResult, .copyResultUnformatted, .copyExpressionAndResult, .showDetails]
        ))
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
        return open > close && !trimmed.hasSuffix(")")
    }
}
