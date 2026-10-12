// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

public enum RuleMode {
    public static let xpath = "xpath"
    public static let api = "api"

    public static func normalize(_ value: JSONValue?) -> String {
        value?.string == api ? api : xpath
    }
}

public enum APIBodyType {
    public static let none = "none"
    public static let json = "json"
    public static let form = "form"

    public static func normalize(_ value: JSONValue?) -> String {
        switch value?.string {
        case json: return json
        case form: return form
        default: return none
        }
    }
}

public enum APIChapterFormat {
    public static let nested = "nested"
    public static let delimited = "delimited"

    public static func normalize(_ value: JSONValue?) -> String {
        value?.string == delimited ? delimited : nested
    }
}

public enum CaptchaType {
    public static let image = 1
    public static let autoClick = 2
    public static let javascript = 3
}

public enum CaptchaDetectType {
    public static let xpath = 1
    public static let text = 2
    public static let regex = 3
}

public struct APIRequestConfig: Equatable, Sendable {
    public var method: String
    public var url: String
    public var headers: [String: JSONValue]
    public var query: [String: JSONValue]
    public var bodyType: String
    public var body: JSONValue?

    public init(
        method: String = "GET",
        url: String = "",
        headers: [String: JSONValue] = [:],
        query: [String: JSONValue] = [:],
        bodyType: String = APIBodyType.none,
        body: JSONValue? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.query = query
        self.bodyType = bodyType
        self.body = body
    }

    public static func from(_ json: JSONValue?) -> APIRequestConfig {
        guard let object = json?.object else { return APIRequestConfig() }
        let value = JSONValue.object(object)
        return APIRequestConfig(
            method: value.looseString("method", default: "GET").uppercased(),
            url: value.looseString("url"),
            headers: value.object("headers"),
            query: value.object("query"),
            bodyType: APIBodyType.normalize(value["bodyType"]),
            body: value["body"]
        )
    }

    public func jsonObject() -> JSONValue {
        var object: [String: JSONValue] = [
            "method": .string(method.uppercased()),
            "url": .string(url),
        ]
        if !headers.isEmpty { object["headers"] = .object(headers) }
        if !query.isEmpty { object["query"] = .object(query) }
        if bodyType != APIBodyType.none {
            object["bodyType"] = .string(bodyType)
            if let body { object["body"] = body }
        }
        return .object(object)
    }
}

public struct APISearchConfig: Equatable, Sendable {
    public var request: APIRequestConfig
    public var listPath: String
    public var namePath: String
    public var sourcePath: String

    public init(
        request: APIRequestConfig = APIRequestConfig(),
        listPath: String = "$.data[*]",
        namePath: String = "$.name",
        sourcePath: String = "$.url"
    ) {
        self.request = request
        self.listPath = listPath
        self.namePath = namePath
        self.sourcePath = sourcePath
    }

    public static func from(_ json: JSONValue?) -> APISearchConfig {
        guard let object = json?.object else { return APISearchConfig() }
        let value = JSONValue.object(object)
        return APISearchConfig(
            request: APIRequestConfig.from(value["request"]),
            listPath: value.looseString("listPath", default: "$.data[*]"),
            namePath: value.looseString("namePath", default: "$.name"),
            sourcePath: value.looseString("sourcePath", default: "$.url")
        )
    }

    public func jsonObject() -> JSONValue {
        .object([
            "request": request.jsonObject(),
            "listPath": .string(listPath),
            "namePath": .string(namePath),
            "sourcePath": .string(sourcePath),
        ])
    }
}

public struct APIEpisodePageConfig: Equatable, Sendable {
    public var url: String
    public var query: [String: JSONValue]

    public init(url: String = "", query: [String: JSONValue] = [:]) {
        self.url = url
        self.query = query
    }

    public static func from(_ json: JSONValue?) -> APIEpisodePageConfig? {
        guard let object = json?.object else { return nil }
        let value = JSONValue.object(object)
        return APIEpisodePageConfig(url: value.looseString("url"), query: value.object("query"))
    }

    public func jsonObject() -> JSONValue {
        .object([
            "url": .string(url),
            "query": .object(query),
        ])
    }
}

public struct APIChapterConfig: Equatable, Sendable {
    public var request: APIRequestConfig
    public var format: String
    public var roadsPath: String
    public var roadNamePath: String
    public var episodesPath: String
    public var episodeNamePath: String
    public var episodeURLPath: String
    public var roadNamesPath: String
    public var roadEpisodesPath: String
    public var roadSeparator: String
    public var episodeSeparator: String
    public var fieldSeparator: String
    public var variables: [String: String]
    public var episodePage: APIEpisodePageConfig?

