// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

/// One row of the official rule index (`PluginHTTPItem`).
public struct RuleCatalogItem: Equatable, Sendable, Identifiable {
    public var name: String
    public var version: String
    public var useNativePlayer: Bool
    public var author: String
    /// Unix milliseconds, matching `DateTime.fromMillisecondsSinceEpoch`.
    public var lastUpdate: Int
    public var antiCrawlerEnabled: Bool

    public var id: String { name.lowercased() }

    public var updatedAt: Date? {
        guard lastUpdate > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(lastUpdate) / 1000)
    }

    public init(
        name: String,
        version: String,
        useNativePlayer: Bool,
        author: String,
        lastUpdate: Int,
        antiCrawlerEnabled: Bool
    ) {
        self.name = name
        self.version = version
        self.useNativePlayer = useNativePlayer
        self.author = author
        self.lastUpdate = lastUpdate
        self.antiCrawlerEnabled = antiCrawlerEnabled
    }
}

public struct RuleCatalogParseResult: Equatable, Sendable {
    public var items: [RuleCatalogItem]
    public var skippedItems: Int

    public init(items: [RuleCatalogItem], skippedItems: Int) {
        self.items = items
        self.skippedItems = skippedItems
    }
}

public enum RuleCatalogFilter: String, CaseIterable, Sendable, Hashable {
    case all
    case installed
    case updates
}

public enum RuleCatalogSort: String, CaseIterable, Sendable, Hashable {
    case lastUpdate
    case name
}

/// Shop row relative to the rules already installed.
public enum RuleCatalogItemStatus: String, Sendable, Equatable {
    case install
    case installed
    case update

    public var actionTitle: String {
        switch self {
        case .install: return "安装"
        case .installed: return "已安装"
        case .update: return "更新"
        }
    }
}

/// Installed rule relative to a loaded catalog. `unknown` means the index was never fetched.
public enum RuleUpdateAvailability: String, Sendable, Equatable {
    case unknown
    case notInCatalog
    case latest
    case updatable

    public var title: String {
        switch self {
        case .unknown: return "未检查"
        case .notInCatalog: return "不在仓库"
        case .latest: return "已是最新"
        case .updatable: return "可更新"
        }
    }
}

public enum RuleUpdateOutcome: Equatable, Sendable {
    case updated(PluginRule)
    case requiresNewerClient
    case notNewer
    case failed(String)

    public var rule: PluginRule? {
        if case .updated(let rule) = self { return rule }
        return nil
    }
}

public struct RuleBatchUpdateResult: Equatable, Sendable {
    public var updated: Int
    public var requiresNewerClient: Int
    public var failed: Int
    public var notNewer: Int
    public var hasNoCandidates: Bool

    public init(
        updated: Int,
        requiresNewerClient: Int,
        failed: Int,
        notNewer: Int,
        hasNoCandidates: Bool
    ) {
        self.updated = updated
        self.requiresNewerClient = requiresNewerClient
        self.failed = failed
        self.notNewer = notNewer
        self.hasNoCandidates = hasNoCandidates
    }
}

public enum RuleCatalog {
    public static func shopBase(mirror: Bool) -> String {
        mirror ? KazumiCore.ruleShopMirror : KazumiCore.ruleShop
    }

    public static func indexURL(mirror: Bool) -> String {
        shopBase(mirror: mirror) + "index.json"
    }

    /// `{base}{name}.json`, with the name percent-encoded like a path segment.
    public static func fileURL(name: String, mirror: Bool) -> String {
        shopBase(mirror: mirror) + PercentEncoding.encodeComponent(name) + ".json"
    }

    /// Later duplicates win, matching the Flutter name map.
    public static func item(named name: String, in items: [RuleCatalogItem]) -> RuleCatalogItem? {
        items.last { $0.id == name.lowercased() }
    }

    public static func parseIndex(_ raw: String) throws -> RuleCatalogParseResult {
        let json: JSONValue
        do {
            json = try JSONValue.parse(raw)
        } catch {
            throw KazumiError.message("Rule catalog root must be a JSON array")
        }
        guard let array = json.array else {
            throw KazumiError.message("Rule catalog root must be a JSON array")
        }
        var items: [RuleCatalogItem] = []
        var skipped = 0
        for (index, entry) in array.enumerated() {
            do {
                items.append(try parseItem(entry, index: index))
            } catch {
                skipped += 1
            }
        }
        if !array.isEmpty && items.isEmpty {
            throw KazumiError.message("Rule catalog contains no valid items")
        }
        return RuleCatalogParseResult(items: items, skippedItems: skipped)
    }

