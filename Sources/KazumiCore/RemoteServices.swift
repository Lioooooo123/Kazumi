// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

// MARK: - Legacy sniff

/// Filters media addresses the Flutter WebView sniffer would keep.
public enum LegacySniff {
    public static let blockedFragments = ["googleads", "googlesyndication", "adtrafficquality", "prestrain.html"]

    public static func accepts(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("//") else { return false }
        guard !blockedFragments.contains(where: { lower.contains($0) }),
              let url = URL(string: value.hasPrefix("//") ? "https:" + value : value) else { return false }
        return MediaSniffer.isDirect(url)
    }

    /// Pulls playlist and media URLs out of a response body, including `#EXTM3U`.
    public static func mediaCandidates(in text: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        func add(_ raw: String) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard accepts(value) else { return }
            guard seen.insert(value).inserted else { return }
            found.append(value)
        }
        if text.contains("#EXTM3U") {
            for line in text.split(whereSeparator: \.isNewline) {
                let row = String(line).trimmingCharacters(in: .whitespaces)
                if row.hasPrefix("http") { add(row) }
            }
        }
        for url in MediaSniffer.mediaURLs(in: text, baseURL: nil) {
            add(url.absoluteString)
        }
        return found
    }
}

// MARK: - Super resolution

/// Storage values match Flutter `SuperResolutionMode`. The Mac player applies a
/// Core Image sharpen, which is not the Anime4K shader stack.
public enum SuperResolutionMode: Int, Sendable, Equatable, CaseIterable {
    case off = 1
    case efficiency = 2
    case quality = 3

    public var label: String {
        switch self {
        case .off: return "关闭"
        case .efficiency: return "效率档"
        case .quality: return "质量档"
        }
    }

    public var detail: String {
        switch self {
        case .off: return "不处理画面"
        case .efficiency: return "播放时用轻度锐化。这不是 Anime4K 着色器。"
        case .quality: return "播放时用更强的锐化。这不是 Anime4K 着色器。"
        }
    }

    public static func fromStorage(_ value: Int) -> SuperResolutionMode {
        SuperResolutionMode(rawValue: value) ?? .off
    }
}

// MARK: - Proxy

public struct ProxyEndpoint: Equatable, Sendable {
    public var enabled: Bool
    public var host: String
    public var port: Int

    public init(enabled: Bool, host: String, port: Int) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }

    public var isActive: Bool { enabled && !host.isEmpty && port > 0 && port < 65536 }

    /// String keys understood by `URLSessionConfiguration.connectionProxyDictionary`.
    public var sessionDictionary: [String: String] {
        guard isActive else { return [:] }
        return [
            "HTTPEnable": "1",
            "HTTPProxy": host,
            "HTTPPort": String(port),
            "HTTPSEnable": "1",
            "HTTPSProxy": host,
            "HTTPSPort": String(port),
        ]
    }
}

// MARK: - Downloads

public struct DownloadRecord: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var episodeName: String
    public var sourceURL: String
    public var fileName: String
    public var status: String
    public var receivedBytes: Int
    public var error: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        episodeName: String,
        sourceURL: String,
        fileName: String,
        status: String = "queued",
        receivedBytes: Int = 0,
        error: String = ""
    ) {
        self.id = id
        self.title = title
        self.episodeName = episodeName
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.status = status
        self.receivedBytes = receivedBytes
        self.error = error
    }
}

public enum DownloadNames {
    public static func fileName(title: String, episode: String, ext: String) -> String {
        let base = sanitize(title) + " - " + sanitize(episode)
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        let stem = trimmed.isEmpty ? "kazumi" : trimmed
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleanExt.isEmpty ? stem : stem + "." + cleanExt
    }

    public static func sanitize(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = value.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public struct HLSPlaylist: Equatable, Sendable {
    public var variant: URL?
    public var segments: [URL]

    public init(variant: URL?, segments: [URL]) {
        self.variant = variant
        self.segments = segments
    }

    public static func parse(_ text: String, base: URL) -> HLSPlaylist {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        var variant: URL?
        var expectVariant = false
        var segments: [URL] = []
        for line in lines where !line.isEmpty {
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                expectVariant = true
                continue
            }
            if line.hasPrefix("#") { continue }
            guard let url = resolve(line, base: base) else { continue }
            if expectVariant && variant == nil {
                variant = url
                expectVariant = false
                continue
            }
            segments.append(url)
        }
        return HLSPlaylist(variant: variant, segments: segments)
    }

    private static func resolve(_ line: String, base: URL) -> URL? {
        if let absolute = URL(string: line), absolute.scheme != nil { return absolute }
        return URL(string: line, relativeTo: base)?.absoluteURL
    }
}

public final class DownloadStore: @unchecked Sendable {
    public let file: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        file = directory.appendingPathComponent("downloads.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() -> [DownloadRecord] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([DownloadRecord].self, from: data)) ?? []
    }

