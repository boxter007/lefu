import Foundation
import LefuCore

// MARK: - 音源协议
// 一个音乐软件 = 一份「音源档案」：档案元数据 + 该音源自带的本地歌词后端。
protocol MusicSource: AnyObject {
    static var profile: SourceProfile { get }
    /// 本地歌词后端（零联网）。不实现者默认无本地歌词能力。
    static var lyricsBackends: [LyricsBackend] { get }
}

extension MusicSource {
    static var lyricsBackends: [LyricsBackend] { [] }
}

// MARK: - 音源登记处
// 内置音源清单与解析逻辑：监听层/设置页只认这里，不再写死任何 bundle。
final class SourceRegistry {
    static let shared = SourceRegistry(sources: [SodaSource.self, AppleMusicSource.self])

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

    /// 解析某音源声明的本地歌词后端：由 MusicSource 类型自身声明（单一真源），按注册类型取；未登记返回空
    func backends(for profile: SourceProfile) -> [LyricsBackend] {
        types.first { $0.profile.id == profile.id }?.lyricsBackends ?? []
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
