// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation

public struct InstalledRule: Equatable, Sendable, Identifiable, Codable {
    public var enabled: Bool
    public var plugin: PluginRule

    public var id: String { plugin.id }

    public init(enabled: Bool = true, plugin: PluginRule) {
        self.enabled = enabled
        self.plugin = plugin
    }
}

public struct FavoriteRecord: Equatable, Sendable, Identifiable, Codable {
    public var subjectID: Int
    public var name: String
    public var nameCN: String
    public var imageURL: String
    public var summary: String
    public var addedAt: Date

    public var id: Int { subjectID }
    public var displayName: String { nameCN.isEmpty ? name : nameCN }

    public init(subject: BangumiSubject, addedAt: Date = Date()) {
        subjectID = subject.id
        name = subject.name
        nameCN = subject.nameCN
        imageURL = subject.coverURL
        summary = subject.summary
        self.addedAt = addedAt
    }
}

public struct HistoryRecord: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var subjectID: Int
    public var name: String
    public var nameCN: String
    public var imageURL: String
    public var episodeName: String
    public var pageURL: String
    public var position: Double
    public var duration: Double
    public var updatedAt: Date

    public var displayName: String { nameCN.isEmpty ? name : nameCN }
    public var progress: Double {
        guard duration > 1 else { return 0 }
        return min(1, max(0, position / duration))
    }

    public init(
        subjectID: Int,
        name: String,
        nameCN: String,
        imageURL: String,
        episodeName: String,
        pageURL: String,
        position: Double,
        duration: Double,
        updatedAt: Date = Date()
    ) {
        self.id = pageURL
        self.subjectID = subjectID
        self.name = name
        self.nameCN = nameCN
        self.imageURL = imageURL
        self.episodeName = episodeName
        self.pageURL = pageURL
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }
}

public struct AppSettings: Equatable, Sendable, Codable {
    public var themeMode: String
    public var accent: String
    public var danmakuEnabled: Bool
    public var danmakuOpacity: Double
    public var danmakuFontSize: Double
    public var danmakuDuration: Double
    public var danmakuShield: [String]
    public var playbackRate: Double
    public var dandanAppID: String
    public var dandanAppSecret: String
    public var showRating: Bool
    /// Flutter `SettingsKeys.enableGitProxy`: fetch the rule index from the mirror.
    public var useRuleMirror: Bool
    public var oled: Bool
    public var superResolution: Int
    public var externalPlayer: String
    public var webDavURL: String
    public var webDavUsername: String
    public var webDavPassword: String
    public var webDavEnabled: Bool
    public var bangumiToken: String
    public var proxyEnabled: Bool
    public var proxyHost: String
    public var proxyPort: Int
    public var downloadParallel: Int
    public var saveDanmakuWithDownload: Bool
    public var deviceID: String
    public var syncplayHost: String
    public var syncplayPort: Int
    public var syncplayTLS: Bool

    public static let `default` = AppSettings(
        themeMode: "system",
        accent: "green",
        danmakuEnabled: true,
        danmakuOpacity: 0.92,
        danmakuFontSize: 18,
        danmakuDuration: 8,
        danmakuShield: [],
        playbackRate: 1,
        dandanAppID: "",
        dandanAppSecret: "",
        showRating: true,
        useRuleMirror: false,
        oled: false,
        superResolution: SuperResolutionMode.off.rawValue,
        externalPlayer: "",
        webDavURL: "",
        webDavUsername: "",
        webDavPassword: "",
        webDavEnabled: false,
        bangumiToken: "",
        proxyEnabled: false,
        proxyHost: "",
        proxyPort: 7890,
        downloadParallel: 3,
        saveDanmakuWithDownload: false,
        deviceID: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
        syncplayHost: SyncPlayCodec.defaultHost,
        syncplayPort: SyncPlayCodec.defaultPort,
        syncplayTLS: false
    )

