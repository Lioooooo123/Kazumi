// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation
import SwiftUI
import KazumiCore

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case popular, timeline, search, favorites, history, rules, settings
    var id: String { rawValue }
}

struct RuleSearchGroup: Identifiable, Hashable, Sendable {
    var ruleName: String
    var hits: [SearchHit]
    var error: String?
    var id: String { ruleName }
}

struct EpisodeRoute: Hashable {
    var ruleName: String
    var title: String
    var source: String
    var subjectID: Int
    var subjectName: String
    var coverURL: String
}

struct PlaybackRequest: Hashable {
    var title: String
    var subjectName: String
    var subjectID: Int
    var coverURL: String
    var episodeName: String
    var pageURL: String
    var referer: String
    var userAgent: String
    var episodes: [EpisodeEntry]
}

enum AppRoute: Hashable {
    case detail(Int)
    case episodes(EpisodeRoute)
}

@MainActor
@Observable
final class AppModel {
    var sidebar: SidebarItem = .popular
    var path = NavigationPath()

    var settings: AppSettings
    var rules: [InstalledRule]
    var favorites: [FavoriteRecord]
    var history: [HistoryRecord]

    var catalog: [RuleCatalogItem] = []
    var catalogLoaded = false
    var catalogLoading = false
    var catalogError: String?
    var busyRuleNames: Set<String> = []
    var updatingAllRules = false

    var subjects: [Int: BangumiSubject] = [:]
    var popular: [BangumiSubject] = []
    var popularTag = ""
    var popularError: String?
    var popularLoading = false
    private var popularOffset = 0

    var timeline: [[BangumiSubject]] = Array(repeating: [], count: 7)
    var timelineError: String?
    var timelineLoading = false
    var seasonAnchor = Date()
    var selectedWeekday = 1

    var searchQuery = ""
    var searchBangumi: [BangumiSubject] = []
    var searchGroups: [RuleSearchGroup] = []
    var searchError: String?
    var searching = false

    var detailError: String?
    var sourceGroups: [Int: [RuleSearchGroup]] = [:]
    var sourceLoading = false
    var nowPlaying: PlaybackRequest?

    private let store: LibraryStore
    private let bangumi = BangumiClient()
    private let ruleService = RuleService()
    private let rulesRepo = RuleRepository()
    private var popularTask: UUID?
    private var searchToken = UUID()
    private var timelineToken = UUID()
    private var catalogToken = UUID()

    init() {
        let directory = AppPaths.support
        store = LibraryStore(directory: directory)
        let snapshot = (try? store.load()) ?? .empty
        settings = snapshot.settings
        rules = snapshot.rules
        favorites = snapshot.favorites
        history = snapshot.history
        selectedWeekday = AnimeCalendar.localWeekday(Date())
        CoverLoader.shared.configure(directory: AppPaths.imageCache)
        CoverLoader.shared.prefetch(history.prefix(8).map(\.imageURL))
    }

    var continueWatching: [HistoryRecord] {
        ContinueWatching.select(history)
    }

    var enabledRules: [InstalledRule] { rules.filter(\.enabled) }

    func play(_ request: PlaybackRequest) {
        nowPlaying = request
    }

    func open(_ subject: BangumiSubject) {
        subjects[subject.id] = subject
        path.append(AppRoute.detail(subject.id))
    }

    func subject(id: Int) -> BangumiSubject? { subjects[id] }

    func isFavorite(_ id: Int) -> Bool { favorites.contains { $0.subjectID == id } }

