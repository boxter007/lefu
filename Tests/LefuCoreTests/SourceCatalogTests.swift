import XCTest
import LefuCore

final class SourceCatalogTests: XCTestCase {
    private func soda() -> SourceProfile {
        SourceProfile(
            id: SourceID(raw: "soda"), displayName: "汽水音乐",
            bundleIDs: ["com.soda.music"], symbolName: "music.note",
            detection: DetectionProfile(), control: .nowPlayingCLI,
            enabledByDefault: true)
    }
    private func netease() -> SourceProfile {
        SourceProfile(
            id: SourceID(raw: "netease"), displayName: "网易云音乐",
            bundleIDs: ["com.netease.163music"], symbolName: "cloud",
            detection: DetectionProfile(playSignal: .elapsedAdvance),
            control: .mediaRemote, enabledByDefault: false)
    }

    func testResolveByBundleID() {
        let profiles = [soda(), netease()]
        XCTAssertEqual(SourceCatalog.resolve(bundleID: "com.soda.music", in: profiles)?.id.raw, "soda")
        XCTAssertEqual(SourceCatalog.resolve(bundleID: "com.netease.163music", in: profiles)?.id.raw, "netease")
    }
    func testResolveUnknownAndNil() {
        let profiles = [soda()]
        XCTAssertNil(SourceCatalog.resolve(bundleID: "com.spotify.client", in: profiles))
        XCTAssertNil(SourceCatalog.resolve(bundleID: nil, in: profiles))
        XCTAssertNil(SourceCatalog.resolve(bundleID: "", in: profiles))
    }
    func testFilterEnabled() {
        let profiles = [soda(), netease()]
        let enabled = SourceCatalog.filterEnabled(profiles, enabled: ["soda"])
        XCTAssertEqual(enabled.map(\.id.raw), ["soda"])
        XCTAssertTrue(SourceCatalog.filterEnabled(profiles, enabled: ["netease", "soda"]).count == 2)
        XCTAssertTrue(SourceCatalog.filterEnabled(profiles, enabled: []).isEmpty)
    }
    func testDefaultDetectionProfile() {
        let d = DetectionProfile()
        XCTAssertEqual(d.confirmTicks, 2)
        XCTAssertEqual(d.pollInterval, 1.0)
        XCTAssertEqual(d.playSignal, .ratePreferred)
        XCTAssertEqual(d.exposesElapsed, false)   // 汽水 elapsed 恒为 0
    }
}