    public init(
        themeMode: String,
        accent: String,
        danmakuEnabled: Bool,
        danmakuOpacity: Double,
        danmakuFontSize: Double,
        danmakuDuration: Double,
        danmakuShield: [String],
        playbackRate: Double,
        dandanAppID: String,
        dandanAppSecret: String,
        showRating: Bool,
        useRuleMirror: Bool = false,
        oled: Bool = false,
        superResolution: Int = SuperResolutionMode.off.rawValue,
        externalPlayer: String = "",
        webDavURL: String = "",
        webDavUsername: String = "",
        webDavPassword: String = "",
        webDavEnabled: Bool = false,
        bangumiToken: String = "",
        proxyEnabled: Bool = false,
        proxyHost: String = "",
        proxyPort: Int = 7890,
        downloadParallel: Int = 3,
        saveDanmakuWithDownload: Bool = false,
        deviceID: String = "",
        syncplayHost: String = SyncPlayCodec.defaultHost,
        syncplayPort: Int = SyncPlayCodec.defaultPort,
        syncplayTLS: Bool = false
    ) {
        self.themeMode = themeMode
        self.accent = accent
        self.danmakuEnabled = danmakuEnabled
        self.danmakuOpacity = danmakuOpacity
        self.danmakuFontSize = danmakuFontSize
        self.danmakuDuration = danmakuDuration
        self.danmakuShield = danmakuShield
        self.playbackRate = playbackRate
        self.dandanAppID = dandanAppID
        self.dandanAppSecret = dandanAppSecret
        self.showRating = showRating
        self.useRuleMirror = useRuleMirror
        self.oled = oled
        self.superResolution = superResolution
        self.externalPlayer = externalPlayer
        self.webDavURL = webDavURL
        self.webDavUsername = webDavUsername
        self.webDavPassword = webDavPassword
        self.webDavEnabled = webDavEnabled
        self.bangumiToken = bangumiToken
        self.proxyEnabled = proxyEnabled
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.downloadParallel = downloadParallel
        self.saveDanmakuWithDownload = saveDanmakuWithDownload
        self.deviceID = deviceID.isEmpty
            ? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            : deviceID
        self.syncplayHost = syncplayHost
        self.syncplayPort = syncplayPort
        self.syncplayTLS = syncplayTLS
    }

