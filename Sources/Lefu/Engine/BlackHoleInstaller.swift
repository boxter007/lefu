import Foundation
import CryptoKit

// MARK: - BlackHole 一键安装器
// 全新机器零环境场景：下载官方 pkg → 校验 → 提权安装 → 校验驱动
//
// 安全边界：安装包最终会以管理员权限执行，因此下载物必须同时通过两道校验——
//   ① 字节级 SHA256 与固定版本一致；② 签名链来自官方发行方且已被 Apple 公证。
//   二者任一不符即中止，绝不进入提权安装环节。
enum BlackHoleInstaller {
    static let pkgURL = URL(string: "https://existential.audio/downloads/BlackHole2ch-0.6.1.pkg")!
    static let officialSite = URL(string: "https://existential.audio/blackhole/")!

    /// 固定版本 BlackHole2ch-0.6.1.pkg 的 SHA256（2026-09-11 实测官方分发物）
    private static let expectedSHA256 = "c829afa041a9f6e1b369c01953c8f079740dd1f02421109855829edc0d3c1988"
    /// 官方发行方 Team ID：Developer ID Installer: Existential Audio Inc. (Q5C99V536K)
    private static let expectedTeamID = "Q5C99V536K"

    /// 下载官方 pkg → 校验哈希与签名 → 落盘，返回本地路径
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

        // 校验 1：字节级哈希必须与固定版本完全一致（防下载被替换、镜像/CDN 被投毒）
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else {
            throw NSError(domain: "BlackHoleInstaller", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "安装包哈希校验失败，已中止安装，请到官网手动下载"])
        }

        try data.write(to: tmp, options: .atomic)

        // 校验 2：签名链必须是官方发行方 + 已公证（pkgutil 需要落地文件，故放在写盘之后）
        do {
            try verifySignature(pkg: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
        return tmp
    }

    /// 校验 pkg 的 Developer ID Installer 签名链：Team ID 必须是官方发行方，且已被 Apple 公证
    private static func verifySignature(pkg: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        proc.arguments = ["--check-signature", pkg.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let text = String(data: out, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0,
              text.contains(expectedTeamID),
              text.lowercased().contains("notarization: trusted") else {
            throw NSError(domain: "BlackHoleInstaller", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "安装包签名校验未通过，已中止安装，请到官网手动下载"])
        }
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
