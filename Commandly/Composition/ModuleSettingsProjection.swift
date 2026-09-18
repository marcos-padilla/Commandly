import ModuleKit

/// Projects a module's authored configuration schema onto the launcher's settings model.
///
/// Modules author their preferences once, in ``ModuleSettingsContribution``. The launcher's
/// generic Applications settings screen keeps rendering ``LauncherConfigurationField`` values, so
/// this projection exists to avoid a second hand-maintained copy of every field.
///
/// The mapping is intentionally total and lossless: adding a field kind to ``ModuleKit`` forces a
/// compile error here rather than silently dropping a control.
extension LauncherConfigurationValue {
    /// Creates a launcher value from a module configuration value.
    init(moduleValue: ModuleConfigurationValue) {
        switch moduleValue {
        case .text(let value): self = .text(value)
        case .boolean(let value): self = .boolean(value)
        case .integer(let value): self = .integer(value)
        case .decimal(let value): self = .decimal(value)
        }
    }

    /// Projects a launcher value back onto the module schema type.
    var moduleValue: ModuleConfigurationValue {
        switch self {
        case .text(let value): return .text(value)
        case .boolean(let value): return .boolean(value)
        case .integer(let value): return .integer(value)
        case .decimal(let value): return .decimal(value)
        }
    }
}

extension LauncherConfigurationFieldKind {
    /// Creates a launcher control kind from a module field kind.
    init(moduleKind: ModuleConfigurationFieldKind) {
        switch moduleKind {
        case .text: self = .text
        case .toggle: self = .toggle
        case .integer: self = .integer
        case .decimal: self = .decimal
        case .selection: self = .selection
        }
    }
}

extension LauncherConfigurationOption {
    /// Creates a launcher selection option from a module option.
    init(moduleOption: ModuleConfigurationOption) {
        self.init(
            id: moduleOption.id,
            title: moduleOption.title,
            description: moduleOption.description
        )
    }
}

extension LauncherConfigurationField {
    /// Creates a launcher settings field from a module's authored schema.
    init(moduleField: ModuleConfigurationField) {
        self.init(
            id: moduleField.id,
            variable: moduleField.variable,
            title: moduleField.title,
            description: moduleField.description,
            placeholder: moduleField.placeholder,
            section: moduleField.section,
            kind: LauncherConfigurationFieldKind(moduleKind: moduleField.kind),
            defaultValue: LauncherConfigurationValue(moduleValue: moduleField.defaultValue),
            options: moduleField.options.map(LauncherConfigurationOption.init(moduleOption:)),
            minimumValue: moduleField.minimumValue,
            maximumValue: moduleField.maximumValue,
            step: moduleField.step
        )
    }
}

/// Projects a module's whole settings contribution onto launcher settings fields.
///
/// A plain loop is used instead of `map` so the call stays inside the caller's main-actor
/// context rather than converting an isolated initializer into a non-isolated function value.
extension ModuleSettingsContribution {
    /// The contribution's fields, as launcher settings fields.
    var launcherConfigurationFields: [LauncherConfigurationField] {
        var projected: [LauncherConfigurationField] = []
        projected.reserveCapacity(fields.count)
        for field in fields {
            projected.append(LauncherConfigurationField(moduleField: field))
        }
        return projected
    }
}