    private enum CodingKeys: String, CodingKey {
        case themeMode, accent, danmakuEnabled, danmakuOpacity, danmakuFontSize
        case danmakuDuration, danmakuShield, playbackRate, dandanAppID, dandanAppSecret
        case showRating, useRuleMirror, oled, superResolution, externalPlayer
        case webDavURL, webDavUsername, webDavPassword, webDavEnabled, bangumiToken
        case proxyEnabled, proxyHost, proxyPort, downloadParallel, saveDanmakuWithDownload
        case deviceID, syncplayHost, syncplayPort, syncplayTLS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeMode = try container.decodeIfPresent(String.self, forKey: .themeMode) ?? "system"
        accent = try container.decodeIfPresent(String.self, forKey: .accent) ?? "green"
        danmakuEnabled = try container.decodeIfPresent(Bool.self, forKey: .danmakuEnabled) ?? true
        danmakuOpacity = try container.decodeIfPresent(Double.self, forKey: .danmakuOpacity) ?? 0.92
        danmakuFontSize = try container.decodeIfPresent(Double.self, forKey: .danmakuFontSize) ?? 18
        danmakuDuration = try container.decodeIfPresent(Double.self, forKey: .danmakuDuration) ?? 8
        danmakuShield = try container.decodeIfPresent([String].self, forKey: .danmakuShield) ?? []
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1
        dandanAppID = try container.decodeIfPresent(String.self, forKey: .dandanAppID) ?? ""
        dandanAppSecret = try container.decodeIfPresent(String.self, forKey: .dandanAppSecret) ?? ""
        showRating = try container.decodeIfPresent(Bool.self, forKey: .showRating) ?? true
        useRuleMirror = try container.decodeIfPresent(Bool.self, forKey: .useRuleMirror) ?? false
        oled = try container.decodeIfPresent(Bool.self, forKey: .oled) ?? false
        superResolution = try container.decodeIfPresent(Int.self, forKey: .superResolution) ?? SuperResolutionMode.off.rawValue
        externalPlayer = try container.decodeIfPresent(String.self, forKey: .externalPlayer) ?? ""
        webDavURL = try container.decodeIfPresent(String.self, forKey: .webDavURL) ?? ""
        webDavUsername = try container.decodeIfPresent(String.self, forKey: .webDavUsername) ?? ""
        webDavPassword = try container.decodeIfPresent(String.self, forKey: .webDavPassword) ?? ""
        webDavEnabled = try container.decodeIfPresent(Bool.self, forKey: .webDavEnabled) ?? false
        bangumiToken = try container.decodeIfPresent(String.self, forKey: .bangumiToken) ?? ""
        proxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .proxyEnabled) ?? false
        proxyHost = try container.decodeIfPresent(String.self, forKey: .proxyHost) ?? ""
        proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort) ?? 7890
        downloadParallel = try container.decodeIfPresent(Int.self, forKey: .downloadParallel) ?? 3
        saveDanmakuWithDownload = try container.decodeIfPresent(Bool.self, forKey: .saveDanmakuWithDownload) ?? false
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        syncplayHost = try container.decodeIfPresent(String.self, forKey: .syncplayHost) ?? SyncPlayCodec.defaultHost
        syncplayPort = try container.decodeIfPresent(Int.self, forKey: .syncplayPort) ?? SyncPlayCodec.defaultPort
        syncplayTLS = try container.decodeIfPresent(Bool.self, forKey: .syncplayTLS) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(themeMode, forKey: .themeMode)
        try container.encode(accent, forKey: .accent)
        try container.encode(danmakuEnabled, forKey: .danmakuEnabled)
        try container.encode(danmakuOpacity, forKey: .danmakuOpacity)
        try container.encode(danmakuFontSize, forKey: .danmakuFontSize)
        try container.encode(danmakuDuration, forKey: .danmakuDuration)
        try container.encode(danmakuShield, forKey: .danmakuShield)
        try container.encode(playbackRate, forKey: .playbackRate)
        try container.encode(dandanAppID, forKey: .dandanAppID)
        try container.encode(dandanAppSecret, forKey: .dandanAppSecret)
        try container.encode(showRating, forKey: .showRating)
        try container.encode(useRuleMirror, forKey: .useRuleMirror)
        try container.encode(oled, forKey: .oled)
        try container.encode(superResolution, forKey: .superResolution)
        try container.encode(externalPlayer, forKey: .externalPlayer)
        try container.encode(webDavURL, forKey: .webDavURL)
        try container.encode(webDavUsername, forKey: .webDavUsername)
        try container.encode(webDavPassword, forKey: .webDavPassword)
        try container.encode(webDavEnabled, forKey: .webDavEnabled)
        try container.encode(bangumiToken, forKey: .bangumiToken)
        try container.encode(proxyEnabled, forKey: .proxyEnabled)
        try container.encode(proxyHost, forKey: .proxyHost)
        try container.encode(proxyPort, forKey: .proxyPort)
        try container.encode(downloadParallel, forKey: .downloadParallel)
        try container.encode(saveDanmakuWithDownload, forKey: .saveDanmakuWithDownload)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(syncplayHost, forKey: .syncplayHost)
        try container.encode(syncplayPort, forKey: .syncplayPort)
        try container.encode(syncplayTLS, forKey: .syncplayTLS)
    }
}

public struct LibrarySnapshot: Equatable, Sendable, Codable {
    public var rules: [InstalledRule]
    public var favorites: [FavoriteRecord]
    public var history: [HistoryRecord]
    public var settings: AppSettings

    public static let empty = LibrarySnapshot(rules: [], favorites: [], history: [], settings: .default)

    public init(rules: [InstalledRule], favorites: [FavoriteRecord], history: [HistoryRecord], settings: AppSettings) {
        self.rules = rules
        self.favorites = favorites
        self.history = history
        self.settings = settings
    }
}

public final class LibraryStore: @unchecked Sendable {
    public let directory: URL
    private let file: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        self.file = directory.appendingPathComponent("library.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else { return .empty }
        let data = try Data(contentsOf: file)
        return try decoder.decode(LibrarySnapshot.self, from: data)
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: file, options: .atomic)
    }
}

extension PluginRule: Codable {
    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try jsonObject().encode(to: encoder)
    }
}
