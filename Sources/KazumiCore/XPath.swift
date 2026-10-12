// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

public enum XPathValue: Equatable {
    case element(HTMLElement)
    case attribute(name: String, value: String)
    case text(String)

    public var stringValue: String {
        switch self {
        case .element(let element):
            return element.textContent
        case .attribute(_, let value):
            return value
        case .text(let value):
            return value
        }
    }

    /// Link used by search/chapter rules: an `@href` node, or the href/src of an element.
    public var linkValue: String {
        switch self {
        case .attribute(_, let value):
            return value
        case .element(let element):
            return element.attribute("href") ?? element.attribute("src") ?? ""
        case .text:
            return ""
        }
    }

    public static func == (lhs: XPathValue, rhs: XPathValue) -> Bool {
        switch (lhs, rhs) {
        case (.element(let a), .element(let b)):
            return a === b
        case (.attribute(let an, let av), .attribute(let bn, let bv)):
            return an == bn && av == bv
        case (.text(let a), .text(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Kazumi's rule editor only promises selectors that start with `//`.
/// Supported steps: element names, `*`, `@attr`, `text()`,
/// `[@attr='value']`, `[contains(@attr,'value')]`, and `[n]`.
public enum XPath {
    public static func query(_ expression: String, from context: HTMLElement) throws -> [XPathValue] {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw KazumiError.message("XPath 不能为空")
        }
        let steps = try parse(trimmed)
        var current: [XPathValue] = [.element(context)]
        for step in steps {
            var next: [XPathValue] = []
            for node in current {
                guard case .element(let element) = node else { continue }
                next.append(contentsOf: evaluate(step, from: element))
            }
            current = next
        }
        return current
    }

    public static func first(_ expression: String, from context: HTMLElement) throws -> XPathValue? {
        try query(expression, from: context).first
    }

    private struct Step {
        enum Axis { case child, descendant }
        enum Test {
            case element(String)
            case attribute(String)
            case text
        }
        enum Predicate {
            case equals(attribute: String, value: String)
            case contains(attribute: String, value: String)
            case position(Int)
        }
        var axis: Axis
        var test: Test
        var predicates: [Predicate]
    }

    private static func evaluate(_ step: Step, from element: HTMLElement) -> [XPathValue] {
        switch step.test {
        case .attribute(let name):
            let hosts: [HTMLElement]
            switch step.axis {
            case .child:
                hosts = [element]
            case .descendant:
                hosts = [element] + element.descendantElements
            }
            return hosts.compactMap { host in
                guard let value = host.attribute(name) else { return nil }
                return .attribute(name: name, value: value)
            }
        case .text:
            let hosts = step.axis == .child ? [element] : [element] + element.descendantElements
            return hosts.compactMap { host in
                let text = host.directText
                return text.isEmpty ? nil : .text(text)
            }
        case .element(let name):
            let descendants = element.descendantElements
            // `//tag[n]` abbreviates descendant-or-self::node()/child::tag[n].
            // Evaluate the predicates per parent, then return document order.
            let parents = step.axis == .child ? [element] : [element] + descendants
            var results: [HTMLElement] = []
            for parent in parents {
                var matched = parent.childElements.filter { name == "*" || $0.name == name }
                for predicate in step.predicates {
                    switch predicate {
                    case .equals(let attribute, let value):
                        matched = matched.filter { $0.attribute(attribute) == value }
                    case .contains(let attribute, let value):
                        matched = matched.filter { $0.attribute(attribute)?.contains(value) == true }
                    case .position(let position):
                        let index = position - 1
                        matched = matched.indices.contains(index) ? [matched[index]] : []
                    }
                }
                results.append(contentsOf: matched)
            }
            let selected = Set(results.map { ObjectIdentifier($0) })
            let ordered = step.axis == .child ? element.childElements : descendants
            return ordered.filter { selected.contains(ObjectIdentifier($0)) }.map { .element($0) }
        }
    }

    private static func parse(_ expression: String) throws -> [Step] {
        var cursor = Cursor(expression)
        var steps: [Step] = []
        if cursor.starts(with: ".") { cursor.advance() }
        var first = true
        while !cursor.isAtEnd {
            let axis: Step.Axis
            if cursor.starts(with: "//") {
                axis = .descendant
                cursor.advance(2)
            } else if cursor.starts(with: "/") {
                axis = .child
                cursor.advance()
            } else if first {
                axis = .descendant
            } else {
                throw KazumiError.message("XPath 无效: \(expression)")
            }
            first = false
            if cursor.isAtEnd {
                throw KazumiError.message("XPath 无效: \(expression)")
            }
            let test: Step.Test
            if cursor.peek() == "@" {
                cursor.advance()
                test = .attribute(cursor.readName())
            } else if cursor.starts(with: "text()") {
                cursor.advance(6)
                test = .text
            } else if cursor.peek() == "*" {
                cursor.advance()
                test = .element("*")
            } else {
                let name = cursor.readName().lowercased()
                if name.isEmpty {
                    throw KazumiError.message("XPath 无效: \(expression)")
                }
                test = .element(name)
            }
            var predicates: [Step.Predicate] = []
            while cursor.peek() == "[" {
                predicates.append(try parsePredicate(&cursor, expression: expression))
            }
            steps.append(Step(axis: axis, test: test, predicates: predicates))
        }
        if steps.isEmpty {
            throw KazumiError.message("XPath 无效: \(expression)")
        }
        return steps
    }

    private static func parsePredicate(_ cursor: inout Cursor, expression: String) throws -> Step.Predicate {
        cursor.advance() // [
        let body = cursor.readPredicateBody()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let position = Int(trimmed), position > 0 {
            return .position(position)
        }
        if trimmed.hasPrefix("position()") {
            let rest = trimmed.dropFirst("position()".count).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("=") {
                let number = rest.dropFirst().trimmingCharacters(in: .whitespaces)
                if let position = Int(number), position > 0 {
                    return .position(position)
                }
            }
        }
        if trimmed.lowercased().hasPrefix("contains("), trimmed.hasSuffix(")") {
            let inner = trimmed.dropFirst("contains(".count).dropLast()
            let parts = splitArgs(String(inner))
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).hasPrefix("@") {
                let attribute = String(parts[0].trimmingCharacters(in: .whitespaces).dropFirst())
                let value = unquote(parts[1].trimmingCharacters(in: .whitespaces))
                return .contains(attribute: attribute, value: value)
            }
        }
        if let equal = trimmed.firstIndex(of: "=") {
            let left = trimmed[..<equal].trimmingCharacters(in: .whitespaces)
            let right = trimmed[trimmed.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            if left.hasPrefix("@") {
                return .equals(attribute: String(left.dropFirst()), value: unquote(String(right)))
            }
        }
        throw KazumiError.message("不支持的 XPath 条件 [\(trimmed)]（\(expression)）")
    }

    private static func splitArgs(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let activeQuote = quote, character == activeQuote {
                current.append(character)
                quote = nil
                continue
            }
            if quote != nil {
                current.append(character)
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                current.append(character)
                continue
            }
            if character == "," {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }

    private static func unquote(_ text: String) -> String {
        if text.count >= 2 {
            let first = text.first
            let last = text.last
            if (first == "'" && last == "'") || (first == "\"" && last == "\"") {
                return String(text.dropFirst().dropLast())
            }
        }
        return text
    }

    private struct Cursor {
        let text: String
        var index: String.Index

        init(_ text: String) {
            self.text = text
            self.index = text.startIndex
        }

        var isAtEnd: Bool { index >= text.endIndex }

        func peek() -> Character? {
            isAtEnd ? nil : text[index]
        }

        func starts(with prefix: String) -> Bool {
            text[index...].hasPrefix(prefix)
        }

        mutating func advance(_ count: Int = 1) {
            for _ in 0..<count where index < text.endIndex {
                index = text.index(after: index)
            }
        }

        mutating func readName() -> String {
            let start = index
            while index < text.endIndex {
                let character = text[index]
                if character.isLetter || character.isNumber || character == "_" || character == "-" || character == ":" {
                    index = text.index(after: index)
                } else {
                    break
                }
            }
            return String(text[start..<index])
        }

        mutating func readPredicateBody() -> String {
            var depth = 1
            var quote: Character?
            let start = index
            while index < text.endIndex {
                let character = text[index]
                if let activeQuote = quote {
                    if character == activeQuote { quote = nil }
                    index = text.index(after: index)
                    continue
                }
                if character == "'" || character == "\"" {
                    quote = character
                    index = text.index(after: index)
                    continue
                }
                if character == "[" { depth += 1 }
                if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        let body = String(text[start..<index])
                        index = text.index(after: index)
                        return body
                    }
                }
                index = text.index(after: index)
            }
            return String(text[start..<index])
        }
    }
}
