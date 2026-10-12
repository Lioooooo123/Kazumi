// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// Finds direct media URLs in an episode page.
///
/// The Flutter app resolves many sources inside a WebView (including legacy
/// iframe listening). This sniffer covers the direct-file and HLS cases so
/// AVPlayer can start without that WebView. Pages that hide the address in
/// obfuscated script still need the WebView port.
public enum MediaSniffer {
    public static let mediaExtensions: Set<String> = ["m3u8", "mp4", "m4v", "webm", "mkv", "flv", "mov", "m4s"]

    public static func isDirect(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if let ext = path.split(separator: ".").last, mediaExtensions.contains(String(ext)) {
            return true
        }
        let absolute = url.absoluteString.lowercased()
        return absolute.contains(".m3u8") || absolute.contains("m3u8?")
    }

    public static func mediaURLs(in text: String, baseURL: URL?) -> [URL] {
        var normalized = text
        while let range = normalized.range(of: "\\/") {
            normalized.replaceSubrange(range, with: "/")
        }
        guard let regex = try? NSRegularExpression(pattern: #"https?:\/\/[^\s"'<>\\]+"#, options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        var results: [URL] = []
        var seen = Set<String>()
        for match in regex.matches(in: normalized, range: range) {
            guard let slice = Range(match.range, in: normalized) else { continue }
            var raw = String(normalized[slice])
            while let last = raw.last, ".,);]'\"".contains(last) {
                raw.removeLast()
            }
            guard let url = URL(string: raw), isDirect(url) else { continue }
            if seen.insert(url.absoluteString).inserted {
                results.append(url)
            }
        }
        if let baseURL, isDirect(baseURL), seen.insert(baseURL.absoluteString).inserted {
            results.insert(baseURL, at: 0)
        }
        return results
    }
}
