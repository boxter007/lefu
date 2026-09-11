import SwiftUI
import UniformTypeIdentifiers
import LefuCore

// MARK: - 设置（多分区表单）
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController
    @Environment(\.lefuTheme) var th

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                groupTitle("录制")
                group {
                    toggleRow("挂机监听", "检测到所选音源开播自动开录，停播自动收卷（关窗后菜单栏常驻）", $settings.backgroundMonitor)
                    toggleRow("无声自动停", "连续静音 1 分钟自动结束录制（歌间串场不会误触发）", $settings.silenceAutoStop)
                    pickerRow("最短收录时长", "低于此时长的段落丢弃") {
                        Picker("", selection: Binding(get: { settings.minLength }, set: { settings.minLength = $0 })) {
                            Text("30 秒").tag(30); Text("60 秒").tag(60); Text("120 秒").tag(120)
                        }.pickerStyle(.menu).frame(width: 90)
                    }
                    pathRow
                    pickerRow("默认格式", "MP3 320k 兼容性最好；M4A 体积更小") {
                        Picker("", selection: Binding(get: { settings.format }, set: { settings.format = $0 })) {
                            ForEach(AppSettings.OutputFormat.allCases, id: \.self) { f in
                                Text(f.label).tag(f)
                            }
                        }.pickerStyle(.segmented).frame(width: 290)
                    }
                }

                groupTitle("音源")
                group {
                    Text("只录制勾选的软件，避免误录视频/播客")
                        .font(.system(size: 11))
                        .foregroundColor(th.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                    ForEach(SourceRegistry.shared.allProfiles) { p in
                        row(p.displayName, icon: p.symbolName) {
                            Toggle("", isOn: sourceBinding(p))
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }

                groupTitle("歌词与封面")
                group {
                    toggleRow("离线模式", "只用本地歌词缓存，不联网", $settings.offlineMode)
                    toggleRow("缺词联网兜底", "本地没有时按 LRCLIB → 网易云 顺序抓取", $settings.lyricFallback)
                    row("封面") {
                        Text("✓ 始终开启").font(.system(size: 11)).foregroundColor(th.ok)
                    }
                }

                groupTitle("引擎（高级）")
                group {
                    envRow
                    row("版本", sub: "乐府当前安装版本") {
                        Text(AppInfo.versionText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(th.text2)
                            .textSelection(.enabled)
                    }
                    row("诊断日志") {
                        Button("导出") { exportDiag() }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }

                groupTitle("外观")
                group {
                    row("主题", sub: "跟随系统深浅色切换") {
                        Picker("", selection: Binding(get: { settings.themeMode }, set: { settings.themeMode = $0 })) {
                            ForEach(ThemeMode.allCases, id: \.self) { m in
                                Text(m.label).tag(m)
                            }
                        }.pickerStyle(.segmented).frame(width: 220)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(th.bg)
    }

    // MARK: 行组件
    private func groupTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .medium)).foregroundColor(th.text2).padding(.bottom, 8)
    }

    private func group(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 10).fill(th.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(th.border, lineWidth: 0.5))
            .padding(.bottom, 14)
    }

    private func row(_ k: String, sub: String? = nil, icon: String? = nil, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(th.text2)
                            .frame(width: 16)
                    }
                    Text(k).font(.system(size: 13)).foregroundColor(th.text)
                }
                if let sub { Text(sub).font(.system(size: 11)).foregroundColor(th.text2) }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func toggleRow(_ k: String, _ d: String, _ binding: Binding<Bool>) -> some View {
        row(k, sub: d) {
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    /// 音源勾选绑定：切换时按登记处顺序回写 enabledSourceIDs（不强制至少一项）
    private func sourceBinding(_ p: SourceProfile) -> Binding<Bool> {
        Binding(
            get: { settings.enabledSourceIDs.contains(p.id.raw) },
            set: { on in
                var s = Set(settings.enabledSourceIDs)
                if on { s.insert(p.id.raw) } else { s.remove(p.id.raw) }
                settings.enabledSourceIDs = SourceRegistry.shared.allProfiles.map { $0.id.raw }.filter { s.contains($0) }
            }
        )
    }

    private func pickerRow(_ k: String, _ d: String, @ViewBuilder picker: () -> some View) -> some View {
        row(k, sub: d) { picker() }
    }

    private var pathRow: some View {
        row("输出位置", sub: "按日期自动建子目录") {
            Text(settings.outputDir)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(th.ok)
            Button("更改") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.begin { resp in
                    if resp == .OK, let url = panel.url {
                        settings.outputDir = url.path
                        session.refreshLibrary() // 换目录后府库统计立即重扫
                    }
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
        }
    }

    private var envRow: some View {
        row("环境自检", sub: "BlackHole 驱动 / 采诗通道 / MP3 编码器 / 放音路由") {
            HStack(spacing: 8) {
                ForEach(session.envChecks) { c in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(envColor(c.status))
                            .frame(width: 6, height: 6)
                        Text(envLabel(c))
                            .font(.system(size: 11))
                            .foregroundColor(envColor(c.status))
                    }
                }
                Button("重新检查") {
                    session.runEnvCheck()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    private func envColor(_ s: EnvCheck.Status) -> Color {
        switch s {
        case .pending: return th.text3
        case .checking: return th.accentText
        case .ok: return th.ok
        case .fail: return Color(red: 0xE2/255, green: 0x4B/255, blue: 0x4A/255)
        }
    }

    private func envLabel(_ c: EnvCheck) -> String {
        let names = ["blackhole": "BlackHole", "channel": "采诗通道", "encoder": "编码器", "route": "放音路由"]
        var s = names[c.id] ?? c.id
        switch c.status {
        case .checking: s += " · 检查中"
        case .fail: s += c.note.isEmpty ? " · 未通过" : " · \(c.note)"
        default: break
        }
        return s
    }

    // MARK: 诊断日志导出
    private func exportDiag() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "乐府诊断-\(f.string(from: Date())).txt"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            var lines: [String] = []
            lines.append("乐府 诊断日志 · \(f.string(from: Date()))")
            lines.append("版本: \(AppInfo.versionText)")
            lines.append("")
            lines.append("— 环境 —")
            for c in session.envChecks {
                let s: String
                switch c.status {
                case .pending: s = "待检"
                case .checking: s = "检查中"
                case .ok: s = "✓"
                case .fail: s = "✗ \(c.note)"
                }
                lines.append("  \(c.id): \(s)")
            }
            lines.append("")
            lines.append("— 设置 —")
            lines.append("主题: \(settings.themeMode.rawValue)")
            lines.append("输出位置: \(settings.outputDir)")
            lines.append("默认格式: \(settings.format.rawValue)")
            lines.append("无声自动停: \(settings.silenceAutoStop ? "开" : "关")")
            lines.append("挂机监听: \(settings.backgroundMonitor ? "开" : "关")")
            lines.append("离线模式: \(settings.offlineMode ? "开" : "关")")
            lines.append("缺词联网兜底: \(settings.lyricFallback ? "开" : "关")")
            lines.append("最短收录: \(settings.minLength) 秒")
            lines.append("")
            lines.append("— 府库 —")
            lines.append("今日采得: \(session.library.todayCount) 首 · \(String(format: "%.1f", Double(session.library.todayBytes) / 1024 / 1024)) MB")
            lines.append("府库总量: \(String(format: "%.1f", Double(session.library.totalBytes) / 1024 / 1024)) MB")
            lines.append("最近成品: \(session.library.recent.count) 条")
            for item in session.library.recent {
                lines.append("  \(item.name) (\(String(format: "%.1f", Double(item.size) / 1024 / 1024)) MB)")
            }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
