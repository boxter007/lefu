import Foundation
import Combine

// MARK: - 应用设置（四分区表单的数据源）
final class AppSettings: ObservableObject {
    @Published var themeMode: ThemeMode { didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode") } }
    @Published var silenceAutoStop: Bool { didSet { UserDefaults.standard.set(silenceAutoStop, forKey: "silenceAutoStop") } }
    @Published var minLength: Int { didSet { UserDefaults.standard.set(minLength, forKey: "minLength") } }
    @Published var outputDir: String { didSet { UserDefaults.standard.set(outputDir, forKey: "outputDir") } }
    @Published var format: OutputFormat { didSet { UserDefaults.standard.set(format.rawValue, forKey: "format") } }
    @Published var offlineMode: Bool { didSet { UserDefaults.standard.set(offlineMode, forKey: "offlineMode") } }
    @Published var lyricFallback: Bool { didSet { UserDefaults.standard.set(lyricFallback, forKey: "lyricFallback") } }
    @Published var backgroundMonitor: Bool { didSet { UserDefaults.standard.set(backgroundMonitor, forKey: "backgroundMonitor") } }

    enum OutputFormat: String, CaseIterable {
        case mp3 = "mp3_320"
        case m4a = "m4a_256"
        case wav = "wav"
        var label: String {
            switch self {
            case .mp3: return "MP3 320k"
            case .m4a: return "M4A 256k"
            case .wav: return "WAV"
            }
        }
        var ext: String {
            switch self {
            case .mp3: return "mp3"
            case .m4a: return "m4a"
            case .wav: return "wav"
            }
        }
    }

    init() {
        let d = UserDefaults.standard
        self.themeMode = ThemeMode(rawValue: d.string(forKey: "themeMode") ?? "") ?? .system
        self.silenceAutoStop = d.object(forKey: "silenceAutoStop") as? Bool ?? true
        // 旧默认 60 秒会把不少正常短歌（42s 实验/串场铃声）当「过短·丢弃」，降到 30
        self.minLength = d.object(forKey: "minLength") as? Int ?? 30
        self.outputDir = d.string(forKey: "outputDir") ?? ("~/Music/乐府" as String)
        self.format = OutputFormat(rawValue: d.string(forKey: "format") ?? "") ?? .mp3
        self.offlineMode = d.object(forKey: "offlineMode") as? Bool ?? false
        self.lyricFallback = d.object(forKey: "lyricFallback") as? Bool ?? true
        self.backgroundMonitor = d.object(forKey: "backgroundMonitor") as? Bool ?? false
    }

    var resolvedOutputDir: URL {
        let p = (outputDir as NSString).expandingTildeInPath
        return URL(fileURLWithPath: p)
    }
}
