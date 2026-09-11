import Foundation
import CoreMedia
import LefuCore

// MARK: - 正在播放信息
struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var rate: Double?      // 播放速率：>0 在播，0 暂停；nil = 系统未上报该字段
    var artwork: Data?
    var clientBundle: String? = nil   // 系统上报的客户端 App 标识（音源登记处据此解析/门禁）

    var key: String { title + "|" + artist }
}

// MARK: - 播放控制（让汽水真的切歌）
enum NowPlayingControl {
    /// 切到下一首：按音源档案声明的控制通道执行
    /// - .none：该音源不支持控制，明确返回失败（不谎报成功）
    /// - .nowPlayingCLI：优先 nowplaying-cli（已实测能控制汽水），失败回落 MediaRemote 命令
    /// - .mediaRemote：跳过 CLI，直接走 MediaRemote 命令
    @discardableResult
    static func next(channel: ControlChannel) -> Bool {
        switch channel {
        case .none:
            return false
        case .mediaRemote:
            return sendMediaRemoteCommand("kMRNextTrack")
        case .nowPlayingCLI:
            for path in ["/opt/homebrew/bin/nowplaying-cli", "/usr/local/bin/nowplaying-cli"] {
                guard FileManager.default.isExecutableFile(atPath: path) else { continue }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                proc.arguments = ["next"]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 { return true }
                } catch {
                    continue
                }
            }
            return sendMediaRemoteCommand("kMRNextTrack")
        }
    }

    /// MediaRemote 私有框架发控制命令（CLI 缺失时的兜底）
    private static func sendMediaRemoteCommand(_ command: String) -> Bool {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: path)),
              let sym = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return false }
        typealias Fn = @convention(c) (CFString, CFDictionary?, AnyObject?, AnyObject?) -> Void
        let fn = unsafeBitCast(sym, to: Fn.self)
        final class Box { var ok = false }
        let box = Box()
        let handler: @convention(block) () -> Void = { box.ok = true }
        let blockObj = unsafeBitCast(handler, to: AnyObject.self)
        let queue = DispatchQueue(label: "lefu.mediaremote.cmd")
        fn(command as CFString, nil, queue, blockObj)
        let deadline = Date().addingTimeInterval(0.8)
        while !box.ok && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        return box.ok
    }
}

// MARK: - 正在播放监听
// 主通道：MediaRemote 私有框架；兜底：nowplaying-cli（若已安装）
// 设计约定：本层只产"每拍轮询事实"（onUpdate），不做任何歌名判断——
// 确认/去抖/残影识别全部由 SessionController 的确认器负责
final class NowPlayingMonitor {
    var onUpdate: ((TrackInfo?) -> Void)?     // 每次轮询都回调（确认器消费）
    private var timer: Timer?
    private var lastTitle = ""
    private var lastMeta: TrackInfo?
    // fetch 会阻塞数百毫秒（起进程+读管道），放后台串行队列跑，主线程只做状态处理
    private let fetchQueue = DispatchQueue(label: "lefu.nowplaying.fetch", qos: .userInitiated)

    func start(interval: TimeInterval = 1.0) {
        stop()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTitle = ""
        lastMeta = nil
    }

    private func poll() {
        fetchQueue.async { [weak self] in
            let info = Self.fetch()
            DispatchQueue.main.async { [weak self] in
                self?.handle(info)
            }
        }
    }

    private func handle(_ info: TrackInfo?) {
        onUpdate?(info)   // 只产事实：确认器消费（歌名判断在 SessionController）
    }

    // MARK: 采集一次
    // 主通道：nowplaying-cli（engine/soda_nowplaying.py 同款，已实测可用）
    // 兜底：MediaRemote 私有框架（部分系统版本已被 Apple 收紧）
    static func fetch() -> TrackInfo? {
        if let t = fetchCLI() { return t }
        if let t = fetchMediaRemote() { return t }
        return nil
    }

    // MARK: MediaRemote 私有框架
    private static let mrBundle: CFBundle? = {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        return CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: path))
    }()

    private static func fetchMediaRemote() -> TrackInfo? {
        guard let bundle = mrBundle,
              let sym = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString)
        else { return nil }

        typealias Fn = @convention(c) (AnyObject?, AnyObject?) -> Void
        let fn = unsafeBitCast(sym, to: Fn.self)

        final class Box { var dict: CFDictionary? }
        let box = Box()
        let handler: @convention(block) (CFDictionary?) -> Void = { d in
            if let d { box.dict = d }
        }
        let blockObj = unsafeBitCast(handler, to: AnyObject.self)
        let queue = DispatchQueue(label: "lefu.mediaremote")

        fn(queue, blockObj)

        // 同步等待，最多 800ms
        let deadline = Date().addingTimeInterval(0.8)
        while box.dict == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard let d = box.dict as? [String: Any] else { return nil }

        let title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let artist = d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = d["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let duration = d["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
        let elapsed = d["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        let rate: Double? = {
            if let v = d["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double { return v }
            return (d["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
        }()
        // 客户端 App 标识：上报给门禁层，由音源登记处解析
        let clientBundle = d["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String
        // 封面：部分系统版本会随信息字典一起给出
        var artwork: Data?
        if let art = d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data { artwork = art }
        if title.isEmpty { return nil }
        return TrackInfo(title: title, artist: artist, album: album, duration: duration, elapsed: elapsed, rate: rate, artwork: artwork, clientBundle: clientBundle)
    }

    // MARK: nowplaying-cli 兜底（get-raw 返回 kMRMediaRemoteNowPlayingInfo* 原始键）
    private static func fetchCLI() -> TrackInfo? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/nowplaying-cli")
        proc.arguments = ["get-raw"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let title = json["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            if title.isEmpty { return nil }
            let artist = json["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = json["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            let duration = (json["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
            let elapsed = (json["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
            let rate = (json["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
            // 客户端 App 标识：不再在此层过滤音源，交给登记处/门禁
            let clientBundle = json["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String
            // 封面：get-raw 给的是 base64 字符串
            var artwork: Data?
            if let b64 = json["kMRMediaRemoteNowPlayingInfoArtworkData"] as? String,
               let raw = Data(base64Encoded: b64), raw.count > 100 {
                artwork = raw
            } else if let raw = json["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, raw.count > 100 {
                artwork = raw
            }
            return TrackInfo(title: title, artist: artist, album: album, duration: duration, elapsed: elapsed, rate: rate, artwork: artwork, clientBundle: clientBundle)
        } catch {
            return nil
        }
    }
}
