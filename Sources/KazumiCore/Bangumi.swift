// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

public struct BangumiTag: Equatable, Sendable, Hashable, Codable {
    public var name: String
    public var count: Int

    public init(name: String, count: Int = 0) {
        self.name = name
        self.count = count
    }
}

public struct BangumiSubject: Equatable, Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var type: Int
    public var name: String
    public var nameCN: String
    public var summary: String
    public var airDate: String
    public var airWeekday: Int
    public var rank: Int
    public var score: Double
    public var votes: Int
    public var images: [String: String]
    public var tags: [BangumiTag]
    public var aliases: [String]
    public var info: String
    public var metaTags: [String]
    public var episodeCount: Int

    public var displayName: String { nameCN.isEmpty ? name : nameCN }

    public var coverURL: String {
        for key in ["large", "common", "medium", "small", "grid"] {
            if let value = images[key], !value.isEmpty { return value }
        }
        return images.values.first(where: { !$0.isEmpty }) ?? ""
    }

    public init(json: JSONValue) throws {
        guard let id = json.looseInt("id").nonZero else {
            throw KazumiError.message("Bangumi 条目缺少 id")
        }
        self.id = id
        type = json.looseInt("type", default: 2)
        name = json.looseString("name")
        let cn = json.looseString("name_cn")
        let cn2 = json.looseString("nameCN")
        if !cn.isEmpty {
            nameCN = cn
        } else if !cn2.isEmpty {
            nameCN = cn2
        } else {
            nameCN = name
        }
        summary = json.looseString("summary")
        airDate = Self.airDate(json)
        airWeekday = AnimeCalendar.weekday(from: airDate) ?? 0
        let rating = json["rating"]
        rank = rating?.looseInt("rank") ?? 0
        score = rating?["score"]?.double ?? Double(rating?.looseInt("score") ?? 0)
        votes = rating?.looseInt("total") ?? 0
        var images: [String: String] = [:]
        if let map = json["images"]?.object {
            for (key, value) in map {
                if let string = value.string, !string.isEmpty { images[key] = string }
            }
        }
        if images.isEmpty, let image = json["image"]?.string, !image.isEmpty {
            images["large"] = image
        }
        self.images = images
        tags = (json["tags"]?.array ?? []).compactMap { item in
            if let name = item.string, !name.isEmpty { return BangumiTag(name: name) }
            let name = item.looseString("name")
            guard !name.isEmpty else { return nil }
            return BangumiTag(name: name, count: item.looseInt("count"))
        }
        aliases = Self.aliases(json)
        info = json.looseString("info")
        metaTags = (json["metaTags"]?.array ?? []).compactMap { $0.string?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        episodeCount = json.looseInt("eps") == 0 ? json.looseInt("total_episodes") : json.looseInt("eps")
    }

    public static func list(from value: JSONValue) -> [BangumiSubject] {
        let array = value.array ?? value["data"]?.array ?? []
        return array.compactMap { item in
            let payload = item["subject"]?.object != nil ? (item["subject"] ?? item) : item
            return try? BangumiSubject(json: payload)
        }
    }

    private static func airDate(_ json: JSONValue) -> String {
        let top = json.looseString("date")
        if !top.isEmpty { return top }
        return json["airtime"]?.looseString("date") ?? ""
    }

    private static func aliases(_ json: JSONValue) -> [String] {
        guard let infobox = json["infobox"]?.array else { return [] }
        for item in infobox where item.looseString("key") == "别名" {
            let raw = item["values"] ?? item["value"]
            if let list = raw?.array {
                return list.compactMap { element -> String? in
                    if let map = element.object, let value = map["v"]?.templateString.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                        return value
                    }
                    let text = element.templateString.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : text
                }
            }
            if let text = raw?.templateString.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return [text]
            }
        }
        return []
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

public enum AnimeCalendar {
    public static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// Monday = 1 ... Sunday = 7, matching Dart `DateTime.weekday`.
    public static func weekday(from airDate: String) -> Int? {
        let parts = airDate.split(separator: "-")
        guard parts.count >= 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = calendar.date(from: components) else { return nil }
        let system = calendar.component(.weekday, from: date)
        return system == 1 ? 7 : system - 1
    }

    public static func seasonName(month: Int) -> String {
        if month <= 3 { return "冬" }
        if month <= 6 { return "春" }
        if month <= 9 { return "夏" }
        return "秋"
    }

    public static func seasonLabel(year: Int, month: Int) -> String {
        "\(year)年\(seasonName(month: month))季"
    }

    public static func seasonStart(year: Int, month: Int) -> (year: Int, month: Int) {
        let startMonth = ((month - 1) / 3) * 3 + 1
        return (year, startMonth)
    }

    /// Inclusive start and exclusive end, `yyyy-MM-dd`, for Bangumi air_date filters.
    public static func seasonRange(year: Int, month: Int) -> (start: String, end: String) {
        let start = seasonStart(year: year, month: month)
        let endMonth = start.month + 3
        let endYear = endMonth > 12 ? start.year + 1 : start.year
        let normalizedEnd = endMonth > 12 ? endMonth - 12 : endMonth
        return (
            String(format: "%04d-%02d-01", start.year, start.month),
            String(format: "%04d-%02d-01", endYear, normalizedEnd)
        )
    }

