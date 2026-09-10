import Foundation

// MARK: - BlackHole 一键安装器
// 全新机器零环境场景：下载官方 pkg → 提权安装 → 校验驱动
enum BlackHoleInstaller {
    static let pkgURL = URL(string: "https://existential.audio/downloads/BlackHole2ch-0.6.1.pkg")!
    static let officialSite = URL(string: "https://existential.audio/blackhole/")!

    /// 下载官方 pkg 到临时目录，返回本地路径
    static func download() async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlackHole2ch-\(UUID().uuidString.prefix(6)).pkg")
        let (bytes, resp) = try await URLSession.shared.bytes(from: pkgURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "BlackHoleInstaller", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "下载链接不可用"])
        }
        var data = Data()
        data.reserveCapacity(2 << 20)
        for try await b in bytes { data.append(b) }
        guard data.count > 100_000 else { // pkg 至少几百 KB，防 404 页面
            throw NSError(domain: "BlackHoleInstaller", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "下载内容异常"])
        }
        try data.write(to: tmp, options: .atomic)
        return tmp
    }

    /// 提权执行 installer（系统会弹管理员密码框）
    static func install(pkg: URL) throws {
        let script = "do shell script \"installer -pkg '\(pkg.path)' -target /\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "BlackHoleInstaller", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: proc.terminationStatus == 1 ? "已取消或密码不对" : "安装器退出码 \(proc.terminationStatus)"])
        }
    }

    /// 安装后需要重启音频服务才枚举得到，稍等再查
    static func verifyAfterDelay(seconds: Double = 2.0) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return AudioCapture.findBlackHole() != nil
    }
}
