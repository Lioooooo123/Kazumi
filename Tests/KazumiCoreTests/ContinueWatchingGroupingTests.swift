import XCTest
@testable import KazumiCore

final class ContinueWatchingGroupingTests: XCTestCase {
    func testRuleOnlyEpisodesShareOneContinueWatchingCard() {
        let older = HistoryRecord(subjectID: 0, name: "番剧", nameCN: "", imageURL: "", episodeName: "01", pageURL: "https://site.example/1", position: 100, duration: 1400)
        var latest = older
        latest.id = "https://site.example/2"
        latest.pageURL = latest.id
        latest.episodeName = "02"
        XCTAssertEqual(ContinueWatching.select([latest, older]).map(\.pageURL), [latest.pageURL])
    }

    func testCompletedLatestEpisodeDoesNotReviveAnOlderEpisode() {
        let older = HistoryRecord(subjectID: 0, name: "番剧", nameCN: "", imageURL: "", episodeName: "01", pageURL: "https://site.example/1", position: 100, duration: 1400)
        var latest = older
        latest.id = "https://site.example/2"
        latest.pageURL = latest.id
        latest.position = 1400
        XCTAssertTrue(ContinueWatching.select([latest, older]).isEmpty)
    }
}