    public func save(_ records: [DownloadRecord]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(records).write(to: file, options: .atomic)
    }
}

// MARK: - WebDAV and shield sync

public enum WebDAVPaths {
    public static let root = "/kazumiSync"
    public static let historyDirectory = "/kazumiSync/history"
    public static let librarySnapshot = "/kazumiSync/history/macos-library.json"
    public static let shieldDirectory = "/kazumiSync/danmakuShield"

    public static func shieldFile(deviceID: String) -> String {
        shieldDirectory + "/" + deviceID + ".json"
    }
}

public enum WebDAVHeaders {
    public static func authorization(username: String, password: String) -> String {
        let token = Data((username + ":" + password).utf8).base64EncodedString()
        return "Basic " + token
    }

    public static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/></d:prop></d:propfind>
    """
}

public struct ShieldSyncEntry: Equatable, Sendable, Codable {
    public var rule: String
    public var updatedAt: Int
    public var deviceId: String
    public var deleted: Bool

    public init(rule: String, updatedAt: Int, deviceId: String, deleted: Bool) {
        self.rule = rule
        self.updatedAt = updatedAt
        self.deviceId = deviceId
        self.deleted = deleted
    }
}

public enum ShieldSync {
    public static func encode(_ entries: [ShieldSyncEntry]) -> String {
        let sorted = entries.sorted { $0.rule < $1.rule }
        let payload: [String: JSONValue] = [
            "version": .int(1),
            "entries": .array(sorted.map { entry in
                .object([
                    "rule": .string(entry.rule),
                    "updatedAt": .int(entry.updatedAt),
                    "deviceId": .string(entry.deviceId),
                    "deleted": .bool(entry.deleted),
                ])
            }),
        ]
        return (try? JSONValue.object(payload).text(pretty: false)) ?? "{\"version\":1,\"entries\":[]}"
    }

    public static func decode(_ text: String) throws -> [ShieldSyncEntry] {
        let json = try JSONValue.parse(text)
        guard json.looseInt("version") == 1, let entries = json["entries"]?.array else {
            throw KazumiError.message("Invalid danmaku shield sync document")
        }
        return try entries.map { item in
            let rule = item.looseString("rule")
            let device = item.looseString("deviceId")
            guard !rule.isEmpty, rule.count <= 200, !device.isEmpty else {
                throw KazumiError.message("Invalid danmaku shield entry")
            }
            guard item["deleted"]?.bool != nil else {
                throw KazumiError.message("Invalid danmaku shield entry")
            }
            return ShieldSyncEntry(
                rule: rule,
                updatedAt: max(0, item.looseInt("updatedAt")),
                deviceId: device,
                deleted: item.looseBool("deleted")
            )
        }
    }

    /// Newer `updatedAt` wins. Ties break by device id, then a deletion beats a live rule.
    public static func merge(_ lists: [[ShieldSyncEntry]]) -> [ShieldSyncEntry] {
        var best: [String: ShieldSyncEntry] = [:]
        for entry in lists.joined() {
            if let previous = best[entry.rule] {
                if compare(entry, previous) > 0 { best[entry.rule] = entry }
            } else {
                best[entry.rule] = entry
            }
        }
        return best.values.sorted { $0.rule < $1.rule }
    }

    public static func activeRules(_ entries: [ShieldSyncEntry]) -> [String] {
        entries.filter { !$0.deleted }.map(\.rule).sorted()
    }

    private static func compare(_ lhs: ShieldSyncEntry, _ rhs: ShieldSyncEntry) -> Int {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt ? -1 : 1 }
        if lhs.deviceId != rhs.deviceId { return lhs.deviceId < rhs.deviceId ? -1 : 1 }
        return (lhs.deleted ? 1 : 0) - (rhs.deleted ? 1 : 0)
    }
}

public struct LibrarySyncBundle: Equatable, Sendable, Codable {
    public var histories: [HistoryRecord]
    public var favorites: [FavoriteRecord]

    public init(histories: [HistoryRecord], favorites: [FavoriteRecord]) {
        self.histories = histories
        self.favorites = favorites
    }

    /// Keeps the newer history row for each page, and unions favorites by subject.
    public static func merge(local: LibrarySyncBundle, remote: LibrarySyncBundle) -> LibrarySyncBundle {
        var history: [String: HistoryRecord] = [:]
        for record in local.histories + remote.histories {
            if let existing = history[record.pageURL] {
                if record.updatedAt >= existing.updatedAt { history[record.pageURL] = record }
            } else {
                history[record.pageURL] = record
            }
        }
        var favorites: [Int: FavoriteRecord] = [:]
        for record in remote.favorites + local.favorites {
            if favorites[record.subjectID] == nil || record.addedAt >= (favorites[record.subjectID]?.addedAt ?? .distantPast) {
                favorites[record.subjectID] = record
            }
        }
        return LibrarySyncBundle(
            histories: history.values.sorted { $0.updatedAt > $1.updatedAt },
            favorites: favorites.values.sorted { $0.addedAt > $1.addedAt }
        )
    }
}

public struct WebDAVClient: Sendable {
    public var http: HTTPClient
    public var baseURL: String
    public var username: String
    public var password: String

    public init(http: HTTPClient = HTTPClient(), baseURL: String, username: String, password: String) {
        self.http = http
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.username = username
        self.password = password
    }

    public func put(_ path: String, body: Data, contentType: String) async throws {
        _ = try await send("PUT", path: path, body: body, contentType: contentType)
    }

    public func getData(_ path: String) async throws -> Data {
        try await send("GET", path: path, body: nil, contentType: nil).data
    }

    public func mkcol(_ path: String) async throws {
        _ = try await send("MKCOL", path: path, body: nil, contentType: nil)
    }

    public func propfind(_ path: String) async throws -> HTTPResponse {
        try await send(
            "PROPFIND",
            path: path,
            body: Data(WebDAVHeaders.propfindBody.utf8),
            contentType: "application/xml",
            extra: ["Depth": "1"]
        )
    }

    public func ensureSyncFolders() async throws {
        for path in [WebDAVPaths.root, WebDAVPaths.historyDirectory, WebDAVPaths.shieldDirectory] {
            do {
                try await mkcol(path)
            } catch let error as KazumiError {
                if case .http(let status, _) = error, status == 405 || status == 409 || status == 301 {
                    continue
                }
                throw error
            }
        }
    }

    private func send(
        _ method: String,
        path: String,
        body: Data?,
        contentType: String?,
        extra: [String: String] = [:]
    ) async throws -> HTTPResponse {
        var headers = extra
        headers["Authorization"] = WebDAVHeaders.authorization(username: username, password: password)
        if let contentType { headers["Content-Type"] = contentType }
        let url = baseURL + path
        return try await http.sendRaw(method: method, url: url, body: body, headers: headers)
    }
}

// MARK: - SyncPlay

public enum SyncPlayEvent: Equatable, Sendable {
    case hello(username: String, room: String)
    case state(position: Double, paused: Bool, seek: Bool)
    case chat(String)
    case other
}

public enum SyncPlayCodec {
    public static let defaultHost = "syncplay.pl"
    public static let defaultPort = 8996

    public static func hello(username: String, room: String, version: String = "1.7.0") -> String {
        let json = JSONValue.object([
            "Hello": .object([
                "username": .string(username),
                "room": .object(["name": .string(room)]),
                "version": .string(version),
                "features": .object([
                    "sharedPlaylists": .bool(true),
                    "chat": .bool(true),
                    "featureList": .bool(true),
                    "readiness": .bool(true),
                    "managedRooms": .bool(false),
                ]),
            ]),
        ])
        return ((try? json.text(pretty: false)) ?? "{}") + "\n"
    }

    public static func state(position: Double, paused: Bool, clientRtt: Double = 0, latency: Double = 0) -> String {
        let json = JSONValue.object([
            "State": .object([
                "ping": .object([
                    "clientRtt": .double(clientRtt),
                    "clientLatencyCalculation": .double(latency),
                    "latencyCalculation": .double(0),
                ]),
                "playstate": .object([
                    "position": .double(position),
                    "paused": .bool(paused),
                    "doSeek": .bool(false),
                ]),
            ]),
        ])
        return ((try? json.text(pretty: false)) ?? "{}") + "\n"
    }

    public static func chat(_ message: String) -> String {
        let json = JSONValue.object(["Chat": .string(message)])
        return ((try? json.text(pretty: false)) ?? "{}") + "\n"
    }

    public static func parse(_ line: String) -> SyncPlayEvent {
        guard let json = try? JSONValue.parse(line) else { return .other }
        if let hello = json["Hello"] {
            return .hello(
                username: hello.looseString("username"),
                room: hello["room"]?.looseString("name") ?? ""
            )
        }
        if let state = json["State"] {
            let play = state["playstate"]
            let position = play?["position"]?.double ?? 0
            let paused = play?.looseBool("paused") ?? false
            let seek = play?["doSeek"]?.bool ?? false
            return .state(position: position, paused: paused, seek: seek)
        }
        if let chat = json["Chat"]?.string { return .chat(chat) }
        return .other
    }
}

// MARK: - DLNA

public enum DLNAMessages {
    public static let searchTarget = "239.255.255.250"
    public static let searchPort = 1900

    public static func searchRequest() -> String {
        [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: 3",
            "ST: urn:schemas-upnp-org:device:MediaRenderer:1",
            "",
            "",
        ].joined(separator: "\r\n")
    }

    public static func location(in response: String) -> String? {
        for line in response.split(whereSeparator: \.isNewline) {
            let row = String(line)
            if row.lowercased().hasPrefix("location:") {
                let value = row.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                if value.lowercased().hasPrefix("http") { return value }
            }
        }
        return nil
    }

    public static func setAVTransportURI(mediaURL: String, title: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(escape(mediaURL))</CurrentURI>
              <CurrentURIMetaData>\(escape(didl(title: title, url: mediaURL)))</CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
    }

    public static func play() -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Speed>1</Speed>
            </u:Play>
          </s:Body>
        </s:Envelope>
        """
    }

