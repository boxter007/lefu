import AppKit
import UserNotifications

/// 完成通知 + 触感反馈
///
/// 打包后的 App 才有 bundleIdentifier；`swift run` 直接起可执行文件时为 nil，
/// 此时 UNUserNotificationCenter 会因缺少 bundle 而崩溃/报错，故所有入口都先 guard。
enum Notifier {
    /// 启动时申请一次通知权限（未打包运行直接跳过）
    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 一首歌收卷成功：发系统通知，带曲名/歌手
    static func songCaptured(title: String, artist: String) {
        guard Bundle.main.bundleIdentifier != nil, !title.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "已收录"
        content.body = artist.isEmpty ? title : artist + " — " + title
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// 触控板触感（收卷完成的一下轻震）
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
