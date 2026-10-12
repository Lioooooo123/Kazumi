// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// Resolves the same anonymous playback request as Xifan's web player, without
/// depending on JavaScript execution in a detached, hidden WKWebView.
public struct XifanPlaybackService: Sendable {
    public var http: HTTPClient
    public init(http: HTTPClient = HTTPClient()) { self.http = http }

    public func resolve(page: URL, html: String, rule: PluginRule, userAgent: String) async throws -> URL? {
        guard page.scheme == "https", page.host?.lowercased() == "next.xifanacg.com",
              let configuredAPI = URL(string: rule.chapterAPI.request.url),
              configuredAPI.scheme == "https", configuredAPI.host?.lowercased() == "api.xifanacg.com" else { return nil }
        let path = page.path.split(separator: "/")
        guard path.count == 4, path[0] == "anime", path[2] == "play",
              let anime = Int(path[1]), anime > 0, let episode = Int(path[3]), episode > 0 else { return nil }
        guard let source = Self.sourceID(in: html, anime: anime, episode: episode) else {
            throw KazumiError.message("无法读取稀饭片源的当前集数和播放线路")
        }
        // Use the public request configuration already declared by this rule.
        // Never copy a browser account token or persist a signed media URL.
        var headers = rule.chapterAPI.request.headers.mapValues(\.templateString)
        guard headers.contains(where: { $0.key.lowercased() == "apikey" && !$0.value.isEmpty }) else {
            throw KazumiError.message("稀饭规则缺少播放请求配置，请更新规则")
        }
        headers["User-Agent"] = userAgent.isEmpty ? KazumiCore.defaultBrowserUserAgent : userAgent
        headers["Referer"] = page.absoluteString
        headers["Origin"] = "https://next.xifanacg.com"
        let response = try await http.post(
            "https://api.xifanacg.com/functions/v1/issue-web-playback",
            json: .object(["action": .string("fallback"), "episode_id": .int(episode), "source_id": .int(source)]),
            headers: headers)
        guard let body = response.json, body["ok"]?.bool == true else {
            let message: String
            switch response.json?["error"]?.string {
            case "unauthorized", "unauthenticated": message = "这个稀饭片源需要登录后观看"
            case "forbidden": message = "这个稀饭片源暂不允许当前用户观看"
            case "rate_limited": message = "稀饭片源请求过于频繁，请稍后重试"
            case "not_found": message = "稀饭片源没有提供这一集的播放地址"
            default: message = "稀饭播放服务暂时不可用，请稍后重试"
            }
            throw KazumiError.message(message)
        }
        guard body["episode_id"]?.int == episode, body["anime_id"]?.int == anime,
              let candidate = body["candidates"]?.array?.first(where: { $0["source_id"]?.int == source }),
              let raw = candidate["url"]?.string, LegacySniff.accepts(raw), let url = URL(string: raw) else {
            throw KazumiError.message("稀饭片源未返回当前集数和线路的有效视频地址")
        }
        return url
    }

    private static func sourceID(in html: String, anime: Int, episode: Int) -> Int? {
        // Decode the Flight push's JSON string first. The inner stream contains
        // separate, labelled JSON records, not one JSON document or plain HTML.
        let pattern = #"self\.__next_f\.push\((\[(?:[^"\]]|"(?:\\.|[^"\\])*")*\])\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let push = try? JSONValue.parse(String(html[range])), let values = push.array, values.count > 1,
                  let payload = values[1].string else { continue }
            for record in payload.split(separator: "\n") {
                guard let colon = record.firstIndex(of: ":"),
                      let json = try? JSONValue.parse(String(record[record.index(after: colon)...])) else { continue }
                if let source = sourceID(in: json, anime: anime, episode: episode, depth: 0) { return source }
            }
        }
        return nil
    }

    private static func sourceID(in value: JSONValue, anime: Int, episode: Int, depth: Int) -> Int? {
        guard depth < 64 else { return nil }
        if value["animeId"]?.int == anime, value["episodeId"]?.int == episode,
           let source = value["initialSourceId"]?.int, source > 0 { return source }
        let children = value.array ?? value.object.map { Array($0.values) } ?? []
        for child in children {
            if let source = sourceID(in: child, anime: anime, episode: episode, depth: depth + 1) { return source }
        }
        return nil
    }
}
