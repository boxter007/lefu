import SwiftUI

// MARK: - 根视图：窄轨侧栏 + 页面
struct RootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController
    @Environment(\.lefuTheme) var th
    @Environment(\.colorScheme) private var colorScheme

    enum Page: String, CaseIterable {
        case record = "采诗"
        case settings = "设置"
        case guide = "指南"
        var title: String {
            switch self {
            case .record: return "采诗 · 录制"
            case .settings: return "设置"
            case .guide: return "指南"
            }
        }
        var icon: String {
            switch self {
            case .record: return "record.circle"
            case .settings: return "gearshape"
            case .guide: return "book.pages"
            }
        }
    }

    @State private var page: Page = .record

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：原生 macOS 布局——品牌字跟红绿灯左对齐 + 竖线页名，右侧状态
            HStack(spacing: 10) {
                Color.clear.frame(width: 64)
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(th.accent)
                Text("乐府")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(th.text)
                Rectangle()
                    .fill(th.border2)
                    .frame(width: 1, height: 14)
                Text(page.rawValue)
                    .font(.lefu(.headline))
                    .foregroundColor(th.text2)
                Spacer()
                routeChip
                Spacer()
                recChip
                    .padding(.trailing, 16)
            }
            .frame(height: 40)
            .background(.regularMaterial)
            .background(TitleBarDragArea())

            HStack(spacing: 0) {
                // 侧栏
                VStack(spacing: 14) {
                    ForEach(Page.allCases, id: \.self) { p in
                        railItem(p)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .frame(width: 64)
                .background(.ultraThinMaterial)
                Divider().overlay(th.border)

                // 内容
                ZStack {
                    switch page {
                    case .record: RecordView(settings: settings, session: session)
                    case .settings: SettingsView(settings: settings, session: session)
                    case .guide: GuideView(settings: settings, session: session)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            // 最底层：主题底色；采诗页且正在播放时叠一层全窗模糊封面氛围
            ZStack {
                th.bg
                if page == .record, session.currentTrack != nil {
                    AmbientBackground(image: session.artworkImage,
                                      key: session.currentTrack?.key ?? "",
                                      isDark: colorScheme == .dark)
                        .ignoresSafeArea()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top) // 头部从窗口最顶开始，红绿灯融入同一行
        .onAppear { session.runEnvCheck() }
    }

    // MARK: 顶栏采诗通道状态徽章（点击跳指南页）
    private var routeChip: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { page = .guide }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: session.routeReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(session.routeReady ? Color.green : th.live)
                Text(session.routeReady ? "采诗通道 · 已接通" : "采诗通道 · 未接通")
                    .font(.lefu(.subheadline))
                    .foregroundColor(session.routeReady ? th.text2 : th.live)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(th.panel.opacity(0.9)))
            .overlay(Capsule().stroke(session.routeReady ? th.border2 : th.live.opacity(0.55), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: 顶栏录音计时（参考图样式：裸排圆点 + 时间，无胶囊底）
    private var recChip: some View {
        HStack(spacing: 6) {
            if session.state == .live {
                // 呼吸圆点走 CA 层动画：SwiftUI 的 repeatForever 会以 60Hz 逐帧 dirty 视图图
                PulseDot(color: th.live)
                    .frame(width: 7, height: 7)
                    .shadow(color: th.live.opacity(0.6), radius: 4)
                Text(session.elapsedText)
                    .font(.lefu(.mono))
                    .foregroundColor(th.live)
            } else {
                Circle().fill(th.text2).frame(width: 6, height: 6)
                Text(session.state == .cutting ? "裁曲中" : (session.state == .done ? "本次完成" : "空闲"))
                    .font(.lefu(.subheadline))
                    .foregroundColor(th.text2)
            }
        }
    }

    // MARK: 侧栏项
    @State private var hoveredPage: Page?
    private func railItem(_ p: Page) -> some View {
        let active = page == p
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { page = p }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: p.icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(active ? th.accent : (hoveredPage == p ? th.panel2 : .clear))
                    )
                    .foregroundColor(active ? th.accentContrast : (hoveredPage == p ? th.text : th.text2))
                    .shadow(color: active ? th.accent.opacity(0.35) : .clear, radius: 6, y: 2)
                    .scaleEffect(active ? 1.0 : (hoveredPage == p ? 1.06 : 1.0))
                Text(p.rawValue)
                    .font(.system(size: 11, weight: active ? .medium : .regular))
                    .foregroundColor(active ? th.accent : th.text2)
            }
            .frame(width: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in hoveredPage = h ? p : nil }
    }
}

// MARK: 顶栏空白处可拖动窗口
struct TitleBarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { v.window?.isMovableByWindowBackground = true }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
