import XCTest
@testable import KazumiCore

final class XPathPositionTests: XCTestCase {
    func testDescendantPositionsAreEvaluatedWithinEachParent() throws {
        let root = HTMLParser.parse("<html><body><section><div>one</div><div>A</div></section><section><div>two</div><div>B</div></section></body></html>")
        XCTAssertEqual(try XPath.query("//div[2]", from: root).map(\.stringValue), ["A", "B"])
    }

    func testFilteredPositionsUseMatchingSiblingsAndDocumentOrder() throws {
        let root = HTMLParser.parse("<body><section><a class='x'>A</a><a>B</a><a class='x'>C</a><span><a class='x'>D</a></span></section><section><a class='x'>E</a><a class='x'>F</a></section></body>")
        XCTAssertEqual(try XPath.query("//a[contains(@class,'x')][1]", from: root).map(\.stringValue), ["A", "D", "E"])
        XCTAssertEqual(try XPath.query("//a[contains(@class,'x')][2]", from: root).map(\.stringValue), ["C", "F"])
    }

    func testPositionalRoadSelectorKeepsAllEpisodes() throws {
        let root = HTMLParser.parse("<body><div></div><div></div><div></div><div><div></div><div><div><ul><li><h2><a href='/show/1'>番剧</a></h2></li><li><h2><a href='/show/2'>番剧二</a></h2></li></ul></div></div></div></body>")
        XCTAssertEqual(try XPath.query("//div[4]/div[2]/div[1]/ul/li", from: root).count, 2)
    }
}
