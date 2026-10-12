// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// Port of `lib/utils/episode_url.dart`.
///
/// Relative hrefs are resolved against the rule base URL. Same-host http(s)
/// links adopt the base scheme. Trailing slashes (except `/`) and empty
/// queries are removed. The result is stable and safe to use as a history key.
public func normalizeEpisodeURL(baseURL: String, raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }

    let baseTrimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = URL(string: baseTrimmed)
    let hasValidBase = base?.scheme?.isEmpty == false && !(base?.host ?? "").isEmpty

    let resolved: URL?
    if let absolute = URL(string: trimmed),
       let scheme = absolute.scheme, !scheme.isEmpty,
       let host = absolute.host, !host.isEmpty {
        resolved = absolute
    } else if hasValidBase, let base {
        resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL
    } else {
        resolved = nil
    }

    guard let resolved, let host = resolved.host, !host.isEmpty else {
        return trimmed
    }

    var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true) ?? URLComponents()
    if let base, hasValidBase,
       isHTTP(base.scheme), isHTTP(resolved.scheme),
       resolved.scheme != base.scheme,
       resolved.host == base.host,
       sameExplicitPort(resolved, base) {
        components.scheme = base.scheme
    }

    var path = components.percentEncodedPath
    if path.isEmpty { path = components.path }
    while path.count > 1 && path.hasSuffix("/") {
        path.removeLast()
    }
    components.percentEncodedPath = path.isEmpty ? "/" : path

    if components.percentEncodedQuery?.isEmpty != false {
        components.percentEncodedQuery = nil
    }
    if components.fragment?.isEmpty != false {
        components.fragment = nil
    }
    return components.string ?? trimmed
}

private func isHTTP(_ scheme: String?) -> Bool {
    scheme == "http" || scheme == "https"
}

private func sameExplicitPort(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.port == rhs.port
}