    public static func visible(
        items: [RuleCatalogItem],
        installed: [PluginRule],
        query: String,
        filter: RuleCatalogFilter,
        sort: RuleCatalogSort
    ) -> [RuleCatalogItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = items.filter { item in
            let status = RuleUpdates.itemStatus(item: item, installed: installed)
            let matchesQuery = needle.isEmpty
                || item.name.lowercased().contains(needle)
                || item.author.lowercased().contains(needle)
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .installed:
                matchesFilter = status != .install
            case .updates:
                matchesFilter = status == .update
            }
            return matchesQuery && matchesFilter
        }
        switch sort {
        case .lastUpdate:
            return matched.sorted { lhs, rhs in
                if lhs.lastUpdate != rhs.lastUpdate { return lhs.lastUpdate > rhs.lastUpdate }
                return lhs.name.lowercased() < rhs.name.lowercased()
            }
        case .name:
            return matched.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    private static func parseItem(_ value: JSONValue, index: Int) throws -> RuleCatalogItem {
        guard let object = value.object else {
            throw KazumiError.message("Rule catalog item \(index) must be an object")
        }
        guard case .string(let name) = object["name"] else {
            throw KazumiError.message("Invalid rule catalog item \(index)")
        }
        guard case .string(let version) = object["version"] else {
            throw KazumiError.message("Invalid rule catalog item \(index)")
        }
        guard case .bool(let useNativePlayer) = object["useNativePlayer"] else {
            throw KazumiError.message("Invalid rule catalog item \(index)")
        }
        guard case .string(let author) = object["author"] else {
            throw KazumiError.message("Invalid rule catalog item \(index)")
        }
        let lastUpdate = try integer(object["lastUpdate"], missing: 0, index: index)
        let antiCrawlerEnabled = try antiCrawlerFlag(object, index: index)
        return RuleCatalogItem(
            name: name,
            version: version,
            useNativePlayer: useNativePlayer,
            author: author,
            lastUpdate: lastUpdate,
            antiCrawlerEnabled: antiCrawlerEnabled
        )
    }

    private static func antiCrawlerFlag(_ object: [String: JSONValue], index: Int) throws -> Bool {
        if let config = object["antiCrawlerConfig"], config != .null {
            guard let map = config.object else {
                return try flag(object["antiCrawlerEnabled"], index: index)
            }
            return try flag(map["enabled"], index: index)
        }
        return try flag(object["antiCrawlerEnabled"], index: index)
    }

    private static func flag(_ value: JSONValue?, index: Int) throws -> Bool {
        if value == nil || value == .null { return false }
        guard case .bool(let enabled) = value else {
            throw KazumiError.message("Invalid rule catalog item \(index)")
        }
        return enabled
    }

    private static func integer(_ value: JSONValue?, missing: Int, index: Int) throws -> Int {
        if value == nil || value == .null { return missing }
        if case .int(let number) = value { return number }
        if case .double(let number) = value,
           number.rounded() == number,
           number >= Double(Int.min),
           number <= Double(Int.max) {
            return Int(number)
        }
        throw KazumiError.message("Invalid rule catalog item \(index)")
    }
}

public enum RuleUpdates {
    /// Flutter `needUpdate`, with the controller's inequality fallback when a segment is not an int.
    public static func remoteIsNewer(local: String, remote: String) -> Bool {
        do {
            return try needUpdate(local: local, remote: remote)
        } catch {
            return local != remote
        }
    }

    public static func itemStatus(item: RuleCatalogItem, installed: [PluginRule]) -> RuleCatalogItemStatus {
        guard let local = installed.first(where: { $0.id == item.id }) else { return .install }
        return remoteIsNewer(local: local.version, remote: item.version) ? .update : .installed
    }

