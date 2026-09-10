import SwiftUI

// MARK: - 菜单栏迷你控制台（MenuBarExtra .window 样式）
struct MenuBarPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController
    @Environment(\.lefuTheme) var th

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusCard
            primaryButton
            monitorToggle
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: 头部：品牌 + 状态胶囊
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(th.accent)
            Text("乐府")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(th.text)
            Spacer()
            statusChip
        }
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(chipColor)
                .frame(width: 6, height: 6)
                .modifier(BreathingModifier())
                .shadow(color: chipColor.opacity(0.6), radius: 3)
            Text(chipText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(chipColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(chipColor.opacity(0.12)))
    }

    private var chipColor: Color {
        switch session.state {
        case .live: return th.live
        case .cutting: return th.accent
        case .done: return th.ok
        case .idle: return th.text3
        }
    }

    private var chipText: String {
        switch session.state {
        case .live: return "采诗中"
        case .cutting: return "裁曲中"
        case .done: return "本次完成"
        case .idle: return "空闲"
        }
    }

    // MARK: 状态卡
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch session.state {
            case .live:
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.currentTrack?.title ?? "等待曲目信息")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(th.text)
                            .lineLimit(1)
                        Text(session.currentTrack?.artist ?? "—")
                            .font(.lefu(.subheadline))
                            .foregroundColor(th.text2)
                            .lineLimit(1)
                    }
                    Spacer()
                    levelBars
                }
                Text(session.elapsedText)
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(th.live)
            case .cutting:
                Text("正在裁曲")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(th.text)
                ProgressView(value: session.cutProgress)
                    .tint(th.accent)
            case .done:
                Label("已收卷 \(session.doneStats.count) 首", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(th.ok)
                Text("成品在 \(settings.outputDir)")
                    .font(.lefu(.subheadline))
                    .foregroundColor(th.text2)
                    .lineLimit(1)
            case .idle:
                Text("府中清静")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(th.text)
                Text("汽水开播即自动采诗")
                    .font(.lefu(.subheadline))
                    .foregroundColor(th.text2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(th.panel.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(th.border, lineWidth: 0.5))
    }

    // MARK: 电平小波形（采诗中才有）
    private var levelBars: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                let h: CGFloat = {
                    let base = Double(levelSeed(i)) * Double(session.level)
                    return max(5, min(22, CGFloat(6 + base * 26)))
                }()
                Capsule()
                    .fill(th.live.opacity(0.85))
                    .frame(width: 3, height: h)
            }
        }
        .frame(height: 24, alignment: .bottom)
        .opacity(session.state == .live ? 1 : 0.35)
        .animation(.easeOut(duration: 0.12), value: session.level)
    }

    private func levelSeed(_ i: Int) -> Double {
        // 固定权重让四根柱子错落，而不是同涨同跌
        [0.55, 0.85, 0.7, 0.4][i % 4]
    }

    // MARK: 主按钮
    private var primaryButton: some View {
        Button {
            if session.state == .live { session.stopAndCut() } else { session.startSession() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: session.state == .live ? "stop.fill" : "record.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(session.state == .live ? "收卷裁曲" : "开始采诗")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(th.accentContrast)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [th.accent, th.accent.opacity(0.82)],
                                         startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: th.accent.opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(session.state == .cutting)
        .opacity(session.state == .cutting ? 0.5 : 1)
    }

    // MARK: 挂机监听开关卡
    private var monitorToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: settings.backgroundMonitor ? "eye.fill" : "eye")
                .font(.system(size: 13))
                .foregroundColor(settings.backgroundMonitor ? th.accent : th.text3)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("挂机监听")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(th.text)
                Text(settings.backgroundMonitor ? "开播自动采诗 · 停播自动收卷" : "未开启")
                    .font(.system(size: 10))
                    .foregroundColor(th.text2)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { settings.backgroundMonitor },
                set: { settings.backgroundMonitor = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(th.panel.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(th.border, lineWidth: 0.5))
    }

    // MARK: 底部快捷行
    private var footer: some View {
        HStack(spacing: 6) {
            footerButton("打开主窗", icon: "macwindow") { LefuApp.showMain() }
            footerButton("成品", icon: "folder") { session.openOutputFolder() }
            Spacer()
            footerButton("退出", icon: "power") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(th.text2)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(th.panel2.opacity(0.7)))
        }
        .buttonStyle(.plain)
    }
}
