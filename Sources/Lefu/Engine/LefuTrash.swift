import Foundation

// MARK: - 统一清理通道（带降级）
// 教训：FileManager.trashItem 在本机会被安全管控静默拦截（废纸篓 0 条记录 + 21/21 场全遗留 wav 实锤），
// try? 把失败吞掉后 WAV 从未真正清掉，府库积了 1GB 中间产物。
// 策略：先走废纸篓（可反悔）；被拦则降级直接删除（本机 unlink 实测可用）；再失败就留现场 + Diag 记账。
enum LefuTrash {
    @discardableResult
    static func trash(_ url: URL) -> Bool {
        let fm = FileManager.default
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            Diag.log("TRASH 废纸篓被拦，降级直接删除 \(url.lastPathComponent): \(error.localizedDescription)")
        }
        do {
            try fm.removeItem(at: url)
            Diag.log("TRASH 直接删除成功 \(url.lastPathComponent)")
            return true
        } catch {
            Diag.log("TRASH 直接删除也失败 \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
}
