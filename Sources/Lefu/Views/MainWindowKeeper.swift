import AppKit

// MARK: - 主窗保活（关窗不销毁，只隐藏）
//
// 背景：乐府是菜单栏常驻应用，用户会频繁关掉主窗再点菜单栏的「打开主窗」。
//
// SwiftUI 的 `WindowGroup` 在窗口关闭后会**销毁该窗口**，此时
// `makeKeyAndOrderFront` 已无对象可用。而重新创建窗口的官方手段是
// `OpenWindowAction`（openWindow），它是 **macOS 13+** API —— 在 macOS 12 上不可用。
//
// 与其为「重建窗口」做版本分叉，这里直接让窗口**不被销毁**：
// 拦截 `windowShouldClose`，改为 `orderOut`（隐藏）并返回 false，
// 于是窗口对象与内容视图始终存在，「打开主窗」只需 makeKeyAndOrderFront，
// 一条路径同时适用于 macOS 12 与 13+，无需 openWindow。
//
// 注意：不能直接把 NSWindow.delegate 换成自己——那会丢掉 SwiftUI 自己的代理逻辑。
// 所以用「代理转发」：把自己设为 delegate，非本类关心的选择器一律转发给原 delegate。

/// 窗口关闭拦截器：把「关闭」变成「隐藏」。
final class MainWindowKeeper: NSObject, NSWindowDelegate {

    /// SwiftUI 原本的 delegate，未处理的消息转发给它
    private weak var originalDelegate: NSWindowDelegate?
    private weak var window: NSWindow?

    /// 安装到指定窗口（幂等：重复调用不会叠加）
    @discardableResult
    static func install(on window: NSWindow) -> MainWindowKeeper {
        if let existing = window.delegate as? MainWindowKeeper {
            return existing
        }
        let keeper = MainWindowKeeper()
        keeper.window = window
        keeper.originalDelegate = window.delegate
        window.delegate = keeper
        // 双保险：即便某条路径绕过 windowShouldClose 直接关闭，
        // 也不让 AppKit 释放窗口对象（配合上面的强引用，窗口可再次显示）。
        window.isReleasedWhenClosed = false
        return keeper
    }

    /// 拦截关闭：只隐藏，不销毁
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        Diag.log("WIN 主窗关闭 → 转为隐藏（保持可再打开）")
        return false
    }

    /// 未实现的选择器转发给原 delegate，避免破坏 SwiftUI 的窗口行为
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original = originalDelegate, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return originalDelegate?.responds(to: aSelector) ?? false
    }
}
