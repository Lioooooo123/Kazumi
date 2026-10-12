// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Decodes rule pages that are not UTF-8. GBK / GB18030 / Big5 go through iconv.
public enum TextCharsets {
    public static func isUTF8(_ charset: String) -> Bool {
        let name = canonical(charset)
        return name == "UTF-8" || name == "UTF8" || name == "UNICODE-1-1-UTF-8"
    }

    public static func canonical(_ charset: String) -> String {
        charset.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .uppercased()
    }

    /// Reads `charset=` from a Content-Type header or an HTML meta tag.
    public static func charset(contentType: String?, bodyPrefix: Data?) -> String? {
        if let contentType, let found = charsetToken(in: contentType) { return found }
        guard let bodyPrefix, !bodyPrefix.isEmpty else { return nil }
        let prefix = String(decoding: bodyPrefix.prefix(4096), as: UTF8.self)
        return charsetToken(in: prefix)
    }

    public static func decode(_ data: Data, charset: String) -> String? {
        if data.isEmpty { return "" }
        if isUTF8(charset) { return String(data: data, encoding: .utf8) }
        return convert(data, from: iconvName(charset))
    }

    private static func charsetToken(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"charset\s*=\s*["']?([A-Za-z0-9._\-]+)"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let slice = Range(match.range(at: 1), in: text) else { return nil }
        let token = String(text[slice])
        return token.isEmpty ? nil : token
    }

    private static func iconvName(_ charset: String) -> String {
        switch canonical(charset) {
        case "GBK", "CP936", "MS936": return "GBK"
        case "GB2312", "GB-2312": return "GB2312"
        case "GB18030": return "GB18030"
        case "BIG5", "BIG-5", "CP950": return "BIG5"
        default: return charset
        }
    }

    private static func convert(_ data: Data, from encoding: String) -> String? {
        let source = encoding.cString(using: .utf8)
        let target = "UTF-8".cString(using: .utf8)
        guard let source, let target else { return nil }
        let converter = iconv_open(target, source)
        if converter == iconv_t(bitPattern: -1) { return nil }
        defer { iconv_close(converter) }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return "" }
            var input: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(mutating: base.assumingMemoryBound(to: CChar.self))
            var inputLeft = raw.count
            let capacity = raw.count * 4 + 32
            let output = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
            defer { output.deallocate() }
            var outputCursor: UnsafeMutablePointer<CChar>? = output
            var outputLeft = capacity
            let converted = iconv(converter, &input, &inputLeft, &outputCursor, &outputLeft)
            if converted == -1 { return nil }
            let used = capacity - outputLeft
            let bytes = Data(bytes: output, count: used)
            return String(data: bytes, encoding: .utf8)
        }
    }
}