    public static func controlURL(in description: String, base: URL) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<serviceType>\s*urn:schemas-upnp-org:service:AVTransport:1\s*</serviceType>[\s\S]*?<controlURL>\s*([^<]+)\s*</controlURL>"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(description.startIndex..<description.endIndex, in: description)
        guard let match = regex.firstMatch(in: description, range: range),
              let slice = Range(match.range(at: 1), in: description) else { return nil }
        let raw = String(description[slice]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }

    private static func didl(title: String, url: String) -> String {
        "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\"><item><dc:title xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\(escape(title))</dc:title><res>\(escape(url))</res></item></DIDL-Lite>"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Library queries and trace.moe

public enum LibraryQuery {
    public static func history(_ records: [HistoryRecord], query: String, unfinishedOnly: Bool) -> [HistoryRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return records.filter { record in
            let matches = needle.isEmpty
                || record.displayName.lowercased().contains(needle)
                || record.episodeName.lowercased().contains(needle)
            let unfinished = !unfinishedOnly || (record.duration <= 1 || record.position < record.duration - 5)
            return matches && unfinished
        }
    }
}

public struct TraceHit: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var episode: String
    public var similarity: Double
    public var imageURL: String

    public init(title: String, episode: String, similarity: Double, imageURL: String) {
        self.title = title
        self.episode = episode
        self.similarity = similarity
        self.imageURL = imageURL
        self.id = title + "|" + episode + "|" + imageURL
    }
}

public enum TraceMoe {
    public static func searchURL(imageURL: String) -> String {
        let encoded = PercentEncoding.encodeComponent(imageURL)
        return "https://api.trace.moe/search?anilistInfo&url=\(encoded)"
    }

