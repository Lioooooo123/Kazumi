// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import XCTest
@testable import KazumiCore

final class SHA256Tests: XCTestCase {
    func testEmptyAndABC() {
        XCTAssertEqual(SHA256.hex(SHA256.hash("")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(SHA256.hash("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testDandanSignatureIsStable() {
        let signature = DandanSignature.sign(appID: "app", secret: "secret", path: "/api/v2/comment/1", timestamp: 1_700_000_000)
        let material = "app1700000000/api/v2/comment/1secret"
        XCTAssertEqual(signature, SHA256.hash(material).base64EncodedString())
        XCTAssertFalse(signature.isEmpty)
    }
}

final class EpisodeURLTests: XCTestCase {
    func testResolvesRelativeAndStripsSlash() {
        XCTAssertEqual(
            normalizeEpisodeURL(baseURL: "https://example.com/app/", raw: "/play/1/"),
            "https://example.com/play/1"
        )
        XCTAssertEqual(
            normalizeEpisodeURL(baseURL: "https://example.com/base/", raw: "ep/2"),
            "https://example.com/base/ep/2"
        )
    }

    func testRewritesSameHostSchemeOnly() {
        XCTAssertEqual(
            normalizeEpisodeURL(baseURL: "https://example.com/", raw: "http://example.com/a/"),
            "https://example.com/a"
        )
        XCTAssertEqual(
            normalizeEpisodeURL(baseURL: "https://example.com/", raw: "http://cdn.example/a"),
            "http://cdn.example/a"
        )
    }

    func testEmptyAndIdempotent() {
        XCTAssertEqual(normalizeEpisodeURL(baseURL: "https://example.com/", raw: "  "), "")
        let once = normalizeEpisodeURL(baseURL: "https://example.com/", raw: "/watch/3/")
        XCTAssertEqual(normalizeEpisodeURL(baseURL: "https://example.com/", raw: once), once)
    }
}

final class XPathRuleTests: XCTestCase {
    func testSearchAndChapters() throws {
        let html = """
        <html><body>
          <div class="item"><a href="/bangumi/1" title="进击的巨人">进击的巨人</a></div>
          <div class="item active"><a href="https://cdn.example/bangumi/2">紫罗兰</a></div>
          <div class="road"><a href="/play/1">第 1 集</a><a href="/play/2">第2集</a></div>
        </body></html>
        """
        let rule = sampleRule()
        let engine = RuleEngine()
        let search = try engine.parseSearch(rule: rule, raw: html)
        XCTAssertEqual(search.items.map(\.name), ["进击的巨人", "紫罗兰"])
        XCTAssertEqual(search.items.map(\.source), ["/bangumi/1", "https://cdn.example/bangumi/2"])

        let chapters = try engine.parseChapters(rule: rule, raw: html, source: "https://example.com/bangumi/1")
        XCTAssertEqual(chapters.roads.count, 1)
        XCTAssertEqual(chapters.roads[0].episodes.map(\.name), ["第1集", "第2集"])
        XCTAssertEqual(chapters.roads[0].episodes[0].url, "https://example.com/play/1")
    }

    func testContainsClassAndKeywordEncoding() throws {
        let rule = sampleRule()
        let engine = RuleEngine()
        let request = try engine.prepareSearch(rule: rule, keyword: "进击 巨人")
        XCTAssertTrue(request.url.contains("%E8%BF%9B%E5%87%BB"))
        XCTAssertTrue(request.url.contains("+") || request.url.contains("%20"))
        XCTAssertEqual(request.method, "GET")
    }

    func testCaptchaText() throws {
        var rule = sampleRule()
        rule.antiCrawler = AntiCrawlerConfig(
            enabled: true,
            captchaType: 1,
            captchaImage: "",
            captchaInput: "",
            captchaButton: "",
            captchaDetectType: CaptchaDetectType.text,
            captchaDetectValue: "请输入验证码",
            captchaScript: ""
        )
        XCTAssertThrowsError(try RuleEngine().parseSearch(rule: rule, raw: "<html>请输入验证码</html>")) { error in
            guard case KazumiError.captchaRequired = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testPostSearchSplitsQuery() throws {
        var rule = sampleRule()
        rule.usePost = true
        let request = try RuleEngine().prepareSearch(rule: rule, keyword: "abc")
        XCTAssertEqual(request.method, "POST")
        XCTAssertFalse(request.url.contains("?"))
        XCTAssertEqual(request.bodyType, APIBodyType.form)
    }

    private func sampleRule() -> PluginRule {
        let json = """
        {"api":"8","name":"Demo","baseURL":"https://example.com/","searchURL":"https://example.com/search?q=@keyword","searchList":"//div[contains(@class,'item')]","searchName":"//a/text()","searchResult":"//a","chapterRoads":"//div[@class='road']","chapterResult":"//a"}
        """
        return PluginRule(json: try! JSONValue.parse(json))
    }
}

final class APIRuleTests: XCTestCase {
    func testJSONPathAndNestedChapters() throws {
        XCTAssertEqual(try JSONPath.read(try JSONValue.parse(#"{"data":[{"name":"A"}]}"#), "$.data[*].name").map(\.fieldString), ["A"])
        let rule = PluginRule(json: try JSONValue.parse("""
        {
          "name": "API",
          "searchMode": "api",
          "chapterMode": "api",
          "baseURL": "https://example.com/",
          "searchApiConfig": {
            "request": {"method":"GET","url":"https://example.com/search?wd=@keyword"},
            "listPath": "$.data[*]",
            "namePath": "$.name",
            "sourcePath": "$.url"
          },
          "chapterApiConfig": {
            "request": {"method":"GET","url":"https://example.com/detail?url=@source"},
            "roadsPath": "$.roads[*]",
            "roadNamePath": "$.name",
            "episodesPath": "$.episodes[*]",
            "episodeNamePath": "$.name",
            "episodeUrlPath": "$.id",
            "episodePage": {"url":"https://example.com/play/@episodeUrl/@episodeNumber","query":{"ep":"@episodeNumber"}}
          }
        }
        """))
        let engine = RuleEngine()
        let request = try engine.prepareSearch(rule: rule, keyword: "a b")
        XCTAssertTrue(request.url.contains("a%20b"))
        let search = try engine.parseSearch(rule: rule, raw: #"{"data":[{"name":"葬送的芙莉莲","url":"/frieren"}]}"#)
        XCTAssertEqual(search.items, [SearchHit(name: "葬送的芙莉莲", source: "/frieren")])
        let chapters = try engine.parseChapters(
            rule: rule,
            raw: #"{"roads":[{"name":"线路A","episodes":[{"name":"第一话","id":"99"}]}]}"#,
            source: "/frieren"
        )
        XCTAssertEqual(chapters.roads[0].name, "线路A")
        XCTAssertTrue(chapters.roads[0].episodes[0].url.contains("/play/99/1"))
        XCTAssertTrue(chapters.roads[0].episodes[0].url.contains("ep=1"))
    }

    func testDelimitedChapters() throws {
        let rule = PluginRule(json: try JSONValue.parse("""
        {
          "name":"Delim",
          "chapterMode":"api",
          "baseURL":"https://example.com/",
          "chapterApiConfig":{
            "request":{"url":"https://example.com/api"},
            "format":"delimited",
            "roadNamesPath":"$.from",
            "roadEpisodesPath":"$.url",
            "roadSeparator":"$$$",
            "episodeSeparator":"#",
            "fieldSeparator":"$"
          }
        }
        """))
        let raw = #"{"from":"线1$$$线2","url":"第1集$https://cdn.example/1.m3u8#第2集$https://cdn.example/2.mp4$$$第1集$https://cdn.example/b.mp4"}"#
        let chapters = try RuleEngine().parseChapters(rule: rule, raw: raw, source: "x")
        XCTAssertEqual(chapters.roads.map(\.name), ["线1", "线2"])
        XCTAssertEqual(chapters.roads[0].episodes.count, 2)
        XCTAssertEqual(chapters.roads[1].episodes[0].url, "https://cdn.example/b.mp4")
    }

    func testRejectsFilters() {
        XCTAssertThrowsError(try JSONPath.validate("$.data[?(@.a)]"))
    }
}

final class PluginImportTests: XCTestCase {
    func testJSONAndShareLinkRoundTrip() throws {
        let json = """
        [{"api":8,"name":"示例规则","version":"1","baseURL":"https://example.com/","searchURL":"https://example.com/?k=@keyword","searchList":"//div","searchName":"//a","searchResult":"//a/@href","chapterRoads":"//ul","chapterResult":"//li/a","muliSources":true}]
        """
        let parsed = PluginImporter.parse(json)
        XCTAssertEqual(parsed.failureCount, 0)
        XCTAssertEqual(parsed.plugins.count, 1)
        XCTAssertEqual(parsed.plugins[0].api, "8")
        XCTAssertTrue(parsed.plugins[0].multiSources)
        let link = try PluginImporter.exportLink(parsed.plugins[0])
        XCTAssertTrue(link.hasPrefix("kazumi://"))
        let again = PluginImporter.parse("请看规则 \(link) 谢谢")
        XCTAssertEqual(again.plugins.map(\.name), ["示例规则"])
    }

    func testRejectsFutureAPILevel() {
        let result = PluginImporter.parse(#"{"name":"新","api":"99"}"#)
        XCTAssertTrue(result.plugins.isEmpty)
        XCTAssertFalse(result.failures.isEmpty)
    }
}

final class BangumiModelTests: XCTestCase {
    func testSubjectParsing() throws {
        let json = try JSONValue.parse("""
        {
          "id": 8,
          "name": "Code Geass",
          "name_cn": "反叛的鲁路修",
          "summary": "简介",
          "date": "2006-10-06",
          "rating": {"rank": 10, "score": 8.6, "total": 100},
          "images": {"large": "https://example.com/cover.jpg"},
          "tags": [{"name": "机战", "count": 3}],
          "infobox": [{"key": "别名", "value": [{"v": "Code Geass"}]}],
          "eps": 25
        }
        """)
        let subject = try BangumiSubject(json: json)
        XCTAssertEqual(subject.displayName, "反叛的鲁路修")
        XCTAssertEqual(subject.score, 8.6, accuracy: 0.001)
        XCTAssertEqual(subject.coverURL, "https://example.com/cover.jpg")
        XCTAssertEqual(subject.aliases, ["Code Geass"])
        XCTAssertEqual(subject.episodeCount, 25)
        XCTAssertEqual(subject.airWeekday, 5)
        XCTAssertEqual(AnimeCalendar.seasonName(month: 10), "秋")
        XCTAssertEqual(AnimeCalendar.seasonRange(year: 2006, month: 10).start, "2006-10-01")
    }

    func testCalendarGroupingShape() throws {
        let json = try JSONValue.parse(#"{"1":[{"subject":{"id":1,"name":"A","name_cn":"甲","date":"2024-01-01"}}]}"#)
        let list = BangumiSubject.list(from: json["1"] ?? .null)
        XCTAssertEqual(list.map(\.displayName), ["甲"])
    }
}

final class DanmakuTests: XCTestCase {
    func testCommentAndMatching() throws {
        let json = try JSONValue.parse(#"{"m":"好看","p":"12.5,1,16777215,bilibili"}"#)
        let comment = DanmakuComment(json: json, id: 3)
        XCTAssertEqual(comment?.time, 12.5)
        XCTAssertEqual(comment?.colorRGB, 16_777_215)
        XCTAssertTrue(comment?.isScroll == true)
        let animes = [
            DanmakuAnime(id: 1, title: "其他"),
            DanmakuAnime(id: 2, title: "葬送的芙莉莲"),
        ]
        XCTAssertEqual(DanmakuMatching.bestAnime(title: "芙莉莲", candidates: animes)?.id, 2)
        XCTAssertEqual(DanmakuMatching.episodeNumber(from: "第12话"), 12)
        let merged = DanmakuMatching.mergeDuplicates([
            DanmakuComment(id: 1, time: 1, mode: 1, colorRGB: 1, message: "草", source: "a"),
            DanmakuComment(id: 2, time: 1.2, mode: 1, colorRGB: 1, message: "草", source: "a"),
        ])
        XCTAssertEqual(merged.first?.message, "草 x2")
        XCTAssertEqual(merged.first?.mode, 5)
        XCTAssertTrue(DanmakuMatching.blocked(
            DanmakuComment(time: 0, mode: 1, colorRGB: 0, message: "广告来了", source: ""),
            shield: ["广告"]
        ))
    }
}

final class LibraryAndSnifferTests: XCTestCase {
    func testLibraryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LibraryStore(directory: directory)
        let rule = PluginRule(json: try JSONValue.parse(#"{"name":"本地","api":"8","baseURL":"https://example.com/"}"#))
        var snapshot = LibrarySnapshot.empty
        snapshot.rules = [InstalledRule(enabled: false, plugin: rule)]
        snapshot.settings.themeMode = "dark"
        snapshot.settings.dandanAppID = "id"
        let subject = try BangumiSubject(json: try JSONValue.parse(#"{"id":3,"name":"N","name_cn":"中文名"}"#))
        snapshot.favorites = [FavoriteRecord(subject: subject, addedAt: Date(timeIntervalSince1970: 1_700_000_000))]
        snapshot.history = [HistoryRecord(
            subjectID: 3, name: "N", nameCN: "中文名", imageURL: "", episodeName: "第1集",
            pageURL: "https://example.com/1", position: 12, duration: 24,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )]
        try store.save(snapshot)
        let loaded = try store.load()
        XCTAssertEqual(loaded.rules.first?.plugin.name, "本地")
        XCTAssertEqual(loaded.rules.first?.enabled, false)
        XCTAssertEqual(loaded.settings.themeMode, "dark")
        XCTAssertEqual(loaded.favorites.first?.displayName, "中文名")
        XCTAssertEqual(loaded.history.first?.progress ?? 0, 0.5, accuracy: 0.001)
        try? FileManager.default.removeItem(at: directory)
    }

    func testImageCacheAndSniffer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = ImageDiskCache(directory: directory, maxBytes: 1024 * 1024)
        let url = URL(string: "https://example.com/a.jpg")!
        let data = try await cache.fetch(url) { Data("image".utf8) }
        let again = await cache.data(for: url)
        XCTAssertEqual(data, again)
        let found = MediaSniffer.mediaURLs(
            in: #"var u=\"https:\\/\\/cdn.example\\/a.m3u8\"; var b='https://cdn.example/b.mp4?x=1';"#,
            baseURL: nil
        )
        XCTAssertEqual(found.map(\.path), ["/a.m3u8", "/b.mp4"])
        XCTAssertTrue(MediaSniffer.isDirect(URL(string: "https://cdn.example/master.m3u8?token=1")!))
        try? FileManager.default.removeItem(at: directory)
    }

    func testPrefetchSkipsCachedURLs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = ImageDiskCache(directory: directory, maxBytes: 1024 * 1024)
        let url = URL(string: "https://example.com/cover.jpg")!
        let loads = LoadCounter()
        await cache.prefetch([url, url]) { _ in
            loads.add()
            return Data("cover".utf8)
        }
        await cache.prefetch([url]) { _ in
            loads.add()
            return Data("other".utf8)
        }
        let stored = await cache.data(for: url)
        XCTAssertEqual(stored, Data("cover".utf8))
        XCTAssertEqual(loads.value, 1)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func add() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

final class PlaybackFlowTests: XCTestCase {
    func testTimelineLineMatchesFlutterCard() {
        XCTAssertEqual(
            CatalogText.timelineLine(
                title: "甲",
                info: "12话 / 完结",
                metaTags: [],
                tagNames: ["奇幻", "奇幻", "热血"],
                originalName: "A"
            ),
            "12 话 · 奇幻 · 热血"
        )
        XCTAssertEqual(
            CatalogText.timelineLine(title: "甲", info: "第12话", metaTags: [], tagNames: [], originalName: "A"),
            "A"
        )
        XCTAssertEqual(
            CatalogText.timelineLine(title: "甲", info: "", metaTags: [], tagNames: [], originalName: "甲"),
            ""
        )
    }

    func testResumeSkipsOpeningSecondAndCredits() {
        XCTAssertEqual(PlaybackResume.position(saved: 30, savedDuration: 100, mediaDuration: 0), 30)
        XCTAssertNil(PlaybackResume.position(saved: 0.4, savedDuration: 100, mediaDuration: 100))
        XCTAssertNil(PlaybackResume.position(saved: 96, savedDuration: 100, mediaDuration: 100))
        XCTAssertNil(PlaybackResume.position(saved: 40, savedDuration: 50, mediaDuration: 42))
        XCTAssertEqual(PlaybackResume.position(saved: 20, savedDuration: 0, mediaDuration: 90), 20)
    }

    func testNextEpisodeAndContinueWatching() {
        let episodes = [
            EpisodeEntry(name: "1", url: "https://example.com/1"),
            EpisodeEntry(name: "2", url: "https://example.com/2"),
        ]
        XCTAssertEqual(EpisodeSequence.next(after: "https://example.com/1", in: episodes)?.name, "2")
        XCTAssertNil(EpisodeSequence.next(after: "https://example.com/2", in: episodes))
        let history = [
            HistoryRecord(subjectID: 1, name: "A", nameCN: "甲", imageURL: "", episodeName: "2", pageURL: "b", position: 10, duration: 100),
            HistoryRecord(subjectID: 1, name: "A", nameCN: "甲", imageURL: "", episodeName: "1", pageURL: "a", position: 3, duration: 100),
            HistoryRecord(subjectID: 2, name: "B", nameCN: "乙", imageURL: "", episodeName: "1", pageURL: "c", position: 99, duration: 100),
            HistoryRecord(subjectID: 0, name: "C", nameCN: "", imageURL: "", episodeName: "3", pageURL: "d", position: 8, duration: 40),
        ]
        let picked = ContinueWatching.select(history)
        XCTAssertEqual(picked.map(\.pageURL), ["b", "d"])
    }

    func testDanmakuLanesAvoidOverlap() {
        let comments = [
            DanmakuComment(id: 1, time: 0, mode: 1, colorRGB: 1, message: "a", source: ""),
            DanmakuComment(id: 2, time: 0.2, mode: 1, colorRGB: 1, message: "b", source: ""),
            DanmakuComment(id: 3, time: 7, mode: 1, colorRGB: 1, message: "c", source: ""),
            DanmakuComment(id: 4, time: 1, mode: 5, colorRGB: 1, message: "top", source: ""),
            DanmakuComment(id: 5, time: 1, mode: 1, colorRGB: 1, message: "广告", source: ""),
        ]
        let placed = DanmakuLanes.assign(comments: comments, at: 1.5, travel: 8, laneCount: 4, shield: ["广告"])
        let lanes = Dictionary(uniqueKeysWithValues: placed.map { ($0.comment.id, $0.lane) })
        XCTAssertNil(lanes[5])
        XCTAssertNotEqual(lanes[1], lanes[2])
        XCTAssertEqual(lanes[4], 1)
        let later = DanmakuLanes.assign(comments: comments, at: 8, travel: 8, laneCount: 4, shield: [])
        XCTAssertEqual(later.first { $0.comment.id == 3 }?.lane, 0)
    }
}
