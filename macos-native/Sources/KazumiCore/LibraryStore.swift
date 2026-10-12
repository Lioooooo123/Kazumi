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
        showRating: true
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
        showRating: Bool
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
