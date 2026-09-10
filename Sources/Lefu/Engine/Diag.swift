import Foundation

// MARK: - 诊断日志（排查卡死专用：全程时间戳落盘 ~/Library/Logs/lefu-diag.log）
enum Diag {
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "lefu.diag")
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/lefu-diag.log")

    static func log(_ msg: String) {
        queue.async {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            let line = "\(f.string(from: Date())) [\(Thread.current.isMainThread ? "M" : "B")] \(msg)\n"
            lock.lock()
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

    /// 计时工具
    static func since(_ t: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(t))
    }
}