    public static func parse(_ json: JSONValue) -> [TraceHit] {
        (json["result"]?.array ?? []).compactMap { item in
            let title = title(of: item["anilist"])
            guard !title.isEmpty else { return nil }
            let episode = item["episode"]?.templateString ?? ""
            let similarity = item["similarity"]?.double ?? 0
            let image = item.looseString("image")
            return TraceHit(title: title, episode: episode, similarity: similarity, imageURL: image)
        }
    }

    private static func title(of value: JSONValue?) -> String {
        guard let value else { return "" }
        if let text = value.string { return text }
        if let native = value["title"]?.looseString("native"), !native.isEmpty { return native }
        if let romaji = value["title"]?.looseString("romaji"), !romaji.isEmpty { return romaji }
        return value.looseString("title")
    }
}

public struct BangumiCredit: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: String
    public var imageURL: String

    public init(name: String, role: String, imageURL: String) {
        self.name = name
        self.role = role
        self.imageURL = imageURL
        self.id = name + "|" + role
    }
}

public struct BangumiComment: Equatable, Sendable, Identifiable {
    public var id: String
    public var user: String
    public var text: String
    public var score: Int

    public init(user: String, text: String, score: Int) {
        self.user = user
        self.text = text
        self.score = score
        self.id = user + "|" + text
    }
}

public enum BangumiExtras {
    public static func credits(from json: JSONValue) -> [BangumiCredit] {
        let rows = json.array ?? json["data"]?.array ?? []
        return rows.compactMap { item in
            let name = firstNonEmpty(item.looseString("nameCN"), item.looseString("name_cn"), item.looseString("name"))
            guard !name.isEmpty else { return nil }
            let role = firstNonEmpty(item.looseString("relation"), item.looseString("career"))
            let image = item["images"]?.looseString("medium") ?? item["images"]?.looseString("large") ?? ""
            return BangumiCredit(name: name, role: role, imageURL: image)
        }
    }

    public static func comments(from json: JSONValue) -> [BangumiComment] {
        let rows = json["data"]?.array ?? json.array ?? []
        return rows.compactMap { item in
            let text = firstNonEmpty(item.looseString("comment"), item.looseString("content"))
            guard !text.isEmpty else { return nil }
            let user = item["user"]?.looseString("nickname") ?? item.looseString("user")
            return BangumiComment(user: user.isEmpty ? "匿名" : user, text: text, score: item.looseInt("rate"))
        }
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.isEmpty } ?? ""
    }
}
