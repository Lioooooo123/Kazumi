// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// Finds direct media URLs in an episode page.
///
/// The Flutter app resolves many sources inside a WebView (including legacy
/// iframe listening). This sniffer covers the direct-file and HLS cases so
/// AVPlayer can start without that WebView. Pages that hide the address in
/// obfuscated script still need the WebView port.
public enum MediaSniffer {
    public static let mediaExtensions: Set<String> = ["m3u8", "mp4", "m4v", "webm", "mkv", "flv", "mov"]

    public static func isDirect(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        // A player page can carry a playlist in its query. Only its own path
        // identifies a direct resource; segments are not standalone videos.
        return mediaExtensions.contains(url.pathExtension.lowercased())
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
        func add(_ url: URL, depth: Int = 0) {
            if isDirect(url) {
                if LegacySniff.accepts(url.absoluteString), seen.insert(url.absoluteString).inserted {
                    results.append(url)
                }
            } else if depth < 3, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                for item in components.queryItems ?? [] {
                    if let value = item.value, let nested = URL(string: value) { add(nested, depth: depth + 1) }
                }
            }
        }
        for match in regex.matches(in: normalized, range: range) {
            guard let slice = Range(match.range, in: normalized) else { continue }
            var raw = String(normalized[slice])
            while let last = raw.last, ".,);]'\"".contains(last) {
                raw.removeLast()
            }
            guard let url = URL(string: raw.replacingOccurrences(of: "&amp;", with: "&")) else { continue }
            add(url)
        }
        if let baseURL, LegacySniff.accepts(baseURL.absoluteString), seen.insert(baseURL.absoluteString).inserted {
            results.insert(baseURL, at: 0)
        }
        return results
    }
}
