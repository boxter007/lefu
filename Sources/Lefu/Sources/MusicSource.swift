import Foundation
import LefuCore

// MARK: - 音源协议
// 一个音乐软件 = 一份「音源档案」。本协议只要求档案本身；
// Task 3 会在协议上追加 lyricsBackends（本地歌词后端）要求。
protocol MusicSource: AnyObject {
    static var profile: SourceProfile { get }
}

// MARK: - 音源登记处
// 内置音源清单与解析逻辑：监听层/设置页只认这里，不再写死任何 bundle。
final class SourceRegistry {
    static let shared = SourceRegistry(sources: [SodaSource.self])

    private let types: [any MusicSource.Type]

    init(sources: [any MusicSource.Type]) {
        self.types = sources
    }

    var allProfiles: [SourceProfile] {
        types.map { $0.profile }
    }

    /// 按系统上报的客户端 App 标识解析音源；解析不到即不支持
    func profile(forBundle bundleID: String?) -> SourceProfile? {
        SourceCatalog.resolve(bundleID: bundleID, in: allProfiles)
    }

    func profile(forID id: String) -> SourceProfile? {
        allProfiles.first { $0.id.raw == id }
    }

    /// 门禁：该 App 标识解析出的音源必须在已启用集合内
    func isEnabled(_ bundleID: String?, enabled: [String]) -> Bool {
        guard let p = profile(forBundle: bundleID) else { return false }
        return enabled.contains(p.id.raw)
    }

    func enabledProfiles(_ enabled: [String]) -> [SourceProfile] {
        SourceCatalog.filterEnabled(allProfiles, enabled: Set(enabled))
    }
}
