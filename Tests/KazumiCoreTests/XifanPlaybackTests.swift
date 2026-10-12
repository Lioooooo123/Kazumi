import Foundation
import XCTest
@testable import KazumiCore

final class XifanPlaybackTests: XCTestCase {
    func testSelectedRoadOverridesTheWebPagesDefaultSource() async throws {
        let transport = PlaybackFixtureTransport(response: response(source: 8))
        let result = try await XifanPlaybackService(http: HTTPClient(transport: transport)).resolve(page: firstPage, html: html(), rule: rule(), userAgent: "", selectedSourceID: 8)
        XCTAssertEqual(result?.absoluteString, signedMedia)
        let requests = await transport.requests
        let body = try JSONValue.parse(XCTUnwrap(requests.first?.httpBody))
        XCTAssertEqual(body["source_id"]?.int, 8)
    }

    private let firstPage = URL(string: "https://next.xifanacg.com/anime/3432/play/203775")!
    private let signedMedia = "https://media.example/student01.mp4?sign=fixture&t=1999999999"

    private func rule(apiHost: String = "api.xifanacg.com") -> PluginRule {
        PluginRule(json: .object([
            "name": .string("xfdmnext"), "baseURL": .string("https://next.xifanacg.com/"),
            "useLegacyParser": .bool(false),
            "chapterApiConfig": .object(["request": .object([
                "url": .string("https://\(apiHost)/rest/v1/rpc/get_anime_detail"),
                "headers": .object(["apikey": .string("public-fixture"), "Authorization": .string("Bearer public-fixture")])
            ])])
        ]))
    }

    private func html(episode: Int = 203775, source: Int = 1) throws -> String {
        let props: JSONValue = .object(["episodeId": .int(episode), "animeId": .int(3432), "initialSourceId": .int(source)])
        // Same nested React Flight shape as the episode page; unrelated props
        // deliberately precede the requested player, so a first-number regex fails.
        let tree: JSONValue = .array([.object(["episodeId": .int(10), "animeId": .int(20), "initialSourceId": .int(30)]),
            .array([.string("$"), .string("$L29"), .string(String(episode)), props])])
        let payload = "19:" + (try tree.text()) + "\n"
        let push = try JSONValue.array([.int(1), .string(payload)]).text()
        return "<html><script>self.__next_f.push(\(push))</script><script src=\"/app.js\"></script></html>"
    }

    private func response(episode: Int = 203775, source: Int = 1, url: String? = nil) -> JSONValue {
        .object(["ok": .bool(true), "episode_id": .int(episode), "anime_id": .int(3432),
            "url": .string(url ?? signedMedia), "candidates": .array([
                .object(["source_id": .int(source), "url": .string(url ?? signedMedia)])])])
    }

    func testSignedResponseResolvesWithoutVideoDOMOrLegacyParser() async throws {
        let transport = PlaybackFixtureTransport(response: response())
        let result = try await XifanPlaybackService(http: HTTPClient(transport: transport)).resolve(page: firstPage, html: html(), rule: rule(), userAgent: "FixtureBrowser")
        XCTAssertEqual(result?.absoluteString, signedMedia)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.xifanacg.com/functions/v1/issue-web-playback")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "public-fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer public-fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "FixtureBrowser")
        let body = try JSONValue.parse(XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["action"]?.string, "fallback")
        XCTAssertEqual(body["episode_id"]?.int, 203775)
        XCTAssertEqual(body["source_id"]?.int, 1)
    }

    func testNextEpisodeAndSelectedSourceAreReadFromMatchingPlayerProps() async throws {
        let page = URL(string: "https://next.xifanacg.com/anime/3432/play/203776?source=backup")!
        let transport = PlaybackFixtureTransport(response: response(episode: 203776, source: 8))
        let result = try await XifanPlaybackService(http: HTTPClient(transport: transport)).resolve(page: page, html: html(episode: 203776, source: 8), rule: rule(), userAgent: "")
        XCTAssertEqual(result?.absoluteString, signedMedia)
        let requests = await transport.requests
        let body = try JSONValue.parse(XCTUnwrap(requests.first?.httpBody))
        XCTAssertEqual(body["episode_id"]?.int, 203776)
        XCTAssertEqual(body["source_id"]?.int, 8)
    }

    func testUnrelatedPagesAndAPIHostsDoNotSendRuleHeaders() async throws {
        for (page, plugin) in [(URL(string: "https://other.example/anime/3432/play/203775")!, rule()), (firstPage, rule(apiHost: "other.example"))] {
            let transport = PlaybackFixtureTransport(response: response())
            let result = try await XifanPlaybackService(http: HTTPClient(transport: transport)).resolve(page: page, html: html(), rule: plugin, userAgent: "")
            XCTAssertNil(result)
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testMismatchedPlayerPropsDoNotResolveAnotherEpisode() async throws {
        let transport = PlaybackFixtureTransport(response: response())
        do {
            _ = try await XifanPlaybackService(http: HTTPClient(transport: transport)).resolve(page: firstPage, html: html(episode: 203776), rule: rule(), userAgent: "")
            XCTFail("Expected an unmatched player to fail")
        } catch {}
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testWrongEpisodeSourceAndNonMediaResponsesAreRejected() async throws {
        for payload in [response(episode: 203776), response(source: 8), response(url: "https://media.example/embed.html?url=a.m3u8"),
                        JSONValue.object(["ok": .bool(false), "error": .string("forbidden"), "url": .string(signedMedia)])] {
            let transport = PlaybackFixtureTransport(response: payload)
            do {
                _ = try await XifanPlaybackService(http: HTTPClient(transport: transport)).resolve(page: firstPage, html: html(), rule: rule(), userAgent: "")
                XCTFail("Expected invalid playback response to fail")
            } catch {}
        }
    }
}

private actor PlaybackFixtureTransport: HTTPTransport {
    let response: JSONValue
    private(set) var requests: [URLRequest] = []
    init(response: JSONValue) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (try response.data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}