    public static func isSameSeason(_ lhs: Date, _ rhs: Date, calendar: Calendar = calendar) -> Bool {
        let a = calendar.dateComponents([.year, .month], from: lhs)
        let b = calendar.dateComponents([.year, .month], from: rhs)
        guard let ay = a.year, let am = a.month, let by = b.year, let bm = b.month else { return false }
        return ay == by && (am - 1) / 3 == (bm - 1) / 3
    }

    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()
}

public struct BangumiClient: Sendable {
    public var http: HTTPClient
    public var userAgent: String

    public init(http: HTTPClient = HTTPClient(), userAgent: String = KazumiCore.bangumiUserAgent) {
        self.http = http
        self.userAgent = userAgent
    }

    public func trending(limit: Int = 24, offset: Int = 0) async throws -> [BangumiSubject] {
        let url = "\(KazumiCore.bangumiNextAPI)/p1/trending/subjects?type=2&limit=\(limit)&offset=\(offset)"
        let response = try await http.get(url, headers: headers)
        guard let json = response.json else { throw KazumiError.message("番剧趋势响应无法解析") }
        return BangumiSubject.list(from: json)
    }

    /// Seven lists, Monday through Sunday, from `/p1/calendar`.
    public func calendar() async throws -> [[BangumiSubject]] {
        let response = try await http.get("\(KazumiCore.bangumiNextAPI)/p1/calendar", headers: headers)
        guard let json = response.json else { throw KazumiError.message("时间表响应无法解析") }
        return (1...7).map { day in
            BangumiSubject.list(from: json["\(day)"] ?? .array([]))
        }
    }

    public func season(year: Int, month: Int, limit: Int = 100) async throws -> [[BangumiSubject]] {
        let range = AnimeCalendar.seasonRange(year: year, month: month)
        let body = JSONValue.object([
            "keyword": .string(""),
            "sort": .string("rank"),
            "filter": .object([
                "type": .array([.int(2)]),
                "tag": .array([.string("日本")]),
                "air_date": .array([.string(">=" + range.start), .string("<" + range.end)]),
                "rank": .array([.string(">0"), .string("<=99999")]),
                "nsfw": .bool(true),
            ]),
        ])
        let items = try await search(body: body, limit: limit, offset: 0)
        return groupByWeekday(items)
    }

    public func search(keyword: String, tags: [String] = [], limit: Int = 20, offset: Int = 0, sort: String = "heat") async throws -> [BangumiSubject] {
        let body = JSONValue.object([
            "keyword": .string(keyword),
            "sort": .string(sort),
            "filter": .object([
                "type": .array([.int(2)]),
                "tag": .array(tags.map { .string($0) }),
                "rank": .array([.string(">=0"), .string("<=99999")]),
                "nsfw": .bool(false),
            ]),
        ])
        return try await search(body: body, limit: limit, offset: offset).filter { !$0.displayName.isEmpty }
    }

    public func byTag(_ tag: String, limit: Int = 24, offset: Int = 0) async throws -> [BangumiSubject] {
        try await search(keyword: "", tags: tag.isEmpty ? ["日本"] : [tag], limit: limit, offset: offset, sort: "rank")
    }

    public func characters(id: Int) async throws -> [BangumiCredit] {
        let response = try await http.get("\(KazumiCore.bangumiAPI)/v0/subjects/\(id)/characters", headers: headers)
        guard let json = response.json else { throw KazumiError.message("角色响应无法解析") }
        return BangumiExtras.credits(from: json)
    }

    public func staff(id: Int) async throws -> [BangumiCredit] {
        let response = try await http.get("\(KazumiCore.bangumiAPI)/v0/subjects/\(id)/persons", headers: headers)
        guard let json = response.json else { throw KazumiError.message("Staff 响应无法解析") }
        return BangumiExtras.credits(from: json)
    }

    public func comments(id: Int) async throws -> [BangumiComment] {
        let response = try await http.get("\(KazumiCore.bangumiNextAPI)/p1/subjects/\(id)/comments?limit=20&offset=0", headers: headers)
        guard let json = response.json else { throw KazumiError.message("评论响应无法解析") }
        return BangumiExtras.comments(from: json)
    }

    /// Bangumi collection type 3 is "在看".
    public func updateCollection(id: Int, token: String, type: Int = 3) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KazumiError.message("请先在设置里填写 Bangumi 访问令牌") }
        var headers = self.headers
        headers["Authorization"] = "Bearer \(trimmed)"
        _ = try await http.post(
            "\(KazumiCore.bangumiAPI)/v0/users/-/collections/\(id)",
            json: .object(["type": .int(type)]),
            headers: headers
        )
    }

    public func subject(id: Int) async throws -> BangumiSubject {
        let response = try await http.get("\(KazumiCore.bangumiAPI)/v0/subjects/\(id)", headers: headers)
        guard let json = response.json else { throw KazumiError.message("条目详情无法解析") }
        return try BangumiSubject(json: json)
    }

    private func search(body: JSONValue, limit: Int, offset: Int) async throws -> [BangumiSubject] {
        let url = "\(KazumiCore.bangumiAPI)/v0/search/subjects?limit=\(limit)&offset=\(offset)"
        let response = try await http.post(url, json: body, headers: headers)
        guard let json = response.json else { throw KazumiError.message("搜索响应无法解析") }
        return BangumiSubject.list(from: json)
    }

    private func groupByWeekday(_ items: [BangumiSubject]) -> [[BangumiSubject]] {
        (1...7).map { day in items.filter { $0.airWeekday == day } }
    }

    private var headers: [String: String] {
        [
            "User-Agent": userAgent,
            "Content-Type": "application/json",
        ]
    }
}
