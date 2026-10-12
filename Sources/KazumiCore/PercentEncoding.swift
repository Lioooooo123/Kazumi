// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

enum PercentEncoding {
    /// Dart `Uri.encodeComponent`: unreserved plus `! * ' ( )`, space as `%20`.
    static func encodeComponent(_ value: String) -> String {
        encode(value, spaceAsPlus: false)
    }

    /// Dart `Uri.encodeQueryComponent`: same set, space as `+`.
    static func encodeQueryComponent(_ value: String) -> String {
        encode(value, spaceAsPlus: true)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&" {
                if let end = text[index...].firstIndex(of: ";"), text.distance(from: index, to: end) <= 12 {
                    let token = String(text[text.index(after: index)..<end])
                    if let decoded = entity(token) {
                        result.append(decoded)
                        index = text.index(after: end)
                        continue
                    }
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func encode(_ value: String, spaceAsPlus: Bool) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return spaceAsPlus ? encoded.replacingOccurrences(of: "%20", with: "+") : encoded
    }

    private static func entity(_ token: String) -> String? {
        switch token {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        default:
            if token.hasPrefix("#x") || token.hasPrefix("#X") {
                let hex = token.dropFirst(2)
                guard let scalar = UInt32(hex, radix: 16), let unicode = UnicodeScalar(scalar) else { return nil }
                return String(unicode)
            }
            if token.hasPrefix("#") {
                let digits = token.dropFirst()
                guard let scalar = UInt32(digits), let unicode = UnicodeScalar(scalar) else { return nil }
                return String(unicode)
            }
            return nil
        }
    }
}
