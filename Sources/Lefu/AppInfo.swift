import Foundation

// MARK: - 版本信息
// 由 Info.plist 读取；打包脚本 scripts/build_app.sh 每次执行都会把构建号 +1，
// 所以「设置页 / 菜单栏面板」显示的版本号能直接确认当前装的是哪一次打包。
enum AppInfo {
    /// 营销版本号，如 1.0.1
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// 构建号（每次打包递增）
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// 展示用：「1.0.1 (2)」
    static var versionText: String { "\(shortVersion) (\(buildNumber))" }
}
