import SwiftUI

struct LauncherConfigurationFieldEditor: View {
    let field: LauncherConfigurationField
    let value: LauncherConfigurationValue
    let onChange: (LauncherConfigurationValue) -> Void

    var body: some View {
        InspectorFieldRow(title: field.title, description: field.description) {
            editor
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch field.kind {
        case .text:
            TextField(
                field.placeholder ?? "Value",
                text: Binding(
                    get: { value.textValue ?? "" },
                    set: { onChange(.text($0)) }
                )
            )
            .textFieldStyle(.plain)
            .inspectorInputStyle(width: 140)
            .accessibilityLabel(field.title)
        case .toggle:
            Toggle(
                field.title,
                isOn: Binding(
                    get: { value.booleanValue ?? false },
                    set: { onChange(.boolean($0)) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        case .integer:
            integerEditor
        case .decimal:
            decimalEditor
        case .selection:
            Picker(
                field.title,
                selection: Binding(
                    get: { value.textValue ?? field.options.first?.id ?? "" },
                    set: { onChange(.text($0)) }
                )
            ) {
                ForEach(field.options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)
        }
    }

    @ViewBuilder
    private var integerEditor: some View {
        if let range = field.integerRange {
            BoundedIntegerEditor(
                title: field.title,
                value: value.integerValue ?? field.defaultValue.integerValue ?? 0,
                range: range,
                step: field.integerStep,
                onChange: { onChange(.integer($0)) }
            )
        } else {
            TextField(
                field.placeholder ?? "0",
                value: Binding(
                    get: { value.integerValue ?? 0 },
                    set: { onChange(.integer($0)) }
                ),
                format: .number
            )
            .textFieldStyle(.plain)
            .inspectorInputStyle(width: 88)
            .accessibilityLabel(field.title)
        }
    }

    @ViewBuilder
    private var decimalEditor: some View {
        if let range = field.decimalRange {
            BoundedDecimalEditor(
                title: field.title,
                value: value.decimalValue ?? field.defaultValue.decimalValue ?? 0,
                range: range,
                step: field.decimalStep,
                onChange: { onChange(.decimal($0)) }
            )
        } else {
            TextField(
                field.placeholder ?? "0",
                value: Binding(
                    get: { value.decimalValue ?? 0 },
                    set: { onChange(.decimal($0)) }
                ),
                format: .number
            )
            .textFieldStyle(.plain)
            .inspectorInputStyle(width: 88)
            .accessibilityLabel(field.title)
        }
    }
}

private struct BoundedIntegerEditor: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        Stepper(
            value: Binding(
                get: { clampedValue },
                set: { newValue in onChange(newValue) }
            ),
            in: range,
            step: step
        ) {
            Text(clampedValue, format: .number)
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
        }
        .controlSize(.small)
        .accessibilityLabel(title)
        .accessibilityValue(clampedValue.formatted())
    }

    private var clampedValue: Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct BoundedDecimalEditor: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: (Double) -> Void

    var body: some View {
        Stepper(
            value: Binding(
                get: { clampedValue },
                set: { newValue in onChange(newValue) }
            ),
            in: range,
            step: step
        ) {
            Text(clampedValue, format: .number.precision(.fractionLength(0...2)))
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)
        }
        .controlSize(.small)
        .accessibilityLabel(title)
        .accessibilityValue(
            clampedValue.formatted(.number.precision(.fractionLength(0...2)))
        )
    }

    private var clampedValue: Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private extension LauncherConfigurationField {
    var integerRange: ClosedRange<Int>? {
        guard kind == .integer,
              let minimumValue,
              let maximumValue,
              minimumValue.isFinite,
              maximumValue.isFinite,
              minimumValue.rounded() == minimumValue,
              maximumValue.rounded() == maximumValue,
              let minimum = Int(exactly: minimumValue),
              let maximum = Int(exactly: maximumValue),
              minimum <= maximum else {
            return nil
        }
        return minimum...maximum
    }

    var integerStep: Int {
        guard let step,
              step.isFinite,
              let integerStep = Int(exactly: step.rounded()),
              integerStep >= 1 else {
            return 1
        }
        return integerStep
    }

    var decimalRange: ClosedRange<Double>? {
        guard kind == .decimal,
              let minimumValue,
              let maximumValue,
              minimumValue.isFinite,
              maximumValue.isFinite,
              minimumValue <= maximumValue else {
            return nil
        }
        return minimumValue...maximumValue
    }

    var decimalStep: Double {
        guard let step, step.isFinite, step > 0 else { return 0.1 }
        return step
    }
}
