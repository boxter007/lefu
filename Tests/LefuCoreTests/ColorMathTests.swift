import XCTest
@testable import LefuCore

final class ColorMathTests: XCTestCase {
    func testPureGrayReturnsNil() {
        XCTAssertNil(AccentDerivation.clamp(RGB(r: 0.5, g: 0.5, b: 0.5)))
    }
    func testLowSaturationReturnsNil() {
        XCTAssertNil(AccentDerivation.clamp(RGB(r: 0.50, g: 0.48, b: 0.46)))
    }
    func testSaturatedDarkColorIsBrightened() {
        let out = AccentDerivation.clamp(RGB(r: 0.10, g: 0.02, b: 0.20))!
        let (_, s, l) = AccentDerivation.toHSL(out)
        XCTAssertGreaterThanOrEqual(l, 0.44)
        XCTAssertLessThanOrEqual(l, 0.73)
        XCTAssertGreaterThanOrEqual(s, 0.34)
    }
    func testHueIsPreserved() {
        let input = RGB(r: 0.9, g: 0.4, b: 0.1)
        let (h0, _, _) = AccentDerivation.toHSL(input)
        let out = AccentDerivation.clamp(input)!
        let (h1, _, _) = AccentDerivation.toHSL(out)
        XCTAssertEqual(h0, h1, accuracy: 0.01)
    }
}
