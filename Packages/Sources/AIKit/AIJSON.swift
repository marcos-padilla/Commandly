import Foundation

/// Provider-neutral representation of a JSON value.
///
/// This type is used for structured message content, tool arguments, and tool results so provider
/// adapters never expose vendor SDK types to the rest of the application.
public indirect enum AIJSONValue: Sendable, Equatable, Codable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([AIJSONValue])
    case object([String: AIJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AIJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AIJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .boolean(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    /// Decodes a JSON value from data.
    public init(data: Data) throws {
        self = try JSONDecoder().decode(AIJSONValue.self, from: data)
    }

    /// Encodes this value as JSON data.
    public func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Returns the underlying object, if this value is an object.
    public var objectValue: [String: AIJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    /// Returns the underlying array, if this value is an array.
    public var arrayValue: [AIJSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    /// Returns the underlying string, if this value is a string.
    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    /// Returns the underlying boolean, if this value is a boolean.
    public var booleanValue: Bool? {
        guard case let .boolean(value) = self else { return nil }
        return value
    }

    /// Returns the underlying number, if this value is a number.
    public var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        guard let numberValue, numberValue.isFinite, numberValue.rounded() == numberValue else {
            return nil
        }
        return Int(exactly: numberValue)
    }

    /// Returns a property when this value is an object.
    public subscript(key: String) -> AIJSONValue? {
        objectValue?[key]
    }
}

/// JSON Schema subset accepted for AI tool inputs.
///
/// The deliberately small type-safe surface keeps tool schemas portable across providers. It can
/// be expanded without changing the public tool-call model when additional providers need it.
public indirect enum AIJSONSchema: Sendable, Equatable, Codable {
    case object(
        properties: [String: AIJSONSchema],
        required: [String],
        additionalProperties: Bool,
        description: String?
    )
    case array(items: AIJSONSchema, description: String?)
    case string(allowedValues: [String]?, description: String?)
    case integer(minimum: Int?, maximum: Int?, description: String?)
    case number(minimum: Double?, maximum: Double?, description: String?)
    case boolean(description: String?)

    /// Creates an object schema with closed additional properties by default.
    public static func closedObject(
        properties: [String: AIJSONSchema],
        required: [String] = [],
        additionalProperties: Bool = false,
        description: String? = nil
    ) -> AIJSONSchema {
        .object(
            properties: properties,
            required: required,
            additionalProperties: additionalProperties,
            description: description
        )
    }

    public init(from decoder: Decoder) throws {
        let value = try AIJSONValue(from: decoder)
        self = try Self.decode(value)
    }

    public func encode(to encoder: Encoder) throws {
        try jsonValue.encode(to: encoder)
    }

    /// Validates the schema itself before it is sent to a provider.
    public func validate() throws {
        switch self {
        case let .object(properties, required, _, _):
            let propertyNames = Set(properties.keys)
            let unknownRequired = Set(required).subtracting(propertyNames)
            guard unknownRequired.isEmpty else {
                throw AIJSONSchemaError.requiredPropertyMissingFromSchema
            }
            guard Set(required).count == required.count else {
                throw AIJSONSchemaError.duplicateRequiredProperty
            }
            try properties.values.forEach { try $0.validate() }

        case let .array(items, _):
            try items.validate()

        case let .string(allowedValues, _):
            if let allowedValues, Set(allowedValues).count != allowedValues.count {
                throw AIJSONSchemaError.duplicateAllowedValue
            }

        case let .integer(minimum, maximum, _):
            if let minimum, let maximum, minimum > maximum {
                throw AIJSONSchemaError.invalidNumericRange
            }

        case let .number(minimum, maximum, _):
            if let minimum, let maximum, minimum > maximum {
                throw AIJSONSchemaError.invalidNumericRange
            }

        case .boolean:
            break
        }
    }

    var jsonValue: AIJSONValue {
        var object: [String: AIJSONValue]

        switch self {
        case let .object(properties, required, additionalProperties, description):
            object = [
                "type": .string("object"),
                "properties": .object(properties.mapValues(\.jsonValue)),
                "additionalProperties": .boolean(additionalProperties)
            ]
            if !required.isEmpty {
                object["required"] = .array(required.map(AIJSONValue.string))
            }
            Self.insert(description, into: &object)

        case let .array(items, description):
            object = ["type": .string("array"), "items": items.jsonValue]
            Self.insert(description, into: &object)

        case let .string(allowedValues, description):
            object = ["type": .string("string")]
            if let allowedValues {
                object["enum"] = .array(allowedValues.map(AIJSONValue.string))
            }
            Self.insert(description, into: &object)

        case let .integer(minimum, maximum, description):
            object = ["type": .string("integer")]
            if let minimum { object["minimum"] = .number(Double(minimum)) }
            if let maximum { object["maximum"] = .number(Double(maximum)) }
            Self.insert(description, into: &object)

        case let .number(minimum, maximum, description):
            object = ["type": .string("number")]
            if let minimum { object["minimum"] = .number(minimum) }
            if let maximum { object["maximum"] = .number(maximum) }
            Self.insert(description, into: &object)

        case let .boolean(description):
            object = ["type": .string("boolean")]
            Self.insert(description, into: &object)
        }

        return .object(object)
    }

    private static func insert(_ description: String?, into object: inout [String: AIJSONValue]) {
        if let description, !description.isEmpty {
            object["description"] = .string(description)
        }
    }

    private static func decode(_ value: AIJSONValue) throws -> AIJSONSchema {
        guard let object = value.objectValue, let type = object["type"]?.stringValue else {
            throw AIJSONSchemaError.malformedSchema
        }
        let description = object["description"]?.stringValue

        switch type {
        case "object":
            let propertyValues = object["properties"]?.objectValue ?? [:]
            var properties: [String: AIJSONSchema] = [:]
            for (name, property) in propertyValues {
                properties[name] = try decode(property)
            }
            let required = object["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let additionalProperties = object["additionalProperties"]?.booleanValue ?? false
            return .object(
                properties: properties,
                required: required,
                additionalProperties: additionalProperties,
                description: description
            )

        case "array":
            guard let items = object["items"] else { throw AIJSONSchemaError.malformedSchema }
            return .array(items: try decode(items), description: description)

        case "string":
            let allowedValues = object["enum"]?.arrayValue?.compactMap(\.stringValue)
            return .string(allowedValues: allowedValues, description: description)

        case "integer":
            return .integer(
                minimum: object["minimum"]?.integerValue,
                maximum: object["maximum"]?.integerValue,
                description: description
            )

        case "number":
            return .number(
                minimum: object["minimum"]?.numberValue,
                maximum: object["maximum"]?.numberValue,
                description: description
            )

        case "boolean":
            return .boolean(description: description)

        default:
            throw AIJSONSchemaError.unsupportedSchemaType
        }
    }
}

/// Errors produced while validating or decoding a portable tool schema.
public enum AIJSONSchemaError: Error, Sendable, Equatable {
    case malformedSchema
    case unsupportedSchemaType
    case requiredPropertyMissingFromSchema
    case duplicateRequiredProperty
    case duplicateAllowedValue
    case invalidNumericRange
}
