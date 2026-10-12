import Foundation
import XCTest
@testable import KazumiCore

final class PlaybackRecoveryTests: XCTestCase {
    func testAPIRoadIdentifiersSurviveIdenticalEpisodePageURLs() throws {
        let rule = PluginRule(json: .object([
            "name": .string("test"), "baseURL": .string("https://site.example"), "chapterMode": .string("api"),
            "chapterApiConfig": .object(["roadsPath": .string("$.sources[*]"), "roadNamePath": .string("$.name"), "episodesPath": .string("$.episodes[*]"), "episodeNamePath": .string("$.title"), "episodeUrlPath": .string("$.url")])
        ]))
        let raw = #"{"sources":[{"id":1,"name":"A","episodes":[{"title":"01","url":"https://site.example/1"}]},{"id":8,"name":"B","episodes":[{"title":"01","url":"https://site.example/1"}]}]}"#
        let roads = try RuleEngine().parseChapters(rule: rule, raw: raw, source: "detail").roads
        XCTAssertEqual(roads.map(\.sourceID), ["1", "8"])
        XCTAssertNotEqual(roads[0].id, roads[1].id)
    }

    func testExtensionlessPlaylistIsRecognizedWithoutTreatingSegmentsAsVideos() {
        let url = URL(string: "https://cdn.example/play?id=1")!
        XCTAssertTrue(MediaSniffer.isMediaResponse(url: url, mimeType: "application/octet-stream", text: "\n#EXTM3U\n#EXTINF:6\npart.ts"))
        XCTAssertTrue(MediaSniffer.isMediaResponse(url: url, mimeType: "application/vnd.apple.mpegurl; charset=utf-8", text: ""))
        XCTAssertFalse(MediaSniffer.isMediaResponse(url: URL(string: "https://cdn.example/part.ts")!, mimeType: "video/mp2t", text: ""))
        XCTAssertFalse(MediaSniffer.isMediaResponse(url: url, mimeType: "text/html", text: "<script>const example = '#EXTM3U'</script>"))
    }

    func testRelativeAndProtocolRelativeVideoSourcesResolveAgainstThePage() {
        let html = #"<video src="/media/ep1.mp4?token=a&amp;b=2"></video><source src="//cdn.example/ep1.m3u8"><script src="/app.js"></script>"#
        XCTAssertEqual(MediaSniffer.mediaURLs(in: html, baseURL: URL(string: "https://site.example/watch/1")), [
            URL(string: "https://site.example/media/ep1.mp4?token=a&b=2")!,
            URL(string: "https://cdn.example/ep1.m3u8")!
        ])
    }

    func testHistoryPreservesSourceRoadsAndRequestConfiguration() throws {
        let roads = [PlaybackRoad(name: "主线", episodes: [EpisodeEntry(name: "01", url: "https://site.example/1"), EpisodeEntry(name: "02", url: "https://site.example/2")])]
        let context = PlaybackContext(ruleName: "rule", source: "detail/1", roadName: "主线", roads: roads, referer: "https://site.example/", userAgent: "Browser")
        let record = HistoryRecord(subjectID: 1, name: "番剧", nameCN: "", imageURL: "", episodeName: "01", pageURL: roads[0].episodes[0].url, position: 123, duration: 1400, playbackContext: context)
        let restored = try JSONDecoder().decode(HistoryRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.playbackContext, context)
        XCTAssertEqual(EpisodeSequence.next(after: restored.pageURL, in: restored.playbackContext!.episodes), roads[0].episodes[1])
    }

    func testOldHistoryStillDecodes() throws {
        let record = HistoryRecord(subjectID: 1, name: "番剧", nameCN: "", imageURL: "", episodeName: "01", pageURL: "https://site.example/1", position: 123, duration: 1400)
        let data = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(HistoryRecord.self, from: data)
        XCTAssertNil(restored.playbackContext)
    }

    func testRoadSwitchKeepsEpisodeNumberWhenTitlesDiffer() {
        let roads = [PlaybackRoad(name: "A", episodes: [EpisodeEntry(name: "第1集", url: "a1"), EpisodeEntry(name: "第2集", url: "a2")]), PlaybackRoad(name: "B", episodes: [EpisodeEntry(name: "EP01", url: "b1"), EpisodeEntry(name: "EP02", url: "b2")])]
        let context = PlaybackContext(ruleName: "rule", source: "detail", roadName: "A", roads: roads, referer: "", userAgent: "")
        XCTAssertEqual(context.episode(on: roads[1], replacing: "a2")?.url, "b2")
        XCTAssertNil(context.episode(on: PlaybackRoad(name: "empty", episodes: []), replacing: "a2"))
    }

    func testChapterRequestsCarryVerificationCookies() async throws {
        let transport = ChapterTransport()
        let rule = PluginRule(json: .object(["name": .string("test"), "baseURL": .string("https://site.example"), "chapterRoads": .string("//div"), "chapterResult": .string("//a"), "chapterTitle": .string("text()"), "chapterURL": .string("@href")]))
        _ = try? await RuleService(http: HTTPClient(transport: transport)).chapters(rule: rule, source: "https://site.example/detail", extraHeaders: ["Cookie": "verified=yes"])
        let request = await transport.request
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Cookie"), "verified=yes")
    }
}

private actor ChapterTransport: HTTPTransport {
    var request: URLRequest?
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (Data("<div><a href='/play/1'>01</a></div>".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
    }
}
