// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

public struct PluginImportResult: Equatable, Sendable {
    public var plugins: [PluginRule]
    public var failures: [String]
    public var duplicateCount: Int

    public var failureCount: Int { failures.count }
}

/// Imports Kazumi rule JSON and `kazumi://` share links.
public enum PluginImporter {
    public static func parse(_ input: String) -> PluginImportResult {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return PluginImportResult(plugins: [], failures: ["导入内容为空"], duplicateCount: 0)
        }
        var parsed: [PluginRule] = []
        var failures: [String] = []
        if let json = try? JSONValue.parse(value) {
            if let array = json.array {
                for (index, entry) in array.enumerated() {
                    parseEntry(entry, index: index + 1, into: &parsed, failures: &failures)
                }
            } else {
                parseEntry(json, index: 1, into: &parsed, failures: &failures)
            }
        } else {
            let segments = findLinks(value)
            if segments.isEmpty {
                failures.append("未找到有效的 JSON 或 kazumi:// 规则链接")
            } else {
                for (index, segment) in segments.enumerated() {
                    do {
                        let entry = try decodeLink(scheme: segment.scheme, payload: segment.payload)
                        parseEntry(entry, index: index + 1, into: &parsed, failures: &failures)
                    } catch {
                        failures.append("第 \(index + 1) 条：\(error)")
                    }
                }
            }
        }
        var unique: [String: PluginRule] = [:]
        var duplicates = 0
        for plugin in parsed {
            let key = plugin.name.lowercased()
            if unique[key] != nil { duplicates += 1 }
            unique[key] = plugin
        }
        return PluginImportResult(
            plugins: Array(unique.values),
            failures: failures,
            duplicateCount: duplicates
        )
    }

    public static func exportLink(_ rule: PluginRule) throws -> String {
        let data = try rule.jsonObject().data()
        let encoded = data.base64EncodedString()
        return "kazumi://\(encoded)"
    }

    public static func exportJSON(_ rules: [PluginRule], pretty: Bool = true) throws -> String {
        let array = JSONValue.array(rules.map { $0.jsonObject() })
        return try array.text(pretty: pretty)
    }

    private static func parseEntry(
        _ entry: JSONValue,
        index: Int,
        into plugins: inout [PluginRule],
        failures: inout [String]
    ) {
        do {
            let object: JSONValue
            if entry.object != nil {
                object = entry
            } else if let string = entry.string {
                object = try JSONValue.parse(kazumiBase64ToJSON(string))
            } else {
                throw KazumiError.message("规则必须是 JSON object 或 kazumi:// 链接")
            }
            let plugin = PluginRule(json: object)
            if plugin.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw KazumiError.message("规则名称不能为空")
            }
            if plugin.requiresNewerClient {
                throw KazumiError.message("规则需要更高版本客户端")
            }
            plugins.append(plugin)
        } catch {
            failures.append("第 \(index) 条：\(error)")
        }
    }

    private struct LinkSegment {
        var scheme: String
        var payload: String
    }

    private static func findLinks(_ input: String) -> [LinkSegment] {
        let pattern = "kazumi:(?://)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        return matches.enumerated().map { index, match in
            let schemeRange = Range(match.range, in: input)!
            let end = index + 1 < matches.count
                ? input.index(input.startIndex, offsetBy: matches[index + 1].range.location)
                : input.endIndex
            return LinkSegment(scheme: String(input[schemeRange]), payload: String(input[schemeRange.upperBound..<end]))
        }
    }

    private static func decodeLink(scheme: String, payload raw: String) throws -> JSONValue {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
            .union(.whitespacesAndNewlines)
        let prefix = raw.unicodeScalars.prefix { allowed.contains($0) }
        var candidates = [String(prefix)]
        let whitespace = CharacterSet.whitespacesAndNewlines
        var trimmed = String(prefix)
        while let range = trimmed.rangeOfCharacter(from: whitespace, options: .backwards) {
            trimmed = String(trimmed[..<range.lowerBound])
            if !trimmed.isEmpty { candidates.append(trimmed) }
            else { break }
            if trimmed.unicodeScalars.allSatisfy({ !whitespace.contains($0) }) { break }
        }
        var firstError: Error?
        for candidate in candidates {
            do {
                let decoded = try JSONValue.parse(kazumiBase64ToJSON(scheme + candidate.trimmingCharacters(in: .whitespacesAndNewlines)))
                if decoded.object != nil { return decoded }
                firstError = firstError ?? KazumiError.message("规则链接内容必须是 JSON object")
            } catch {
                firstError = firstError ?? error
            }
        }
        throw firstError ?? KazumiError.message("Invalid Kazumi rule link")
    }

    private static func kazumiBase64ToJSON(_ text: String) throws -> String {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^kazumi:(?://)?"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..<input.endIndex, in: input)),
              let range = Range(match.range, in: input) else {
            throw KazumiError.message("Invalid Kazumi rule link")
        }
        var payload = String(input[range.upperBound...])
        payload = payload.removingPercentEncoding ?? payload
        payload = payload.unicodeScalars.filter { !$0.properties.isWhitespace }.map(String.init).joined()
        if payload.isEmpty { throw KazumiError.message("Kazumi rule link is empty") }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64), let json = String(data: data, encoding: .utf8) else {
            throw KazumiError.message("Invalid Kazumi rule link payload")
        }
        return json
    }
}