    public init(
        request: APIRequestConfig = APIRequestConfig(),
        format: String = APIChapterFormat.nested,
        roadsPath: String = "$.data.roads[*]",
        roadNamePath: String = "$.name",
        episodesPath: String = "$.episodes[*]",
        episodeNamePath: String = "$.name",
        episodeURLPath: String = "$.url",
        roadNamesPath: String = "",
        roadEpisodesPath: String = "",
        roadSeparator: String = "$$$",
        episodeSeparator: String = "#",
        fieldSeparator: String = "$",
        variables: [String: String] = [:],
        episodePage: APIEpisodePageConfig? = nil
    ) {
        self.request = request
        self.format = format
        self.roadsPath = roadsPath
        self.roadNamePath = roadNamePath
        self.episodesPath = episodesPath
        self.episodeNamePath = episodeNamePath
        self.episodeURLPath = episodeURLPath
        self.roadNamesPath = roadNamesPath
        self.roadEpisodesPath = roadEpisodesPath
        self.roadSeparator = roadSeparator
        self.episodeSeparator = episodeSeparator
        self.fieldSeparator = fieldSeparator
        self.variables = variables
        self.episodePage = episodePage
    }

    public static func from(_ json: JSONValue?) -> APIChapterConfig {
        guard let object = json?.object else { return APIChapterConfig() }
        let value = JSONValue.object(object)
        var variables: [String: String] = [:]
        for (key, item) in value.object("variables") {
            variables[key] = item.templateString
        }
        return APIChapterConfig(
            request: APIRequestConfig.from(value["request"]),
            format: APIChapterFormat.normalize(value["format"]),
            roadsPath: value.looseString("roadsPath", default: "$.data.roads[*]"),
            roadNamePath: value.looseString("roadNamePath", default: "$.name"),
            episodesPath: value.looseString("episodesPath", default: "$.episodes[*]"),
            episodeNamePath: value.looseString("episodeNamePath", default: "$.name"),
            episodeURLPath: value.looseString("episodeUrlPath", default: "$.url"),
            roadNamesPath: value.looseString("roadNamesPath"),
            roadEpisodesPath: value.looseString("roadEpisodesPath"),
            roadSeparator: value.looseString("roadSeparator", default: "$$$"),
            episodeSeparator: value.looseString("episodeSeparator", default: "#"),
            fieldSeparator: value.looseString("fieldSeparator", default: "$"),
            variables: variables,
            episodePage: APIEpisodePageConfig.from(value["episodePage"])
        )
    }

    public func jsonObject() -> JSONValue {
        var object: [String: JSONValue] = [
            "request": request.jsonObject(),
            "format": .string(format),
        ]
        if format == APIChapterFormat.delimited || !roadNamesPath.isEmpty || !roadEpisodesPath.isEmpty {
            object["roadNamesPath"] = .string(roadNamesPath)
            object["roadEpisodesPath"] = .string(roadEpisodesPath)
            object["roadSeparator"] = .string(roadSeparator)
            object["episodeSeparator"] = .string(episodeSeparator)
            object["fieldSeparator"] = .string(fieldSeparator)
        }
        if format != APIChapterFormat.delimited
            || roadsPath != "$.data.roads[*]"
            || roadNamePath != "$.name"
            || episodesPath != "$.episodes[*]"
            || episodeNamePath != "$.name"
            || episodeURLPath != "$.url" {
            object["roadsPath"] = .string(roadsPath)
            object["roadNamePath"] = .string(roadNamePath)
            object["episodesPath"] = .string(episodesPath)
            object["episodeNamePath"] = .string(episodeNamePath)
            object["episodeUrlPath"] = .string(episodeURLPath)
        }
        if !variables.isEmpty {
            object["variables"] = .object(variables.mapValues { .string($0) })
        }
        if let episodePage {
            object["episodePage"] = episodePage.jsonObject()
        }
        return .object(object)
    }
}

public struct AntiCrawlerConfig: Equatable, Sendable {
    public var enabled: Bool
    public var captchaType: Int
    public var captchaImage: String
    public var captchaInput: String
    public var captchaButton: String
    public var captchaDetectType: Int
    public var captchaDetectValue: String
    public var captchaScript: String

    public static let empty = AntiCrawlerConfig(
        enabled: false,
        captchaType: CaptchaType.image,
        captchaImage: "",
        captchaInput: "",
        captchaButton: "",
        captchaDetectType: CaptchaDetectType.xpath,
        captchaDetectValue: "",
        captchaScript: ""
    )

    public init(
        enabled: Bool,
        captchaType: Int,
        captchaImage: String,
        captchaInput: String,
        captchaButton: String,
        captchaDetectType: Int,
        captchaDetectValue: String,
        captchaScript: String
    ) {
        self.enabled = enabled
        self.captchaType = captchaType
        self.captchaImage = captchaImage
        self.captchaInput = captchaInput
        self.captchaButton = captchaButton
        self.captchaDetectType = captchaDetectType
        self.captchaDetectValue = captchaDetectValue
        self.captchaScript = captchaScript
    }

