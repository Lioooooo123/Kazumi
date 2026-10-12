// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import CoreFoundation
import Foundation

/// JSON value used by rule templates and Bangumi payloads.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public static func parse(_ data: Data) throws -> JSONValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue(foundation: object)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        guard let data = text.data(using: .utf8) else {
            throw KazumiError.message("响应不是 UTF-8 文本")
        }
        return try parse(data)
    }

    public func data(pretty: Bool = false) throws -> Data {
        let object = foundationObject
        guard JSONSerialization.isValidJSONObject(object) || self == .null || string != nil || int != nil || double != nil || bool != nil else {
            throw KazumiError.message("无法编码 JSON")
        }
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        if case .array = self {
            return try JSONSerialization.data(withJSONObject: object, options: options)
        }
        if case .object = self {
            return try JSONSerialization.data(withJSONObject: object, options: options)
        }
        // Fragments (string/number/bool/null) are valid with .fragmentsAllowed on read,
        // but JSONSerialization cannot write them. Wrap is unnecessary for our callers.
        throw KazumiError.message("仅对象或数组可以编码为 JSON 文本")
    }

    public func text(pretty: Bool = false) throws -> String {
        let data = try data(pretty: pretty)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var int: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value) where value.rounded() == value && value <= Double(Int.max) && value >= Double(Int.min):
            return Int(value)
        default:
            return nil
        }
    }

    public var double: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        object?[key]
    }

    /// String used when a template variable is interpolated.
    public var templateString: String {
        switch self {
        case .null:
            return ""
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .double(let value):
            if value.rounded() == value { return String(Int(value)) }
            return String(value)
        case .string(let value):
            return value
        case .array, .object:
            return (try? text()) ?? ""
        }
    }

    /// Display string for scraped fields. Strings are trimmed; other scalars use `templateString`.
    public var fieldString: String {
        switch self {
        case .string(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .null:
            return ""
        default:
            return templateString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func looseString(_ key: String, default fallback: String = "") -> String {
        guard let value = self[key] else { return fallback }
        if case .null = value { return fallback }
        if let string = value.string { return string }
        return value.templateString
    }

    public func looseBool(_ key: String, default fallback: Bool = false) -> Bool {
        guard let value = self[key] else { return fallback }
        if let bool = value.bool { return bool }
        if let int = value.int { return int != 0 }
        if let string = value.string {
            switch string.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return fallback
            }
        }
        return fallback
    }

    public func looseInt(_ key: String, default fallback: Int = 0) -> Int {
        guard let value = self[key] else { return fallback }
        if let int = value.int { return int }
        if let double = value.double { return Int(double) }
        if let string = value.string, let int = Int(string) { return int }
        return fallback
    }

    public func object(_ key: String) -> [String: JSONValue] {
        self[key]?.object ?? [:]
    }

    init(foundation object: Any) {
        if object is NSNull {
            self = .null
            return
        }
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
                return
            }
            let double = number.doubleValue
            if double.rounded() == double, double <= Double(Int.max), double >= Double(Int.min), abs(double) < 9_007_199_254_740_992 {
                self = .int(number.intValue)
            } else {
                self = .double(double)
            }
            return
        }
        if let string = object as? String {
            self = .string(string)
            return
        }
        if let array = object as? [Any] {
            self = .array(array.map(JSONValue.init(foundation:)))
            return
        }
        if let dictionary = object as? [String: Any] {
            var object: [String: JSONValue] = [:]
            object.reserveCapacity(dictionary.count)
            for (key, value) in dictionary {
                object[key] = JSONValue(foundation: value)
            }
            self = .object(object)
            return
        }
        self = .string(String(describing: object))
    }

    private struct CodingKeyBox: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }
        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
        init(_ string: String) {
            stringValue = string
            intValue = nil
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeyBox.self) {
            var object: [String: JSONValue] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [JSONValue] = []
            while !unkeyed.isAtEnd {
                array.append(try unkeyed.decode(JSONValue.self))
            }
            self = .array(array)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int.self) {
            self = .int(value)
        } else if let value = try? single.decode(Double.self) {
            self = .double(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: single, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            var keyed = encoder.container(keyedBy: CodingKeyBox.self)
            for (key, value) in object {
                try keyed.encode(value, forKey: CodingKeyBox(key))
            }
        case .array(let array):
            var unkeyed = encoder.unkeyedContainer()
            for value in array {
                try unkeyed.encode(value)
            }
        case .null:
            var single = encoder.singleValueContainer()
            try single.encodeNil()
        case .bool(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        case .int(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        case .double(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        case .string(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        }
    }
}

extension JSONValue {
    var foundationObject: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.foundationObject)
        case .object(let values):
            var object: [String: Any] = [:]
            for (key, value) in values {
                object[key] = value.foundationObject
            }
            return object
        }
    }
}
