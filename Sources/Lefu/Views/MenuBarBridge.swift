import SwiftUI
import AppKit
import Combine

// MARK: - 菜单栏常驻面板（全版本唯一路径）
//
// 乐府原本用 SwiftUI 的 `MenuBarExtra` 承载菜单栏常驻面板，但它是 **macOS 13+**
// API，而乐府最低支持 macOS 12。这里改用 AppKit 的 `NSStatusItem` + `NSPopover`
// 提供等价能力，**所有系统版本统一走这一条路径**（不做版本分叉）。
//
// 关键点：面板本体 `MenuBarPanel` 是一个普通 SwiftUI `View`，与 MenuBarExtra
// 并无耦合，所以只需换「外壳」，不需要重写任何界面代码。
//
// 为什么不分叉（13+ 用原生、旧系统用 AppKit）：Scene 的 opaque 返回类型要求
// 所有 return 的底层类型一致，按版本返回 Window 与 WindowGroup 会生成崩溃代码，
// 详见 LefuApp.swift 顶部说明与 CHANGELOG 1.0.5。单一路径换来的是可测与不崩。

/// 用 NSStatusItem + NSPopover 托住一个 SwiftUI 视图，行为对齐 `MenuBarExtra(.window)`：
/// - 左键点击状态项 → 弹出面板；再次点击 → 收起
/// - 点击面板外任意位置 → 自动收起（popover 的 transient 行为）
/// - 采诗进行中 → 图标高亮为实心
///
/// 注：类型本身不做 `@available` 限制，只在运行时按系统版本决定是否 install，
/// 这样 AppDelegate 里的 `if #available` 分支能正常编译。
///
/// 标注 `@MainActor`：NSStatusItem 与 NSPopover 都是主线程专属，同时这样也
/// 可以直接访问 SessionController 上主线程隔离的 `@Published state`。
@MainActor
final class MenuBarBridge: NSObject, NSPopoverDelegate {

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var session: SessionController?
    private var settings: AppSettings?
    private var notificationTokens: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    /// 状态图标（SF Symbol 名）随采诗状态切换，与 MenuBarExtra 路径保持一致
    private func symbolName() -> String {
        session?.state == .live ? "waveform.circle.fill" : "music.note.house"
    }

    func install(settings: AppSettings, session: SessionController) {
        self.settings = settings
        self.session = session

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.image = statusImage()
        item.button?.image?.isTemplate = true   // 让系统按明暗菜单栏自动反色
        self.statusItem = item

        popover.behavior = .transient            // 点外部自动收起
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel(settings: settings, session: session)
                // 与主窗共用同一份主题派生，保证封面强调色等细节完全一致
                .environment(\.lefuTheme,
                             LefuThemeFactory.make(settings: settings, session: session))
        )

        // 采诗状态变化 → 换图标（对齐 MenuBarExtra 的 label 行为）。
        // 类整体标注 @MainActor（见类型声明），故这里直接访问 @Published state 合法；
        // receive(on:) 保证回调落在主线程再动 UI。
        session.$state
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let button = self.statusItem?.button else { return }
                let img = self.statusImage()
                img?.isTemplate = true
                button.image = img
            }
            .store(in: &cancellables)

        // 「显示主窗」通知 → 关掉面板并前置主窗（AppKit 路径拿不到 openWindow 环境）
        let showToken = NotificationCenter.default.addObserver(
            forName: .lefuShowMain, object: nil, queue: .main
        ) { [weak self] _ in
            self?.popover.performClose(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let win = LefuApp.mainWindow {
                if win.isMiniaturized { win.deminiaturize(nil) }
                win.makeKeyAndOrderFront(nil)
            }
        }
        notificationTokens.append(showToken)
    }

    private func statusImage() -> NSImage? {
        NSImage(systemSymbolName: symbolName(), accessibilityDescription: "乐府")
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func teardown() {
        cancellables.removeAll()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }
}