    public static func from(_ json: JSONValue?) -> AntiCrawlerConfig {
        guard let object = json?.object else { return .empty }
        let value = JSONValue.object(object)
        return AntiCrawlerConfig(
            enabled: value.looseBool("enabled"),
            captchaType: value.looseInt("captchaType", default: CaptchaType.image),
            captchaImage: value.looseString("captchaImage"),
            captchaInput: value.looseString("captchaInput"),
            captchaButton: value.looseString("captchaButton"),
            captchaDetectType: value.looseInt("captchaDetectType", default: CaptchaDetectType.xpath),
            captchaDetectValue: value.looseString("captchaDetectValue"),
            captchaScript: value.looseString("captchaScript")
        )
    }

    public func jsonObject() -> JSONValue {
        .object([
            "enabled": .bool(enabled),
            "captchaType": .int(captchaType),
            "captchaImage": .string(captchaImage),
            "captchaInput": .string(captchaInput),
            "captchaButton": .string(captchaButton),
            "captchaDetectType": .int(captchaDetectType),
            "captchaDetectValue": .string(captchaDetectValue),
            "captchaScript": .string(captchaScript),
        ])
    }
}

/// A Kazumi plugin rule. Field names follow the Flutter JSON schema, including
/// the historical spelling `muliSources` and `baseURL`.
public struct PluginRule: Equatable, Sendable, Identifiable {
    public var api: String
    public var type: String
    public var name: String
    public var version: String
    public var author: String
    public var multiSources: Bool
    public var useWebview: Bool
    public var useNativePlayer: Bool
    public var usePost: Bool
    public var useLegacyParser: Bool
    public var adBlocker: Bool
    public var userAgent: String
    public var baseURL: String
    public var searchURL: String
    public var searchList: String
    public var searchName: String
    public var searchResult: String
    public var chapterRoads: String
    public var chapterResult: String
    public var referer: String
    public var searchMode: String
    public var chapterMode: String
    public var searchAPI: APISearchConfig
    public var chapterAPI: APIChapterConfig
    public var antiCrawler: AntiCrawlerConfig

    public var id: String { name.lowercased() }

    public static func blank() -> PluginRule {
        PluginRule(json: .object([
            "name": .string("新规则"),
            "api": .string("8"),
            "version": .string("1.0"),
            "baseURL": .string("https://"),
            "searchURL": .string("https://"),
            "searchMode": .string("xpath"),
            "chapterMode": .string("xpath"),
        ]))
    }

    public var requiresNewerClient: Bool {
        (Int(api) ?? 1) > KazumiCore.ruleAPILevel
    }

    public init(json: JSONValue) {
        api = json.looseString("api", default: "1")
        type = json.looseString("type", default: "anime")
        name = json.looseString("name")
        version = json.looseString("version")
        author = json.looseString("author")
        multiSources = json.looseBool("muliSources", default: true)
        useWebview = json.looseBool("useWebview", default: true)
        useNativePlayer = json.looseBool("useNativePlayer", default: true)
        usePost = json.looseBool("usePost")
        useLegacyParser = json.looseBool("useLegacyParser")
        adBlocker = json.looseBool("adBlocker")
        userAgent = json.looseString("userAgent")
        baseURL = json.looseString("baseURL")
        searchURL = json.looseString("searchURL")
        searchList = json.looseString("searchList")
        searchName = json.looseString("searchName")
        searchResult = json.looseString("searchResult")
        chapterRoads = json.looseString("chapterRoads")
        chapterResult = json.looseString("chapterResult")
        referer = json.looseString("referer")
        searchMode = RuleMode.normalize(json["searchMode"])
        chapterMode = RuleMode.normalize(json["chapterMode"])
        searchAPI = APISearchConfig.from(json["searchApiConfig"])
        chapterAPI = APIChapterConfig.from(json["chapterApiConfig"])
        antiCrawler = AntiCrawlerConfig.from(json["antiCrawlerConfig"])
    }

    public func jsonObject() -> JSONValue {
        var object: [String: JSONValue] = [
            "api": .string(api),
            "type": .string(type),
            "name": .string(name),
            "version": .string(version),
            "muliSources": .bool(multiSources),
            "useWebview": .bool(useWebview),
            "useNativePlayer": .bool(useNativePlayer),
            "usePost": .bool(usePost),
            "useLegacyParser": .bool(useLegacyParser),
            "adBlocker": .bool(adBlocker),
            "userAgent": .string(userAgent),
            "baseURL": .string(baseURL),
            "searchURL": .string(searchURL),
            "searchList": .string(searchList),
            "searchName": .string(searchName),
            "searchResult": .string(searchResult),
            "chapterRoads": .string(chapterRoads),
            "chapterResult": .string(chapterResult),
            "referer": .string(referer),
            "searchMode": .string(searchMode),
            "chapterMode": .string(chapterMode),
            "antiCrawlerConfig": antiCrawler.jsonObject(),
        ]
        if !author.isEmpty {
            object["author"] = .string(author)
        }
        if searchMode == RuleMode.api || !searchAPI.request.url.isEmpty {
            object["searchApiConfig"] = searchAPI.jsonObject()
        }
        if chapterMode == RuleMode.api || !chapterAPI.request.url.isEmpty {
            object["chapterApiConfig"] = chapterAPI.jsonObject()
        }
        return .object(object)
    }
}
