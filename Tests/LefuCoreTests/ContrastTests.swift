import XCTest
@testable import LefuCore

final class ContrastTests: XCTestCase {
    private let white = RGB(r: 1, g: 1, b: 1)
    private let black = RGB(r: 0, g: 0, b: 0)

    func testContrastRatioExtremes() {
        XCTAssertEqual(AccentDerivation.contrastRatio(black, white), 21, accuracy: 0.01)
        XCTAssertEqual(AccentDerivation.contrastRatio(white, white), 1, accuracy: 0.001)
    }

    /// 浅金色在纯白上约 1.6:1，应被压暗到 >= 4.5:1。
    func testPaleGoldOnWhiteIsAdjustedToPass() {
        let paleGold = RGB(r: 0.95, g: 0.85, b: 0.55)
        XCTAssertLessThanOrEqual(AccentDerivation.contrastRatio(paleGold, white), 4.5)
        let out = AccentDerivation.contrastSafe(paleGold, against: white, minRatio: 4.5)
        XCTAssertGreaterThanOrEqual(AccentDerivation.contrastRatio(out, white), 4.5)
        XCTAssertTrue((0...1).contains(out.r))
        XCTAssertTrue((0...1).contains(out.g))
        XCTAssertTrue((0...1).contains(out.b))
    }

    /// 深色强调色落在深色面板上，应被提亮到 >= 4.5:1。
    func testDarkColorOnDarkBackgroundIsAdjusted() {
        let dark = RGB(r: 0.05, g: 0.05, b: 0.10)
        let darkBG = RGB(r: 0.08, g: 0.07, b: 0.10)
        XCTAssertLessThanOrEqual(AccentDerivation.contrastRatio(dark, darkBG), 4.5)
        let out = AccentDerivation.contrastSafe(dark, against: darkBG, minRatio: 4.5)
        XCTAssertGreaterThanOrEqual(AccentDerivation.contrastRatio(out, darkBG), 4.5)
    }

    /// 已经达标的颜色必须原样返回。
    func testAlreadyPassingColorIsReturnedUnchanged() {
        let already = RGB(r: 0.0, g: 0.0, b: 0.0)
        XCTAssertGreaterThanOrEqual(AccentDerivation.contrastRatio(already, white), 4.5)
        XCTAssertEqual(AccentDerivation.contrastSafe(already, against: white, minRatio: 4.5), already)
    }
}
