// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

public struct DanmakuComment: Equatable, Sendable, Identifiable, Hashable {
    public var id: Int
    public var time: Double
    public var mode: Int
    public var colorRGB: Int
    public var message: String
    public var source: String

    public init(id: Int = 0, time: Double, mode: Int, colorRGB: Int, message: String, source: String) {
        self.id = id
        self.time = time
        self.mode = mode
        self.colorRGB = colorRGB
        self.message = message
        self.source = source
    }

    /// DanDanPlay comment: `m` is the text, `p` is `time,mode,color,source`.
    public init?(json: JSONValue, id: Int) {
        guard let message = json["m"]?.string else { return nil }
        let parts = (json["p"]?.string ?? "").split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, let time = Double(parts[0]), let mode = Int(parts[1]), let color = Int(parts[2]) else {
            return nil
        }
        self.init(id: id, time: time, mode: mode, colorRGB: color, message: message, source: parts[3])
    }

    public var isScroll: Bool { mode != 4 && mode != 5 }
    public var isTop: Bool { mode == 5 }
    public var isBottom: Bool { mode == 4 }
}

public struct DanmakuAnime: Equatable, Sendable, Identifiable, Hashable {
    public var id: Int
    public var title: String
    public var typeDescription: String

    public init(id: Int, title: String, typeDescription: String = "") {
        self.id = id
        self.title = title
        self.typeDescription = typeDescription
    }
}

public struct DanmakuEpisode: Equatable, Sendable, Identifiable, Hashable {
    public var id: Int
    public var title: String

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

public enum DanmakuMatching {
    public static func bestAnime(title: String, candidates: [DanmakuAnime]) -> DanmakuAnime? {
        let needle = normalize(title)
        if needle.isEmpty { return candidates.first }
        if let exact = candidates.first(where: { normalize($0.title) == needle }) { return exact }
        if let contains = candidates.first(where: {
            let hay = normalize($0.title)
            return hay.contains(needle) || needle.contains(hay)
        }) { return contains }
        return candidates.first
    }

    public static func episodeNumber(from label: String) -> Int? {
        if let match = label.range(of: #"第\s*(\d+)\s*[话話集]"#, options: .regularExpression) {
            let slice = label[match]
            let digits = slice.filter(\.isNumber)
            return Int(digits)
        }
        if let match = label.range(of: #"(?i)(?:ep|episode)\s*(\d+)"#, options: .regularExpression) {
            let digits = label[match].filter(\.isNumber)
            return Int(digits)
        }
        let digits = label.filter(\.isNumber)
        if digits.count > 0, digits.count <= 4, let value = Int(digits) { return value }
        return nil
    }

    public static func bestEpisode(number: Int?, episodes: [DanmakuEpisode]) -> DanmakuEpisode? {
        guard !episodes.isEmpty else { return nil }
        if let number {
            if let titled = episodes.first(where: { episodeNumber(from: $0.title) == number }) {
                return titled
            }
            let index = number - 1
            if index >= 0, index < episodes.count { return episodes[index] }
        }
        return episodes.first
    }

    /// Collapses identical messages into `text xN` top comments, matching Kazumi's merger.
    public static func mergeDuplicates(_ comments: [DanmakuComment]) -> [DanmakuComment] {
        var groups: [String: [DanmakuComment]] = [:]
        var order: [String] = []
        for comment in comments {
            let key = normalize(comment.message)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(comment)
        }
        var result: [DanmakuComment] = []
        for key in order {
            let group = groups[key] ?? []
            guard let first = group.first else { continue }
            if group.count == 1 {
                result.append(first)
            } else {
                result.append(DanmakuComment(
                    id: first.id,
                    time: first.time,
                    mode: 5,
                    colorRGB: 0xFFFFFF,
                    message: "\(first.message) x\(group.count)",
                    source: first.source
                ))
            }
        }
        return result.sorted { $0.time < $1.time }
    }

    public static func blocked(_ comment: DanmakuComment, shield: [String]) -> Bool {
        let text = comment.message.lowercased()
        return shield.contains { keyword in
            let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !needle.isEmpty && text.contains(needle)
        }
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace }
    }
}

public enum DandanSignature {
    /// `base64(sha256(appId + timestamp + path + secret))`, same as the Flutter client.
    public static func sign(appID: String, secret: String, path: String, timestamp: Int) -> String {
        let material = appID + String(timestamp) + path + secret
        return SHA256.hash(material).base64EncodedString()
    }
}

public struct DanmakuClient: Sendable {
    public var http: HTTPClient
    public var appID: String
    public var appSecret: String

    public init(http: HTTPClient = HTTPClient(), appID: String, appSecret: String) {
        self.http = http
        self.appID = appID
        self.appSecret = appSecret
    }

    public func searchAnime(title: String) async throws -> [DanmakuAnime] {
        let encoded = PercentEncoding.encodeQueryComponent(title)
        let path = "/api/v2/search/episodes"
        let url = "\(KazumiCore.dandanAPI)\(path)?anime=\(encoded)&v2=true"
        let json = try await get(url, path: path)
        return (json["animes"]?.array ?? []).compactMap { item in
            let id = item.looseInt("animeId")
            guard id != 0 else { return nil }
            return DanmakuAnime(id: id, title: item.looseString("animeTitle"), typeDescription: item.looseString("typeDescription"))
        }
    }

    public func episodes(bangumiID: Int) async throws -> (bangumiID: Int, episodes: [DanmakuEpisode]) {
        let path = "/api/v2/bangumi/\(bangumiID)"
        let json = try await get(KazumiCore.dandanAPI + path, path: path)
        let bangumi = json["bangumi"]
        let episodes = (bangumi?["episodes"]?.array ?? []).compactMap { item -> DanmakuEpisode? in
            let id = item.looseInt("episodeId")
            guard id != 0 else { return nil }
            return DanmakuEpisode(id: id, title: item.looseString("episodeTitle"))
        }
        return (bangumi?.looseInt("animeId") ?? bangumiID, episodes)
    }

    public func comments(episodeID: Int) async throws -> [DanmakuComment] {
        let path = "/api/v2/comment/\(episodeID)"
        let url = KazumiCore.dandanAPI + path + "?withRelated=true&chConvert=0"
        let json = try await get(url, path: path)
        return (json["comments"]?.array ?? []).enumerated().compactMap { index, item in
            DanmakuComment(json: item, id: index)
        }
    }

    /// Undocumented DanDan episode id: `bangumiID` + 4-digit episode number.
    public func comments(bangumiID: Int, episodeNumber: Int) async throws -> [DanmakuComment] {
        let padded = String(format: "%04d", episodeNumber)
        let raw = Int("\(bangumiID)\(padded)") ?? 0
        return try await comments(episodeID: raw)
    }

    private func get(_ url: String, path: String) async throws -> JSONValue {
        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty || secret.isEmpty {
            throw KazumiError.message("未配置弹弹play AppId / AppSecret。可在设置中填写，签名算法与 Flutter 版相同。")
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let signature = DandanSignature.sign(appID: id, secret: secret, path: path, timestamp: timestamp)
        let response = try await http.get(url, headers: [
            "User-Agent": KazumiCore.defaultBrowserUserAgent,
            "X-Auth": "1",
            "X-AppId": id,
            "X-Timestamp": String(timestamp),
            "X-Signature": signature,
        ])
        guard let json = response.json else { throw KazumiError.message("弹幕响应无法解析") }
        return json
    }
}
