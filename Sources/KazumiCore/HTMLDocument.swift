// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// Element in a small HTML DOM. Good enough for Kazumi's `//` selectors.
/// This is not a full HTML5 parser: it keeps nesting, attributes, and text,
/// and it auto-closes a few list/paragraph tags the way browsers do.
public final class HTMLElement {
    public let name: String
    public let attributes: [String: String]
    public fileprivate(set) var children: [HTMLNode] = []
    public weak var parent: HTMLElement?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    public var childElements: [HTMLElement] {
        children.compactMap(\.element)
    }

    /// Depth-first descendants, not including this element.
    public var descendantElements: [HTMLElement] {
        var result: [HTMLElement] = []
        func walk(_ node: HTMLElement) {
            for child in node.childElements {
                result.append(child)
                walk(child)
            }
        }
        walk(self)
        return result
    }

    public var directText: String {
        children.compactMap(\.text).joined()
    }

    public var textContent: String {
        var parts: [String] = []
        func walk(_ node: HTMLElement) {
            for child in node.children {
                switch child {
                case .text(let value):
                    parts.append(value)
                case .element(let element):
                    walk(element)
                }
            }
        }
        walk(self)
        return parts.joined()
    }

    func attribute(_ name: String) -> String? {
        if let exact = attributes[name] { return exact }
        let lowered = name.lowercased()
        return attributes.first { $0.key.lowercased() == lowered }?.value
    }
}

public enum HTMLNode {
    case element(HTMLElement)
    case text(String)

    var element: HTMLElement? {
        if case .element(let element) = self { return element }
        return nil
    }

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

public enum HTMLParser {
    public static func parse(_ source: String) -> HTMLElement {
        let root = HTMLElement(name: "#document", attributes: [:])
        var stack: [HTMLElement] = [root]
        var index = source.startIndex

        func current() -> HTMLElement { stack.last ?? root }

        func appendText(_ raw: String) {
            let decoded = PercentEncoding.decodeEntities(raw)
            guard !decoded.isEmpty else { return }
            current().children.append(.text(decoded))
        }

        while index < source.endIndex {
            guard source[index] == "<" else {
                let start = index
                while index < source.endIndex, source[index] != "<" {
                    index = source.index(after: index)
                }
                appendText(String(source[start..<index]))
                continue
            }

            if source[index...].hasPrefix("<!--") {
                index = source.index(index, offsetBy: 4)
                if let range = source.range(of: "-->", range: index..<source.endIndex) {
                    index = range.upperBound
                } else {
                    index = source.endIndex
                }
                continue
            }

            if source[index...].hasPrefix("<!") || source[index...].hasPrefix("<?") {
                index = source.index(after: index)
                while index < source.endIndex, source[index] != ">" {
                    index = source.index(after: index)
                }
                if index < source.endIndex { index = source.index(after: index) }
                continue
            }

            let isClose = source[index...].hasPrefix("</")
            index = source.index(index, offsetBy: isClose ? 2 : 1)
            let nameStart = index
            while index < source.endIndex {
                let character = source[index]
                if character.isWhitespace || character == ">" || character == "/" { break }
                index = source.index(after: index)
            }
            let name = String(source[nameStart..<index]).lowercased()
            if name.isEmpty {
                continue
            }

            if isClose {
                if let match = stack.lastIndex(where: { $0.name == name }) {
                    stack.removeSubrange((match + 1)..<stack.endIndex)
                    if stack.count > 1 { stack.removeLast() }
                }
                while index < source.endIndex, source[index] != ">" {
                    index = source.index(after: index)
                }
                if index < source.endIndex { index = source.index(after: index) }
                continue
            }

            var attributes: [String: String] = [:]
            var selfClosing = false
            while index < source.endIndex {
                while index < source.endIndex, source[index].isWhitespace {
                    index = source.index(after: index)
                }
                if index >= source.endIndex { break }
                if source[index] == ">" {
                    index = source.index(after: index)
                    break
                }
                if source[index] == "/" {
                    selfClosing = true
                    index = source.index(after: index)
                    continue
                }
                let attrStart = index
                while index < source.endIndex {
                    let character = source[index]
                    if character.isWhitespace || character == "=" || character == ">" || character == "/" { break }
                    index = source.index(after: index)
                }
                let attrName = String(source[attrStart..<index]).lowercased()
                while index < source.endIndex, source[index].isWhitespace {
                    index = source.index(after: index)
                }
                var attrValue = ""
                if index < source.endIndex, source[index] == "=" {
                    index = source.index(after: index)
                    while index < source.endIndex, source[index].isWhitespace {
                        index = source.index(after: index)
                    }
                    if index < source.endIndex, source[index] == "\"" || source[index] == "'" {
                        let quote = source[index]
                        index = source.index(after: index)
                        let valueStart = index
                        while index < source.endIndex, source[index] != quote {
                            index = source.index(after: index)
                        }
                        attrValue = String(source[valueStart..<index])
                        if index < source.endIndex { index = source.index(after: index) }
                    } else {
                        let valueStart = index
                        while index < source.endIndex {
                            let character = source[index]
                            if character.isWhitespace || character == ">" { break }
                            index = source.index(after: index)
                        }
                        attrValue = String(source[valueStart..<index])
                    }
                }
                if !attrName.isEmpty {
                    attributes[attrName] = PercentEncoding.decodeEntities(attrValue)
                }
            }

            closeImplied(name, stack: &stack)
            let element = HTMLElement(name: name, attributes: attributes)
            element.parent = current()
            current().children.append(.element(element))

            let rawText = name == "script" || name == "style"
            if !selfClosing && !voidElements.contains(name) {
                stack.append(element)
                if rawText {
                    let closing = "</\(name)"
                    if let range = source.range(of: closing, options: .caseInsensitive, range: index..<source.endIndex) {
                        let raw = String(source[index..<range.lowerBound])
                        if !raw.isEmpty {
                            element.children.append(.text(raw))
                        }
                        index = range.lowerBound
                    } else {
                        let raw = String(source[index..<source.endIndex])
                        if !raw.isEmpty { element.children.append(.text(raw)) }
                        index = source.endIndex
                    }
                }
            }
        }
        return root
    }

    private static func closeImplied(_ name: String, stack: inout [HTMLElement]) {
        let closers: Set<String> = ["li", "p", "dt", "dd", "tr", "option"]
        if closers.contains(name), stack.contains(where: { $0.name == name }) {
            while let last = stack.last, last.name != "#document" {
                stack.removeLast()
                if last.name == name { break }
            }
        }
        if name == "td" || name == "th" {
            while let last = stack.last, last.name == "td" || last.name == "th" {
                stack.removeLast()
            }
        }
    }

    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]
}
