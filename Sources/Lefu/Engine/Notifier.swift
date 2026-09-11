import AppKit
import UserNotifications

/// 完成通知 + 触感反馈
///
/// 打包后的 App 才有 bundleIdentifier；`swift run` 直接起可执行文件时为 nil，
/// 此时 UNUserNotificationCenter 会因缺少 bundle 而崩溃/报错，故所有入口都先 guard。
enum Notifier {
    /// 前台展示代理：App 在前台时也弹横幅 + 声音（默认会被系统直接吞掉）。
    /// UNUserNotificationCenter.delegate 是 weak，必须静态强持有，否则设置完就被释放。
    private static let presenter = ForegroundNotificationPresenter()

    /// 启动时申请一次通知权限（未打包运行直接跳过）
    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = presenter
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 一首歌收卷成功：发系统通知，带曲名/歌手；有封面时挂上封面。
    static func songCaptured(title: String, artist: String, cover: Data? = nil) {
        guard Bundle.main.bundleIdentifier != nil, !title.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "已收录"
        content.body = artist.isEmpty ? title : artist + " — " + title
        content.sound = .default
        if let cover, let attachment = makeAttachment(from: cover) {
            content.attachments = [attachment]
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// 触控板触感（收卷完成的一下轻震）
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: 封面附件
    /// 把封面原始字节落到临时文件再挂成通知附件；任何失败都静默放弃，绝不影响通知本身。
    private static func makeAttachment(from data: Data) -> UNNotificationAttachment? {
        let ext = imageExtension(for: data) ?? "png"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lefu-notify-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(identifier: "cover", url: url, options: nil)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// 从魔数判图片扩展名，保证 UNNotificationAttachment 拿到合法后缀。
    private static func imageExtension(for data: Data) -> String? {
        let b = [UInt8](data.prefix(12))
        if b.count >= 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "png" }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "jpg" }
        if b.count >= 4, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "gif" }
        if b.count >= 12, b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "webp" }
        return nil
    }
}

/// 前台通知呈现：系统默认前台不弹，这里显式要横幅 + 声音。
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
