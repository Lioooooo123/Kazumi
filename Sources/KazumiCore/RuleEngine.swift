// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

public struct PreparedRequest: Equatable, Sendable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var query: [String: String]
    public var bodyType: String
    public var body: JSONValue?
    public var includeCookies: Bool

    public init(
        method: String,
        url: String,
        headers: [String: String] = [:],
        query: [String: String] = [:],
        bodyType: String = APIBodyType.none,
        body: JSONValue? = nil,
        includeCookies: Bool = false
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.query = query
        self.bodyType = bodyType
        self.body = body
        self.includeCookies = includeCookies
    }
}

public struct SearchHit: Equatable, Sendable, Identifiable, Hashable {
    public var name: String
    public var source: String

    public var id: String { "\(name)|\(source)" }

    public init(name: String, source: String) {
        self.name = name
        self.source = source
    }
}

public struct EpisodeEntry: Equatable, Sendable, Identifiable, Hashable {
    public var name: String
    public var url: String

    public var id: String { url }

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

public struct PlaybackRoad: Equatable, Sendable, Identifiable, Hashable {
    public var name: String
    public var episodes: [EpisodeEntry]

    public var id: String { name + "|" + (episodes.first?.url ?? "") }

    public init(name: String, episodes: [EpisodeEntry]) {
        self.name = name
        self.episodes = episodes
    }
}

public struct SearchParseResult: Equatable, Sendable {
    public var items: [SearchHit]
    public var diagnostics: [String]

    public init(items: [SearchHit], diagnostics: [String] = []) {
        self.items = items
        self.diagnostics = diagnostics
    }
}

public struct ChapterParseResult: Equatable, Sendable {
    public var roads: [PlaybackRoad]
    public var diagnostics: [String]

    public init(roads: [PlaybackRoad], diagnostics: [String] = []) {
        self.roads = roads
        self.diagnostics = diagnostics
    }
}

/// Parses Kazumi XPath and API rules. Network I/O lives in `RuleService`.
public struct RuleEngine: Sendable {
    public init() {}

    public func prepareSearch(rule: PluginRule, keyword: String) throws -> PreparedRequest {
        if rule.searchMode == RuleMode.api {
            return try prepareAPI(rule.searchAPI.request, variables: ["keyword": .string(keyword)])
        }
        let queryURL = rule.searchURL.replacingOccurrences(
            of: "@keyword",
            with: PercentEncoding.encodeQueryComponent(keyword)
        )
        guard let uri = URL(string: queryURL), let scheme = uri.scheme, !scheme.isEmpty, !(uri.host ?? "").isEmpty else {
            throw KazumiError.message("搜索 URL 无效: \(queryURL)")
        }
        if !rule.usePost {
            return PreparedRequest(method: "GET", url: queryURL, includeCookies: true)
        }
        var components = URLComponents(url: uri, resolvingAgainstBaseURL: false)
        let body = components?.queryItems ?? []
        components?.query = nil
        let target = components?.string ?? queryURL
        var form: [String: JSONValue] = [:]
        for item in body {
            form[item.name] = .string(item.value ?? "")
        }
        return PreparedRequest(
            method: "POST",
            url: target,
            bodyType: APIBodyType.form,
            body: .object(form),
            includeCookies: true
        )
    }

    public func prepareChapters(rule: PluginRule, source: String) throws -> PreparedRequest {
        if rule.chapterMode == RuleMode.api {
            return try prepareAPI(rule.chapterAPI.request, variables: ["source": .string(source)])
        }
        let url = normalizeEpisodeURL(baseURL: rule.baseURL, raw: source)
        guard let uri = URL(string: url), let scheme = uri.scheme, !scheme.isEmpty, !(uri.host ?? "").isEmpty else {
            throw KazumiError.message("章节 URL 无效: \(url)")
        }
        return PreparedRequest(method: "GET", url: url, includeCookies: false)
    }

    public func parseSearch(rule: PluginRule, raw: String) throws -> SearchParseResult {
        if rule.searchMode == RuleMode.api {
            return try parseAPISearch(raw, config: rule.searchAPI)
        }
        return try parseXPathSearch(raw, rule: rule)
    }

