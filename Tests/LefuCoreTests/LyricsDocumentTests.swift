import XCTest
@testable import LefuCore

final class LyricsDocumentTests: XCTestCase {
    func testParseLRCWithMultipleTags() {
        let doc = LyricsDocument.parseLRC("[00:01.00][00:02.00]hi\n[00:03.50]bye")
        XCTAssertEqual(doc.lines.map { $0.start }, [1.0, 2.0, 3.5])
        XCTAssertEqual(doc.lines.map { $0.text }, ["hi", "hi", "bye"])
    }
    func testCurrentLineIndex() {
        let doc = LyricsDocument.parseLRC("[00:01.00]a\n[00:05.00]b")
        XCTAssertEqual(doc.currentLineIndex(at: 0.5), -1)
        XCTAssertEqual(doc.currentLineIndex(at: 1.0), 0)
        XCTAssertEqual(doc.currentLineIndex(at: 9.0), 1)
    }
    func testParseKRCKeepsWordTimings() {
        let raw = "[1000,2000]<0,500,0>Hel<500,500,0>lo"
        let doc = LyricsDocument.parseKRC(raw)
        XCTAssertEqual(doc.lines.count, 1)
        XCTAssertEqual(doc.lines[0].text, "Hello")
        XCTAssertEqual(doc.lines[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(doc.lines[0].words.count, 2)
        XCTAssertEqual(doc.lines[0].words[1].start, 1.5, accuracy: 0.001)
    }
    func testToLRCRoundTrip() {
        let doc = LyricsDocument.parseKRC("[1000,2000]<0,500,0>Hi")
        XCTAssertTrue(doc.toLRC().contains("[00:01.00]Hi"))
    }
}
