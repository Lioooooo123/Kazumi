import Foundation
import XCTest
@testable import KazumiCore

final class MediaSnifferTests: XCTestCase {
    func testLegacyResourcesAreNotPlaybackCandidates() {
        for path in ["app.js", "style.css", "poster.jpg", "player.html", "segment.ts"] {
            XCTAssertFalse(LegacySniff.accepts("https://cdn.example/\(path)"), path)
        }
        XCTAssertTrue(LegacySniff.accepts("https://cdn.example/master.m3u8?token=abc"))
        XCTAssertTrue(LegacySniff.accepts("//cdn.example/episode.mp4"))
        XCTAssertFalse(LegacySniff.accepts("https://googleads.example/advert.mp4"))
    }

    func testAPlayerPageWithAMediaQueryIsNotDirectMedia() {
        XCTAssertFalse(MediaSniffer.isDirect(URL(string: "https://player.example/embed.html?url=https://cdn.example/master.m3u8")!))
        XCTAssertFalse(MediaSniffer.isDirect(URL(string: "https://cdn.example/app.js?next=episode.m3u8")!))
        XCTAssertTrue(MediaSniffer.isDirect(URL(string: "https://cdn.example/master.m3u8?token=abc")!))
        XCTAssertTrue(MediaSniffer.isDirect(URL(string: "https://cdn.example/episode.mp4")!))
    }

    func testEmbeddedPlayerURLsDoNotReplaceTheirMediaURLs() {
        let html = #"<iframe src="https://player.example/embed.html?url=https://cdn.example/master.m3u8"></iframe><script src="https://cdn.example/app.js"></script>"#
        XCTAssertEqual(MediaSniffer.mediaURLs(in: html, baseURL: URL(string: "https://site.example/episode")), [URL(string: "https://cdn.example/master.m3u8")!])
    }
}