    public func parseChapters(rule: PluginRule, raw: String, source: String) throws -> ChapterParseResult {
        if rule.chapterMode == RuleMode.api {
            return try parseAPIChapters(raw, config: rule.chapterAPI, source: source, baseURL: rule.baseURL)
        }
        return try parseXPathChapters(raw, rule: rule)
    }

    // MARK: XPath

    private func parseXPathSearch(_ raw: String, rule: PluginRule) throws -> SearchParseResult {
        let root = HTMLParser.parse(raw)
        if detectsCaptcha(raw, rule: rule, root: root) {
            throw KazumiError.captchaRequired(plugin: rule.name, pageURL: "")
        }
        let nodes = try XPath.query(rule.searchList, from: root)
        var items: [SearchHit] = []
        var diagnostics: [String] = []
        for (index, node) in nodes.enumerated() {
            guard case .element(let element) = node else {
                diagnostics.append("搜索节点 \(index) 不是元素，已跳过")
                continue
            }
            let name = (try XPath.first(rule.searchName, from: element)?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let source = (try XPath.first(rule.searchResult, from: element)?.linkValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || source.isEmpty {
                diagnostics.append("搜索节点 \(index) 缺少名称或来源，已跳过")
                continue
            }
            items.append(SearchHit(name: name, source: source))
        }
        return SearchParseResult(items: items, diagnostics: diagnostics)
    }

    private func parseXPathChapters(_ raw: String, rule: PluginRule) throws -> ChapterParseResult {
        let root = HTMLParser.parse(raw)
        let roadNodes = try XPath.query(rule.chapterRoads, from: root)
        var roads: [PlaybackRoad] = []
        var diagnostics: [String] = []
        for (roadIndex, node) in roadNodes.enumerated() {
            guard case .element(let element) = node else { continue }
            let episodeNodes = try XPath.query(rule.chapterResult, from: element)
            var episodes: [EpisodeEntry] = []
            for (episodeIndex, episodeNode) in episodeNodes.enumerated() {
                guard case .element(let episode) = episodeNode else { continue }
                let source = (episode.attribute("href") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if source.isEmpty {
                    diagnostics.append("线路 \(roadIndex) 的剧集节点 \(episodeIndex) 缺少 URL，已跳过")
                    continue
                }
                let collapsed = episode.textContent.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                let name = collapsed.isEmpty ? "第\(episodeIndex + 1)集" : collapsed
                episodes.append(EpisodeEntry(
                    name: name,
                    url: normalizeEpisodeURL(baseURL: rule.baseURL, raw: source)
                ))
            }
            if episodes.isEmpty {
                diagnostics.append("线路 \(roadIndex) 没有有效剧集，已跳过")
                continue
            }
            roads.append(PlaybackRoad(name: "播放线路\(roads.count + 1)", episodes: episodes))
        }
        return ChapterParseResult(roads: roads, diagnostics: diagnostics)
    }

    private func detectsCaptcha(_ raw: String, rule: PluginRule, root: HTMLElement) -> Bool {
        let config = rule.antiCrawler
        guard config.enabled else { return false }
        let detect = config.captchaDetectValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detect.isEmpty {
            switch config.captchaDetectType {
            case CaptchaDetectType.text:
                return raw.contains(detect)
            case CaptchaDetectType.regex:
                return raw.range(of: detect, options: [.regularExpression, .caseInsensitive]) != nil
            default:
                return (try? XPath.first(detect, from: root)) != nil
            }
        }
        for expression in [config.captchaImage, config.captchaButton] {
            let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if (try? XPath.first(trimmed, from: root)) != nil { return true }
        }
        return false
    }

    // MARK: API

    private func prepareAPI(_ config: APIRequestConfig, variables: [String: JSONValue]) throws -> PreparedRequest {
        let method = config.method.uppercased()
        guard method == "GET" || method == "POST" else {
            throw KazumiError.message("仅支持 GET/POST，当前为 \(method)")
        }
        let template = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if template.isEmpty {
            throw KazumiError.message("API 请求 URL 不能为空")
        }
        let url = try renderTemplate(template, variables: variables, encode: true)
        guard let uri = URL(string: url), let scheme = uri.scheme, !scheme.isEmpty, !(uri.host ?? "").isEmpty else {
            throw KazumiError.message("API 请求 URL 无效: \(url)")
        }
        let hasBody = method == "POST" && config.bodyType != APIBodyType.none
        return PreparedRequest(
            method: method,
            url: url,
            headers: try renderMap(config.headers, variables: variables),
            query: try renderMap(config.query, variables: variables),
            bodyType: config.bodyType,
            body: hasBody ? try renderValue(config.body, variables: variables) : nil,
            includeCookies: true
        )
    }

    private func parseAPISearch(_ raw: String, config: APISearchConfig) throws -> SearchParseResult {
        try JSONPath.validate(config.listPath)
        try JSONPath.validate(config.namePath)
        try JSONPath.validate(config.sourcePath)
        let document = try decode(raw)
        let nodes = try JSONPath.read(document, config.listPath)
        var items: [SearchHit] = []
        var diagnostics: [String] = []
        for (index, node) in nodes.enumerated() {
            let name = try JSONPath.readFirst(node, config.namePath)?.fieldString ?? ""
            let source = try JSONPath.readFirst(node, config.sourcePath)?.fieldString ?? ""
            if name.isEmpty || source.isEmpty {
                diagnostics.append("搜索节点 \(index) 缺少名称或来源，已跳过")
                continue
            }
            items.append(SearchHit(name: name, source: source))
        }
        return SearchParseResult(items: items, diagnostics: diagnostics)
    }

    private func parseAPIChapters(
        _ raw: String,
        config: APIChapterConfig,
        source: String,
        baseURL: String
    ) throws -> ChapterParseResult {
        try validateChapter(config)
        let document = try decode(raw)
        var variables: [String: JSONValue] = ["source": .string(source)]
        for (key, path) in config.variables {
            guard let value = try JSONPath.readFirst(document, path) else {
                throw KazumiError.message("章节响应变量 \(key) 未匹配到值: \(path)")
            }
            variables[key] = value
        }
        var diagnostics: [String] = []
        let roads = config.format == APIChapterFormat.delimited
            ? try parseDelimited(document, config: config, variables: variables, baseURL: baseURL, diagnostics: &diagnostics)
            : try parseNested(document, config: config, variables: variables, baseURL: baseURL, diagnostics: &diagnostics)
        return ChapterParseResult(roads: roads, diagnostics: diagnostics)
    }

    private func parseNested(
        _ document: JSONValue,
        config: APIChapterConfig,
        variables: [String: JSONValue],
        baseURL: String,
        diagnostics: inout [String]
    ) throws -> [PlaybackRoad] {
        let hasRoads = !config.roadsPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let roadNodes = hasRoads ? try JSONPath.read(document, config.roadsPath) : [document]
        var roads: [PlaybackRoad] = []
        for (roadIndex, roadNode) in roadNodes.enumerated() {
            let roadName = hasRoads && !config.roadNamePath.trimmingCharacters(in: .whitespaces).isEmpty
                ? (try JSONPath.readFirst(roadNode, config.roadNamePath)?.fieldString ?? "")
                : ""
            let episodeNodes = try JSONPath.read(roadNode, config.episodesPath)
            var episodes: [EpisodeEntry] = []
            for (episodeIndex, episodeNode) in episodeNodes.enumerated() {
                let episodeName = try JSONPath.readFirst(episodeNode, config.episodeNamePath)?.fieldString ?? ""
                let rawURL = config.episodeURLPath.trimmingCharacters(in: .whitespaces).isEmpty
                    ? ""
                    : (try JSONPath.readFirst(episodeNode, config.episodeURLPath)?.fieldString ?? "")
                let page = try resolveEpisodeURL(
                    config,
                    variables: variables,
                    rawURL: rawURL,
                    roadIndex: roadIndex,
                    episodeIndex: episodeIndex,
                    baseURL: baseURL
                )
                if page.isEmpty {
                    diagnostics.append("线路 \(roadIndex) 的剧集节点 \(episodeIndex) 缺少 URL，已跳过")
                    continue
                }
                episodes.append(EpisodeEntry(
                    name: episodeName.isEmpty ? "第\(episodeIndex + 1)集" : episodeName,
                    url: page
                ))
            }
            if episodes.isEmpty {
                diagnostics.append("线路节点 \(roadIndex) 没有有效剧集，已跳过")
                continue
            }
            roads.append(PlaybackRoad(
                name: roadName.isEmpty ? "播放线路\(roads.count + 1)" : roadName,
                episodes: episodes
            ))
        }
        return roads
    }

    private func parseDelimited(
        _ document: JSONValue,
        config: APIChapterConfig,
        variables: [String: JSONValue],
        baseURL: String,
        diagnostics: inout [String]
    ) throws -> [PlaybackRoad] {
        let namesValue = try JSONPath.readFirst(document, config.roadNamesPath)?.fieldString ?? ""
        let episodesValue = try JSONPath.readFirst(document, config.roadEpisodesPath)?.fieldString ?? ""
        if episodesValue.isEmpty { return [] }
        let roadNames = namesValue.components(separatedBy: config.roadSeparator)
        let groups = episodesValue.components(separatedBy: config.roadSeparator)
        var roads: [PlaybackRoad] = []
        for (roadIndex, group) in groups.enumerated() {
            var episodes: [EpisodeEntry] = []
            let entries = group.components(separatedBy: config.episodeSeparator)
            for (episodeIndex, entry) in entries.enumerated() {
                let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                guard let separator = trimmed.range(of: config.fieldSeparator) else {
                    diagnostics.append("线路 \(roadIndex) 的剧集条目 \(episodeIndex) 缺少字段分隔符，已跳过")
                    continue
                }
                let name = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rawURL = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                let page = try resolveEpisodeURL(
                    config,
                    variables: variables,
                    rawURL: rawURL,
                    roadIndex: roadIndex,
                    episodeIndex: episodeIndex,
                    baseURL: baseURL
                )
                if page.isEmpty {
                    diagnostics.append("线路 \(roadIndex) 的剧集条目 \(episodeIndex) 缺少 URL，已跳过")
                    continue
                }
                episodes.append(EpisodeEntry(name: name.isEmpty ? "第\(episodeIndex + 1)集" : name, url: page))
            }
            if episodes.isEmpty {
                diagnostics.append("线路 \(roadIndex) 没有有效剧集，已跳过")
                continue
            }
            let configured = roadIndex < roadNames.count ? roadNames[roadIndex].trimmingCharacters(in: .whitespaces) : ""
            roads.append(PlaybackRoad(
                name: configured.isEmpty ? "播放线路\(roads.count + 1)" : configured,
                episodes: episodes
            ))
        }
        return roads
    }

    private func resolveEpisodeURL(
        _ config: APIChapterConfig,
        variables root: [String: JSONValue],
        rawURL: String,
        roadIndex: Int,
        episodeIndex: Int,
        baseURL: String
    ) throws -> String {
        guard let page = config.episodePage else {
            return normalizeEpisodeURL(baseURL: baseURL, raw: rawURL)
        }
        if page.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw KazumiError.message("播放页地址模板不能为空")
        }
        var variables = root
        variables["episodeUrl"] = .string(rawURL)
        variables["roadIndex"] = .int(roadIndex)
        variables["roadNumber"] = .int(roadIndex + 1)
        variables["episodeIndex"] = .int(episodeIndex)
        variables["episodeNumber"] = .int(episodeIndex + 1)
        let path = try renderTemplate(page.url, variables: variables, encode: true)
        guard var components = URLComponents(string: path) else {
            throw KazumiError.message("剧集页面 URL 无效: \(path)")
        }
        let rendered = try renderMap(page.query, variables: variables)
        if !rendered.isEmpty {
            var items = components.queryItems ?? []
            for (key, value) in rendered.sorted(by: { $0.key < $1.key }) {
                items.removeAll { $0.name == key }
                items.append(URLQueryItem(name: key, value: value))
            }
            components.queryItems = items
        }
        return normalizeEpisodeURL(baseURL: baseURL, raw: components.string ?? path)
    }

    private func validateChapter(_ config: APIChapterConfig) throws {
        for path in config.variables.values {
            try JSONPath.validate(path)
        }
        if config.format == APIChapterFormat.delimited {
            try JSONPath.validate(config.roadNamesPath)
            try JSONPath.validate(config.roadEpisodesPath)
            if config.roadSeparator.isEmpty || config.episodeSeparator.isEmpty || config.fieldSeparator.isEmpty {
                throw KazumiError.message("章节分隔符不能为空")
            }
            return
        }
        if !config.roadsPath.trimmingCharacters(in: .whitespaces).isEmpty {
            try JSONPath.validate(config.roadsPath)
        }
        if !config.roadNamePath.trimmingCharacters(in: .whitespaces).isEmpty {
            try JSONPath.validate(config.roadNamePath)
        }
        try JSONPath.validate(config.episodesPath)
        try JSONPath.validate(config.episodeNamePath)
        if !config.episodeURLPath.trimmingCharacters(in: .whitespaces).isEmpty {
            try JSONPath.validate(config.episodeURLPath)
        } else if config.episodePage == nil {
            throw KazumiError.message("必须配置播放入口地址路径或播放页地址模板")
        }
        if let page = config.episodePage, page.url.trimmingCharacters(in: .whitespaces).isEmpty {
            throw KazumiError.message("播放页地址模板不能为空")
        }
    }

    private func decode(_ raw: String) throws -> JSONValue {
        do {
            return try JSONValue.parse(raw)
        } catch {
            throw KazumiError.message("API 响应不是有效 JSON")
        }
    }

    private func renderMap(_ input: [String: JSONValue], variables: [String: JSONValue]) throws -> [String: String] {
        var rendered: [String: String] = [:]
        for (key, value) in input {
            let renderedKey = try renderTemplate(key, variables: variables, encode: false)
            let renderedValue = try renderValue(value, variables: variables)
            rendered[renderedKey] = renderedValue?.templateString ?? ""
        }
        return rendered
    }

    private func renderValue(_ value: JSONValue?, variables: [String: JSONValue]) throws -> JSONValue? {
        guard let value else { return nil }
        switch value {
        case .string(let text):
            if let name = exactVariable(text) {
                guard let resolved = variables[name] else {
                    throw KazumiError.message("缺少模板变量 @\(name)")
                }
                return resolved
            }
            return .string(try renderTemplate(text, variables: variables, encode: false))
        case .array(let items):
            return .array(try items.map { try renderValue($0, variables: variables) ?? .null })
        case .object(let object):
            var rendered: [String: JSONValue] = [:]
            for (key, item) in object {
                rendered[key] = try renderValue(item, variables: variables)
            }
            return .object(rendered)
        default:
            return value
        }
    }

    private func exactVariable(_ text: String) -> String? {
        guard text.hasPrefix("@"), text.count > 1 else { return nil }
        let name = text.dropFirst()
        let scalars = Array(name)
        guard let first = scalars.first, first == "_" || first.isLetter else { return nil }
        for scalar in scalars.dropFirst() where !(scalar == "_" || scalar.isLetter || scalar.isNumber) {
            return nil
        }
        return String(name)
    }

    private func renderTemplate(_ template: String, variables: [String: JSONValue], encode: Bool) throws -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "@" {
                let previousIsIdent = index > template.startIndex && isIdent(template[template.index(before: index)])
                let nameStart = template.index(after: index)
                if !previousIsIdent, nameStart < template.endIndex, isIdentStart(template[nameStart]) {
                    var nameEnd = template.index(after: nameStart)
                    while nameEnd < template.endIndex, isIdent(template[nameEnd]) {
                        nameEnd = template.index(after: nameEnd)
                    }
                    let name = String(template[nameStart..<nameEnd])
                    guard let value = variables[name] else {
                        throw KazumiError.message("缺少模板变量 @\(name)")
                    }
                    let text = value.templateString
                    result += encode ? PercentEncoding.encodeComponent(text) : text
                    index = nameEnd
                    continue
                }
            }
            result.append(template[index])
            index = template.index(after: index)
        }
        return result
    }

    private func isIdentStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private func isIdent(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}