    public static func availability(
        plugin: PluginRule,
        catalog: [RuleCatalogItem],
        loaded: Bool
    ) -> RuleUpdateAvailability {
        guard loaded else { return .unknown }
        guard let remote = RuleCatalog.item(named: plugin.name, in: catalog) else { return .notInCatalog }
        return remoteIsNewer(local: plugin.version, remote: remote.version) ? .updatable : .latest
    }

    /// Author from the index when the shop has one; otherwise the field stored on the rule.
    public static func displayAuthor(plugin: PluginRule, catalog: [RuleCatalogItem]) -> String {
        if let author = RuleCatalog.item(named: plugin.name, in: catalog)?.author, !author.isEmpty {
            return author
        }
        return plugin.author
    }

    public static func updatableNames(installed: [PluginRule], catalog: [RuleCatalogItem]) -> [String] {
        installed.compactMap { plugin in
            guard availability(plugin: plugin, catalog: catalog, loaded: true) == .updatable else { return nil }
            return RuleCatalog.item(named: plugin.name, in: catalog)?.name
        }
    }

    /// Download decision from `PluginsController._preparePluginUpdate`. Never downgrades.
    public static func decide(
        local: PluginRule?,
        remote: PluginRule,
        expectedName: String,
        catalogAuthor: String = ""
    ) -> RuleUpdateOutcome {
        if remote.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || remote.name.lowercased() != expectedName.lowercased() {
            return .failed("下载的规则名称 \(remote.name) 与 \(expectedName) 不一致")
        }
        var adopted = remote
        adopted.name = expectedName
        if adopted.author.isEmpty {
            adopted.author = catalogAuthor
        }
        if adopted.requiresNewerClient {
            return .requiresNewerClient
        }
        if let local, !remoteIsNewer(local: local.version, remote: adopted.version) {
            return .notNewer
        }
        return .updated(adopted)
    }

    public static func singleMessage(_ outcome: RuleUpdateOutcome, installing: Bool) -> String {
        switch outcome {
        case .updated:
            return installing ? "导入成功" : "更新成功"
        case .requiresNewerClient:
            return "规则需要更高版本客户端"
        case .failed:
            return installing ? "导入规则失败" : "更新规则失败"
        case .notNewer:
            return "远程规则版本不高于本地，已跳过更新"
        }
    }

    public static func batchMessage(_ result: RuleBatchUpdateResult) -> String {
        if result.hasNoCandidates { return "没有可更新的规则" }
        if result.failed == 0 && result.requiresNewerClient == 0 && result.notNewer == 0 {
            return "更新成功 \(result.updated) 条"
        }
        var parts = ["成功 \(result.updated) 条"]
        if result.requiresNewerClient > 0 { parts.append("不兼容 \(result.requiresNewerClient) 条") }
        if result.notNewer > 0 { parts.append("已跳过 \(result.notNewer) 条") }
        if result.failed > 0 { parts.append("失败 \(result.failed) 条") }
        return "更新完成：\(parts.joined(separator: "，"))"
    }

    private static func needUpdate(local: String, remote: String) throws -> Bool {
        let localParts = segments(local)
        let remoteParts = segments(remote)
        let count = max(localParts.count, remoteParts.count)
        for index in 0..<count {
            let localSegment = index < localParts.count ? try integer(localParts[index]) : 0
            let remoteSegment = index < remoteParts.count ? try integer(remoteParts[index]) : 0
            if remoteSegment > localSegment { return true }
            if remoteSegment < localSegment { return false }
        }
        return false
    }

    private static func segments(_ version: String) -> [String] {
        if version.isEmpty { return [""] }
        return version.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }

    private static func integer(_ segment: String) throws -> Int {
        guard let value = Int(segment) else { throw KazumiError.message("invalid version") }
        return value
    }
}

public struct RuleRepository: Sendable {
    public var http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func index(mirror: Bool) async throws -> RuleCatalogParseResult {
        let response = try await http.get(RuleCatalog.indexURL(mirror: mirror))
        return try RuleCatalog.parseIndex(response.text)
    }

    public func rule(named name: String, mirror: Bool) async throws -> PluginRule {
        let response = try await http.get(RuleCatalog.fileURL(name: name, mirror: mirror))
        guard let json = response.json, json.object != nil else {
            throw KazumiError.message("规则 \(name) 必须是 JSON object")
        }
        return PluginRule(json: json)
    }
}
