import Foundation

// MARK: - 诊断日志（排查卡死专用：全程时间戳落盘 ~/Library/Logs/lefu-diag.log）
// 乐府是挂机常驻型应用，日志必须自带上限，否则长期运行会一路涨到占满磁盘。
enum Diag {
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "lefu.diag")
    /// 单文件上限 2MB，超过就归档
    private static let maxBytes: UInt64 = 2 * 1024 * 1024
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/lefu-diag.log")
    /// 归档文件（只保留最近一轮，避免无限堆叠）
    private static var archiveURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("lefu-diag.log.1")
    }

    static func log(_ msg: String) {
        queue.async {
            let line = "\(formatter.string(from: Date())) [\(Thread.current.isMainThread ? "M" : "B")] \(msg)\n"
            lock.lock()
            rotateIfNeeded()
            if let fh = FileHandle(forWritingAtPath: url.path) {
                fh.seekToEndOfFile()
                fh.write(Data(line.utf8))
                try? fh.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
            lock.unlock()
        }
    }

    /// 超过上限时把当前日志整体挪成 .1（覆盖旧归档），再开新文件继续写
    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxBytes else { return }
        try? fm.removeItem(at: archiveURL)
        try? fm.moveItem(at: url, to: archiveURL)
    }

    /// 计时工具
    static func since(_ t: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(t))
    }
}