    func toggleFavorite(_ subject: BangumiSubject) {
        if let index = favorites.firstIndex(where: { $0.subjectID == subject.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(FavoriteRecord(subject: subject), at: 0)
        }
        persist()
    }

    func removeFavorite(_ id: Int) {
        favorites.removeAll { $0.subjectID == id }
        persist()
    }

    func removeHistory(_ id: String) {
        history.removeAll { $0.id == id }
        persist()
    }

    func clearHistory() {
        history.removeAll()
        persist()
    }

    func updateSettings(_ body: (inout AppSettings) -> Void) {
        body(&settings)
        persist()
    }

    func importRules(_ text: String) -> PluginImportResult {
        let result = PluginImporter.parse(text)
        for plugin in result.plugins {
            upsertRule(plugin)
        }
        return result
    }

    /// JSON and `kazumi://` are parsed locally. A bare http(s) URL is downloaded first.
    func importRemote(_ text: String) async -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "导入内容为空" }
        if PluginImporter.isRemoteURL(value) {
            do {
                let response = try await rulesRepo.http.get(value)
                return importSummary(importRules(response.text))
            } catch {
                return "导入规则失败"
            }
        }
        return importSummary(importRules(value))
    }

    func refreshCatalog() async {
        let token = UUID()
        catalogToken = token
        catalogLoading = true
        defer { if catalogToken == token { catalogLoading = false } }
        let mirror = settings.useRuleMirror
        do {
            let result = try await rulesRepo.index(mirror: mirror)
            guard catalogToken == token else { return }
            catalog = result.items
            catalogLoaded = true
            catalogError = nil
        } catch {
            guard catalogToken == token else { return }
            catalogError = describe(error)
        }
    }

    func applyCatalogRule(named name: String) async -> String {
        let key = name.lowercased()
        if busyRuleNames.contains(key) { return "" }
        busyRuleNames.insert(key)
        defer { busyRuleNames.remove(key) }
        let installing = catalogStatus(named: name) != .update
        do {
            let outcome = try await prepareCatalogRule(named: name)
            if let plugin = outcome.rule { upsertRule(plugin) }
            return RuleUpdates.singleMessage(outcome, installing: installing)
        } catch {
            return installing ? "导入规则失败" : "更新规则失败"
        }
    }

    func updateAllRules() async -> String {
        if updatingAllRules { return "" }
        updatingAllRules = true
        defer { updatingAllRules = false }
        if !catalogLoaded {
            await refreshCatalog()
        }
        guard catalogLoaded else { return "更新规则失败" }
        let names = RuleUpdates.updatableNames(installed: rules.map(\.plugin), catalog: catalog)
        if names.isEmpty {
            return RuleUpdates.batchMessage(RuleBatchUpdateResult(
                updated: 0, requiresNewerClient: 0, failed: 0, notNewer: 0, hasNoCandidates: true
            ))
        }
        var updated = 0
        var requiresNewerClient = 0
        var failed = 0
        var notNewer = 0
        for name in names {
            let key = name.lowercased()
            busyRuleNames.insert(key)
            do {
                let outcome = try await prepareCatalogRule(named: name)
                switch outcome {
                case .updated(let plugin):
                    updated += 1
                    upsertRule(plugin)
                case .requiresNewerClient:
                    requiresNewerClient += 1
                case .notNewer:
                    notNewer += 1
                case .failed:
                    failed += 1
                }
            } catch {
                failed += 1
            }
            busyRuleNames.remove(key)
        }
        return RuleUpdates.batchMessage(RuleBatchUpdateResult(
            updated: updated,
            requiresNewerClient: requiresNewerClient,
            failed: failed,
            notNewer: notNewer,
            hasNoCandidates: false
        ))
    }

    func catalogStatus(named name: String) -> RuleCatalogItemStatus {
        guard let item = RuleCatalog.item(named: name, in: catalog) else { return .install }
        return RuleUpdates.itemStatus(item: item, installed: rules.map(\.plugin))
    }

    private func prepareCatalogRule(named name: String) async throws -> RuleUpdateOutcome {
        let remote = try await rulesRepo.rule(named: name, mirror: settings.useRuleMirror)
        let item = RuleCatalog.item(named: name, in: catalog)
        let local = rules.first { $0.plugin.id == name.lowercased() }?.plugin
        return RuleUpdates.decide(
            local: local,
            remote: remote,
            expectedName: item?.name ?? name,
            catalogAuthor: item?.author ?? ""
        )
    }

    private func upsertRule(_ plugin: PluginRule) {
        if let index = rules.firstIndex(where: { $0.plugin.id == plugin.id }) {
            let enabled = rules[index].enabled
            rules[index] = InstalledRule(enabled: enabled, plugin: plugin)
        } else {
            rules.append(InstalledRule(enabled: true, plugin: plugin))
        }
        persist()
    }

    private func importSummary(_ result: PluginImportResult) -> String {
        if result.plugins.isEmpty {
            return result.failures.first ?? "没有导入任何规则"
        }
        var text = "导入 \(result.plugins.count) 条"
        if result.duplicateCount > 0 { text += "，跳过重复 \(result.duplicateCount) 条" }
        if !result.failures.isEmpty { text += "，\(result.failures.count) 条失败" }
        return text
    }

    func setRuleEnabled(_ id: String, _ enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = enabled
        persist()
    }

    func deleteRule(_ id: String) {
        rules.removeAll { $0.id == id }
        persist()
    }

    func loadPopular(reset: Bool) async {
        if popularLoading, !reset { return }
        if reset {
            popular = []
            popularOffset = 0
            popularError = nil
        }
        let token = UUID()
        popularTask = token
        popularLoading = true
        defer {
            if popularTask == token { popularLoading = false }
        }
        do {
            let page: [BangumiSubject]
            if popularTag.isEmpty {
                page = try await bangumi.trending(limit: 24, offset: popularOffset)
            } else {
                page = try await bangumi.byTag(popularTag, limit: 24, offset: popularOffset)
            }
            guard popularTask == token else { return }
            let known = Set(popular.map(\.id))
            for item in page where known.contains(item.id) == false {
                popular.append(item)
                subjects[item.id] = item
            }
            if !page.isEmpty { popularOffset += page.count }
            popularError = popular.isEmpty ? "没有拿到推荐数据" : nil
            warm(page)
        } catch {
            guard popularTask == token else { return }
            popularError = describe(error)
        }
    }

    func loadTimeline() async {
        let token = UUID()
        timelineToken = token
        timelineLoading = true
        timelineError = nil
        let anchor = seasonAnchor
        defer { if timelineToken == token { timelineLoading = false } }
        do {
            let days: [[BangumiSubject]]
            if AnimeCalendar.isSameSeason(anchor, Date()) {
                days = try await bangumi.calendar()
            } else {
                let parts = Calendar.current.dateComponents([.year, .month], from: anchor)
                days = try await bangumi.season(year: parts.year ?? 2024, month: parts.month ?? 1)
            }
            guard timelineToken == token else { return }
            timeline = days.count == 7 ? days : Array(repeating: [], count: 7)
            for day in timeline {
                for item in day { subjects[item.id] = item }
            }
            if timeline.allSatisfy(\.isEmpty) {
                timelineError = "这一季没有放送数据"
            }
            warm(Array(timeline.flatMap(\.self).prefix(24)))
        } catch {
            guard timelineToken == token else { return }
            timelineError = describe(error)
        }
    }

    func loadSubject(_ id: Int) async {
        detailError = nil
        do {
            let item = try await bangumi.subject(id: id)
            subjects[id] = item
        } catch {
            if subjects[id] == nil { detailError = describe(error) }
        }
    }

    func search() async {
        let keyword = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        let token = UUID()
        searchToken = token
        searching = true
        searchError = nil
        defer { if searchToken == token { searching = false } }
        async let catalog = bangumi.search(keyword: keyword, limit: 24)
        let groups = await searchRules(keyword)
        guard searchToken == token else { return }
        do {
            let found = try await catalog
            searchBangumi = found
            for item in found { subjects[item.id] = item }
            warm(Array(found.prefix(24)))
        } catch {
            searchBangumi = []
            searchError = describe(error)
        }
        searchGroups = groups
    }

    func findSources(for subject: BangumiSubject) async {
        sourceLoading = true
        defer { sourceLoading = false }
        let groups = await searchRules(subject.displayName)
        sourceGroups[subject.id] = groups
    }

    func chapters(for route: EpisodeRoute) async throws -> [PlaybackRoad] {
        guard let rule = rules.first(where: { $0.plugin.name == route.ruleName })?.plugin else {
            throw KazumiError.message("找不到规则 \(route.ruleName)")
        }
        let service = ruleService
        return try await Task.detached(priority: .userInitiated) {
            try await service.chapters(rule: rule, source: route.source)
        }.value
    }

    func playback(ruleName: String, subject: BangumiSubject?, title: String, episode: EpisodeEntry, episodes: [EpisodeEntry]) -> PlaybackRequest {
        let rule = rules.first { $0.plugin.name == ruleName }?.plugin
        return PlaybackRequest(
            title: title,
            subjectName: subject?.displayName ?? title,
            subjectID: subject?.id ?? 0,
            coverURL: subject?.coverURL ?? "",
            episodeName: episode.name,
            pageURL: episode.url,
            referer: rule?.referer.isEmpty == false ? (rule?.referer ?? "") : (rule?.baseURL ?? episode.url),
            userAgent: rule?.userAgent.isEmpty == false ? (rule?.userAgent ?? "") : KazumiCore.defaultBrowserUserAgent,
            episodes: episodes
        )
    }

    func playback(from history: HistoryRecord) -> PlaybackRequest {
        PlaybackRequest(
            title: history.displayName,
            subjectName: history.displayName,
            subjectID: history.subjectID,
            coverURL: history.imageURL,
            episodeName: history.episodeName,
            pageURL: history.pageURL,
            referer: history.pageURL,
            userAgent: KazumiCore.defaultBrowserUserAgent,
            episodes: [EpisodeEntry(name: history.episodeName, url: history.pageURL)]
        )
    }

    func remember(request: PlaybackRequest, position: Double, duration: Double) {
        let record = HistoryRecord(
            subjectID: request.subjectID,
            name: request.subjectName,
            nameCN: request.subjectName,
            imageURL: request.coverURL,
            episodeName: request.episodeName,
            pageURL: request.pageURL,
            position: position,
            duration: duration
        )
        history.removeAll { $0.pageURL == record.pageURL }
        history.insert(record, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        persist()
    }

    func danmakuClient() -> DanmakuClient {
        DanmakuClient(appID: settings.dandanAppID, appSecret: settings.dandanAppSecret)
    }

    private func searchRules(_ keyword: String) async -> [RuleSearchGroup] {
        let installed = enabledRules
        let service = ruleService
        return await withTaskGroup(of: RuleSearchGroup.self) { group in
            for item in installed {
                let plugin = item.plugin
                group.addTask {
                    do {
                        let hits = try await service.search(rule: plugin, keyword: keyword)
                        return RuleSearchGroup(ruleName: plugin.name, hits: hits, error: nil)
                    } catch {
                        return RuleSearchGroup(ruleName: plugin.name, hits: [], error: describe(error))
                    }
                }
            }
            var groups: [RuleSearchGroup] = []
            for await item in group { groups.append(item) }
            return groups.sorted { $0.ruleName.localizedStandardCompare($1.ruleName) == .orderedAscending }
        }
    }

    private func warm(_ subjects: [BangumiSubject]) {
        CoverLoader.shared.prefetch(subjects.map(\.coverURL))
    }

    private func persist() {
        let snapshot = LibrarySnapshot(rules: rules, favorites: favorites, history: history, settings: settings)
        try? store.save(snapshot)
    }
}

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Kazumi", isDirectory: true)
    }

    static var imageCache: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Kazumi/images", isDirectory: true)
    }
}

extension AnimeCalendar {
    static func localWeekday(_ date: Date) -> Int {
        let system = Calendar.current.component(.weekday, from: date)
        return system == 1 ? 7 : system - 1
    }
}

func describe(_ error: Error) -> String {
    if let error = error as? KazumiError { return error.description }
    return error.localizedDescription
}
