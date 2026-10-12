// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// The restricted JSONPath subset Kazumi API rules are allowed to use:
/// `$`, `.name`, `[index]`, `[*]`, and quoted keys. No filters or scripts.
public enum JSONPath {
    public static func validate(_ expression: String) throws {
        _ = try parse(expression)
    }

    public static func read(_ document: JSONValue, _ expression: String) throws -> [JSONValue] {
        let tokens = try parse(expression)
        var current: [JSONValue] = [document]
        for token in tokens {
            var next: [JSONValue] = []
            for value in current {
                next.append(contentsOf: apply(token, to: value))
            }
            current = next
        }
        return current
    }

    public static func readFirst(_ document: JSONValue, _ expression: String) throws -> JSONValue? {
        try read(document, expression).first
    }

    private enum Token {
        case key(String)
        case index(Int)
        case wildcard
    }

    private static func apply(_ token: Token, to value: JSONValue) -> [JSONValue] {
        switch token {
        case .key(let key):
            guard let child = value[key] else { return [] }
            return [child]
        case .index(let index):
            guard let array = value.array, index >= 0, index < array.count else { return [] }
            return [array[index]]
        case .wildcard:
            return value.array ?? []
        }
    }

    private static func parse(_ expression: String) throws -> [Token] {
        if expression.isEmpty || !expression.hasPrefix("$") {
            throw KazumiError.message("JSONPath 必须以 $ 开头: \(expression)")
        }
        var tokens: [Token] = []
        var index = expression.index(after: expression.startIndex)
        while index < expression.endIndex {
            let character = expression[index]
            if character == "." {
                index = expression.index(after: index)
                let start = index
                while index < expression.endIndex {
                    let scalar = expression[index]
                    if scalar.isLetter || scalar.isNumber || scalar == "_" || scalar == "$" || scalar == "-" {
                        index = expression.index(after: index)
                    } else {
                        break
                    }
                }
                if index == start {
                    throw KazumiError.message("不支持的 JSONPath: \(expression)")
                }
                tokens.append(.key(String(expression[start..<index])))
                continue
            }
            if character == "[" {
                guard let end = bracketEnd(expression, from: index) else {
                    throw KazumiError.message("JSONPath 缺少 ]: \(expression)")
                }
                let content = expression[expression.index(after: index)..<end]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if content == "*" {
                    tokens.append(.wildcard)
                } else if let number = Int(content), number >= 0 {
                    tokens.append(.index(number))
                } else if content.count >= 2,
                          (content.hasPrefix("'") && content.hasSuffix("'")) ||
                          (content.hasPrefix("\"") && content.hasSuffix("\"")) {
                    let inner = content.dropFirst().dropLast().replacingOccurrences(of: "\\'", with: "'")
                        .replacingOccurrences(of: "\\\"", with: "\"")
                    tokens.append(.key(String(inner)))
                } else {
                    throw KazumiError.message("不支持的 JSONPath 片段: [\(content)]")
                }
                index = expression.index(after: end)
                continue
            }
            throw KazumiError.message("不支持的 JSONPath: \(expression)")
        }
        return tokens
    }

    private static func bracketEnd(_ expression: String, from start: String.Index) -> String.Index? {
        var quote: Character?
        var escaped = false
        var index = expression.index(after: start)
        while index < expression.endIndex {
            let character = expression[index]
            if escaped {
                escaped = false
                index = expression.index(after: index)
                continue
            }
            if character == "\\" {
                escaped = true
                index = expression.index(after: index)
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                index = expression.index(after: index)
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                index = expression.index(after: index)
                continue
            }
            if character == "]" { return index }
            index = expression.index(after: index)
        }
        return nil
    }
}
