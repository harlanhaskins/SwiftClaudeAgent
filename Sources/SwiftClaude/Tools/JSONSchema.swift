import Foundation

// MARK: - JSON Schema Types

/// Represents a JSON Schema for tool inputs or API responses.
///
/// This provides a type-safe representation of JSON Schema without resorting
/// to type erasure like `[String: Any]` or `AnyCodable`.
public struct JSONSchema: Sendable, Codable, Equatable {
    public let type: SchemaType
    public let properties: [String: JSONSchemaProperty]?
    public let required: [String]?
    public let items: JSONSchemaProperty?  // For array types
    public let enumValues: [String]?  // For enum types

    public init(
        type: SchemaType,
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil,
        items: JSONSchemaProperty? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.items = items
        self.enumValues = enumValues
    }

    /// Create an object schema with properties
    public static func object(
        properties: [String: JSONSchemaProperty],
        required: [String] = []
    ) -> JSONSchema {
        JSONSchema(
            type: .object,
            properties: properties,
            required: required.isEmpty ? nil : required
        )
    }

    /// Create an array schema with item type
    public static func array(items: JSONSchemaProperty) -> JSONSchema {
        JSONSchema(type: .array, items: items)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case items
        case enumValues = "enum"
    }
}

/// A property within a JSON Schema
public indirect enum JSONSchemaProperty: Sendable, Codable, Equatable {
    case primitive(type: SchemaType, description: String?)
    case array(items: JSONSchemaProperty, description: String?)
    case object(properties: [String: JSONSchemaProperty], required: [String], description: String?)
    case enumeration(values: [String], description: String?)

    public var type: SchemaType {
        switch self {
        case .primitive(let type, _): return type
        case .array: return .array
        case .object: return .object
        case .enumeration: return .string
        }
    }

    public var description: String? {
        switch self {
        case .primitive(_, let desc): return desc
        case .array(_, let desc): return desc
        case .object(_, _, let desc): return desc
        case .enumeration(_, let desc): return desc
        }
    }

    public init(
        type: SchemaType,
        description: String? = nil,
        items: JSONSchemaProperty? = nil,
        enumValues: [String]? = nil,
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil
    ) {
        if let enumValues = enumValues {
            self = .enumeration(values: enumValues, description: description)
        } else if let items = items {
            self = .array(items: items, description: description)
        } else if let properties = properties {
            self = .object(properties: properties, required: required ?? [], description: description)
        } else {
            self = .primitive(type: type, description: description)
        }
    }

    /// Create a string property
    public static func string(
        description: String? = nil,
        enumValues: [String]? = nil
    ) -> JSONSchemaProperty {
        if let enumValues = enumValues {
            return .enumeration(values: enumValues, description: description)
        }
        return .primitive(type: .string, description: description)
    }

    /// Create a number property
    public static func number(description: String? = nil) -> JSONSchemaProperty {
        .primitive(type: .number, description: description)
    }

    /// Create an integer property
    public static func integer(description: String? = nil) -> JSONSchemaProperty {
        .primitive(type: .integer, description: description)
    }

    /// Create a boolean property
    public static func boolean(description: String? = nil) -> JSONSchemaProperty {
        .primitive(type: .boolean, description: description)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case items
        case enumValues = "enum"
        case properties
        case required
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SchemaType.self, forKey: .type)
        let description = try container.decodeIfPresent(String.self, forKey: .description)

        if let enumValues = try container.decodeIfPresent([String].self, forKey: .enumValues) {
            self = .enumeration(values: enumValues, description: description)
        } else if type == .array, let items = try container.decodeIfPresent(JSONSchemaProperty.self, forKey: .items) {
            self = .array(items: items, description: description)
        } else if type == .object {
            let properties = try container.decodeIfPresent([String: JSONSchemaProperty].self, forKey: .properties) ?? [:]
            let required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
            self = .object(properties: properties, required: required, description: description)
        } else {
            self = .primitive(type: type, description: description)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)

        switch self {
        case .enumeration(let values, _):
            try container.encode(values, forKey: .enumValues)
        case .array(let items, _):
            try container.encode(items, forKey: .items)
        case .object(let properties, let required, _):
            try container.encode(properties, forKey: .properties)
            if !required.isEmpty {
                try container.encode(required, forKey: .required)
            }
        case .primitive:
            break
        }
    }
}

/// JSON Schema primitive types
public enum SchemaType: String, Sendable, Codable, Equatable {
    case object
    case array
    case string
    case number
    case integer
    case boolean
    case null
}
