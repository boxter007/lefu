import SwiftUI
import LefuCore

// MARK: - 采诗 · 录制台（五态：待机/采录中/收卷裁曲中/本次完成 + 环境引导）
struct RecordView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController
    @Environment(\.lefuTheme) var th

    var body: some View {
        HStack(spacing: 0) {
            // 主区：四个状态的内容只占主要部分
            ZStack {
                switch session.state {
                case .idle: idleView
                case .live: liveView
                case .cutting: cuttingView
                case .done: doneView
                }
                if session.state == .idle && !guideDismissed {
                    if session.envChecks.contains(where: { $0.id == "blackhole" && $0.status == .fail }) {
                        envGuide
                    } else if session.envChecks.contains(where: { $0.id == "route" && $0.status == .fail }) {
                        routeGuide
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(th.border)

            // 右：府库栏常驻（待机/采录中/裁曲中/完成都在）
            libraryRail
                .frame(width: 272)
                .padding(.leading, 14)
                .padding(.vertical, 20)
                .padding(.trailing, 22)
        }
        // 有正在播放曲目时透出 RootView 的封面氛围背景；否则保持纯色页底
        .background(session.currentTrack == nil ? th.bg : Color.clear)
        .overlay {
            if let t = session.toast {
                toast(text: t)
            }
        }
    }

    // MARK: 待机
    @State private var ringHover = false
    @State private var guideDismissed = false
    @State private var previousTrackRowCount = 0   // 曲目列表自动滚底：记录上一次行数（onAppear 会按当前行数对齐）
    private var idleView: some View {
        VStack(spacing: 6) {
            startRing
            Text("开始采诗")
                .font(.lefu(.title2))
                .foregroundColor(th.text)
            Text("监听所选音源正在播放的内容，边听边录，已有的歌自动跳过")
                .font(.lefu(.callout))
                .foregroundColor(th.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 10) {
                ForEach(session.envChecks) { c in
                    envChip(c)
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var startRing: some View {
        Button {
            session.startSession()
        } label: {
            ZStack {
                // 呼吸光环 + 外圈（CA 层动画，不再逐帧 dirty 视图图）
                PulseHalo(color: th.accent)
                    .frame(width: 200, height: 200)
                PulseRing(color: th.accent.opacity(0.35))
                    .frame(width: 156, height: 156)
                Circle()
                    .fill(RadialGradient(colors: [th.panel2, th.panel], center: .topLeading, startRadius: 0, endRadius: 160))
                    .frame(width: 138, height: 138)
                    .overlay(Circle().stroke(th.border2, lineWidth: 1))
                Image(systemName: "play.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(th.accentText)
                    .offset(x: 3)
            }
            .frame(width: 200, height: 200)
            .scaleEffect(ringHover ? 1.05 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: ringHover)
            .shadow(color: th.accent.opacity(0.25), radius: 24, y: 8)
        }
        .buttonStyle(.plain)
        .onHover { ringHover = $0 }
        .padding(.bottom, 16)
    }

    // MARK: 府库右栏（常驻 · 只留两项核心统计 + 最近成品 6 条）
    private var libraryRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 今日采录：两项核心统计
            VStack(alignment: .leading, spacing: 12) {
                Text("今日采录")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(th.text)
                HStack(spacing: 0) {
                    railStat(icon: "music.note", value: "\(session.library.todayCount)", unit: "首")
                    Rectangle().fill(th.border).frame(width: 0.5, height: 32)
                    railStat(icon: "doc.fill", value: mb(session.library.todayBytes), unit: "MB")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .lefuCard(th, radius: 12)

            // 最近成品（限 6 条）
            VStack(alignment: .leading, spacing: 0) {
                Text("最近成品")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(th.text)
                    .padding(.bottom, 8)
                if session.library.recent.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "music.note.house")
                            .font(.system(size: 18))
                            .foregroundColor(th.text2)
                        Text("还没有采到歌，点中央开始")
                            .font(.system(size: 11))
                            .foregroundColor(th.text2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(session.library.recent.prefix(6))) { item in
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.id])
                                } label: {
                                    HStack(spacing: 8) {
                                        if let cover = item.cover {
                                            Image(nsImage: cover)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 28, height: 28)
                                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                        } else {
                                            Image(systemName: extIcon(item.id.pathExtension))
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(th.accentText)
                                                .frame(width: 28, height: 28)
                                                .background(RoundedRectangle(cornerRadius: 7).fill(th.panel2))
                                        }
                                        Text(item.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(th.text)
                                            .lineLimit(1)
                                        Spacer(minLength: 6)
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text(mbStr(item.size))
                                                .font(.system(size: 10.5, design: .rounded).monospacedDigit())
                                                .foregroundColor(th.text2)
                                            Text(timeAgo(item.date))
                                                .font(.system(size: 10))
                                                .foregroundColor(th.text2)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(th.panel.opacity(0.55)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .lefuCard(th, radius: 12)

            // 挂机监听快捷卡
            HStack(spacing: 8) {
                Image(systemName: settings.backgroundMonitor ? "eye.fill" : "eye")
                    .font(.system(size: 12))
                    .foregroundColor(settings.backgroundMonitor ? th.accentText : th.text2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("挂机监听")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(th.text)
                    Text("开播自动采诗")
                        .font(.system(size: 9))
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
            .lefuCard(th, radius: 12)
        }
    }

    private func railStat(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(th.accentText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(th.text)
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundColor(th.text2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func mb(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1024 / 1024)
    }
    private func mbStr(_ bytes: Int64) -> String {
        let m = Double(bytes) / 1024 / 1024
        return m >= 1 ? String(format: "%.1fM", m) : String(format: "%.0fK", Double(bytes) / 1024)
    }
    private func extIcon(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "MP3"
        case "m4a": return "M4A"
        case "flac": return "FLAC"
        default: return "WAV"
        }
    }
    private func timeAgo(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    private func envChip(_ c: EnvCheck) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colorForEnv(c.status)).frame(width: 6, height: 6)
            Text(labelForEnv(c))
                .font(.system(size: 11))
                .foregroundColor(colorForEnv(c.status))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 16).fill(th.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(th.border, lineWidth: 0.5))
    }

    private func colorForEnv(_ s: EnvCheck.Status) -> Color {
        switch s {
        case .pending, .checking: return th.text3
        case .ok: return th.ok
        case .fail: return Color(red: 0xE2/255, green: 0x4B/255, blue: 0x4A/255)
        }
    }

    private func labelForEnv(_ c: EnvCheck) -> String {
        let names = ["blackhole": "BlackHole 驱动", "channel": "采诗通道", "encoder": "MP3 编码器", "route": "放音路由"]
        var s = names[c.id] ?? c.id
        switch c.status {
        case .checking: s += " 检查中…"
        case .fail: s += c.note.isEmpty ? " ✗" : " · \(c.note)"
        default: break
        }
        return s
    }

    // MARK: 采录中（主卡片 → 会话队列 → 操作栏，阅读顺序连续）
    private var liveView: some View {
        VStack(spacing: 14) {
            // ① 主卡片：正在采录 + 曲目 + 歌词 + 波形 + 计时
            VStack(spacing: 0) {
                nowPlaying
                wave
                    .padding(.top, 14)
                HStack {
                    Text(session.elapsedText)
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundColor(th.text2)
                    Spacer()
                    Text(trackDurationText)
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundColor(th.text2)
                }
                .padding(.top, 8)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .lefuCard(th, radius: 12)

            // ② 会话队列
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("本次会话 · \(session.trackRows.count) 首")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(th.text)
                    Spacer()
                    Text("府中已有的歌曲自动跳过")
                        .font(.system(size: 11))
                        .foregroundColor(th.text2)
                }
                if session.trackRows.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 18))
                            .foregroundColor(th.text2)
                        Text("切到一首歌，这里就会开始记录")
                            .font(.system(size: 12))
                            .foregroundColor(th.text2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 5) {
                                ForEach(session.trackRows) { row in
                                    trackRow(row)
                                        .id(row.id)
                                }
                            }
                        }
                        .onAppear {
                            // 点红叉关窗后视图树被销毁，再打开时滚动位置归零 → 这里主动回到「正在采录的一行」，
                            // 而不是停在列表最顶部；顺带对齐行数基线，避免首次增长被误判。
                            // LazyVStack 首帧可能还没铺好目标行（上百行时更明显），两次尝试兜底
                            previousTrackRowCount = session.trackRows.count
                            guard let id = activeRowID else { return }
                            DispatchQueue.main.async {
                                proxy.scrollTo(id, anchor: .center)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                        .onChange(of: session.trackRows.count) { newCount in
                            // 新增行后自动滚到最底部的新行；仅在增长时触发（防收卷统计回写误滚）
                            guard newCount > previousTrackRowCount else { return }
                            previousTrackRowCount = newCount
                            if let last = session.trackRows.last {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .lefuCard(th, radius: 12)

            // ③ 操作栏：紧贴队列，主操作居中（裁曲已实时进行，收卷=停录+尾首入流水线）
            HStack(spacing: 12) {
                Button {
                    session.nextTrack()
                } label: {
                    Label("下一阕", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(theme: th, kind: .normal))

                Button {
                    session.stopAndCut()
                } label: {
                    Label("收卷", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(theme: th, kind: .danger))
            }
        }
        .padding(18)
    }

    private var trackDurationText: String {
        guard let d = session.currentTrack?.duration, d > 0 else { return "--:--:--" }
        let m = Int(d) / 60, s = Int(d) % 60
        return String(format: "%02d:%02d", m, s)
    }

    // 正在播放卡片
    private var nowPlaying: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(artColor).frame(width: 92, height: 92)
                if let img = session.artworkImage {
                    Image(nsImage: img).resizable().scaledToFill().frame(width: 92, height: 92).clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "music.note").font(.system(size: 30)).foregroundColor(.white.opacity(0.85))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("正在采录")
                    .font(.lefu(.subheadline).weight(.semibold))
                    .tracking(3)
                    .foregroundColor(th.accentText)
                // 以下各行全部固定高度 + 透明占位：内容来去布局纹丝不动
                Text(session.currentTrack?.title ?? "等待正在播放…")
                    .font(.lefu(.largeTitle))
                    .lineLimit(1)
                    .foregroundColor(th.text)
                    .frame(height: 38, alignment: .leading)
                Text(subText.isEmpty ? " " : subText)
                    .font(.lefu(.callout))
                    .lineLimit(1)
                    .foregroundColor(th.text2.opacity(subText.isEmpty ? 0 : 1))
                    .frame(height: 20, alignment: .leading)
                // 歌词双行（占位固定；整行滚动 + KRC 可选逐字高亮）
                let idx = session.lyricIndex
                let cur = session.lyrics.lines[safe: idx]
                let next = session.lyrics.lines[safe: idx + 1]
                lyricCurrentText(cur, nextStart: next?.start)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .frame(height: 22, alignment: .leading)
                Text(next?.text ?? " ")
                    .font(.lefu(.callout))
                    .lineLimit(1)
                    .foregroundColor(next == nil ? .clear : th.text2)
                    .frame(height: 19, alignment: .leading)
            }
            .animation(.easeInOut(duration: 0.3), value: session.lyricIndex)
            Spacer(minLength: 0)
        }
    }

    private var subText: String {
        guard let t = session.currentTrack else { return "" }
        return t.artist + (t.album.isEmpty ? "" : " · " + t.album)
    }

    // MARK: 歌词当前行（KRC 逐字：已唱亮、当前词强调、未唱暗；否则整行亮）
    private func lyricCurrentText(_ line: LyricLine?, nextStart: Double?) -> Text {
        guard let line else { return Text(" ").foregroundColor(.clear) }
        // 只在播放位置落在本行区间内才逐字；否则整行亮（防止行与时间基短暂错位）
        let inLine = songPos >= line.start && (nextStart.map { songPos < $0 } ?? true)
        guard !line.words.isEmpty, inLine else {
            return Text(line.text).foregroundColor(th.text)
        }
        var attr = AttributedString()
        for w in line.words {
            var part = AttributedString(w.text)
            part.foregroundColor = wordColor(w)
            attr += part
        }
        return Text(attr)
    }

    /// 逐字着色：已唱完亮、正在唱用强调色、未唱暗
    private func wordColor(_ w: LyricWord) -> Color {
        if songPos >= w.start + w.duration { return th.text }
        if songPos >= w.start { return th.accentText }
        return th.text2.opacity(0.55)
    }

    private var artColor: Color {
        let palette: [Color] = [th.accent, th.live, th.ok]
        let idx = abs((session.currentTrack?.key.hashValue ?? 0)) % palette.count
        return palette[idx]
    }

    // 波形（独立小视图，只订阅电平表：电平每秒 20+ 次刷新不再带着整个录制台重绘）
    private var wave: some View {
        LevelWave(meter: session.meter, theme: th)
    }

    // 序号列宽：随最大序号位数自适应（2 位 20pt，100+ 首时 3 位也不换行；所有行同宽不错位）
    private var seqColumnWidth: CGFloat {
        let maxID = session.trackRows.map(\.id).max() ?? 0
        let digits = max(2, String(maxID).count)
        return max(20, CGFloat(digits) * 7.4 + 2)
    }

    /// 正在采录的行号（没有采录中则取最后一行）：窗口关闭后再打开时用它把列表带回「当前这条」
    private var activeRowID: Int? {
        session.trackRows.last(where: { $0.status == .recording })?.id ?? session.trackRows.last?.id
    }

    // 曲目行（参考图样式：缩略图 + 序号 + 歌名 + 歌手 + 状态，行高加大）
    private func trackRow(_ row: TrackRow) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", row.id))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(th.text2)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: seqColumnWidth, alignment: .leading)
            // 封面缩略图
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(artColor(for: row))
                    .frame(width: 40, height: 40)
                if let img = row.artwork {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(th.text)
                HStack(spacing: 6) {
                    Text(rowSubtitle(row))
                        .font(.system(size: 11.5))
                        .foregroundColor(th.text2)
                        .lineLimit(1)
                    sourceBadge(row)
                }
            }
            Spacer(minLength: 10)
            // 右缘信息：采录中→播放进度/总时长；已收录→大小·时长；其余→工序进度
            rowTrailing(row)
            statusBadge(row.status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(th.panel))
        // 采录中的行：半透明薄框呼吸描边（自持动画生命周期，行中途出现也能动起来）
        .overlay {
            if row.status == .recording {
                BreathingStroke(color: th.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击行开 Finder：成品优先，未落盘先定位本首录音
            if let p = row.outputPath ?? row.wavPath {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
            }
        }
        .help(row.outputPath != nil ? "点击在 Finder 中显示成品" : "点击在 Finder 中显示本首录音")
    }

    /// 来源徽章：仅在启用多个音源时显示；单源（默认仅汽水）时不出现，保持原有视觉
    @ViewBuilder
    private func sourceBadge(_ row: TrackRow) -> some View {
        if settings.enabledSourceIDs.count > 1, let sourceName = row.sourceName {
            Text(sourceName)
                .font(.system(size: 10))
                .foregroundColor(th.text2)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(th.panel2))
        }
    }

    /// 行右缘信息文字
    @ViewBuilder
    private func rowTrailing(_ row: TrackRow) -> some View {
        switch row.status {
        case .recording:
            // 半路接入（本场第一首）：录制起点在歌中途，汽水不暴露播放位置，绝对进度不可知
            if row.midJoin {
                Text("--:-- / \(durText)")
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundColor(th.text3)
            } else {
                // 切歌打点的歌从 0 播：采录时长 + 确认前已播的头，夹在总时长内
                Text("\(mmss(songPos)) / \(durText)")
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundColor(th.accentText)
            }
        case .captured:
            Text(row.sizeBytes > 0 ? "✓ \(mbStr(row.sizeBytes)) · \(mmss(row.seconds))" : "✓ 完成")
                .font(.system(size: 11, design: .rounded).monospacedDigit())
                .foregroundColor(th.ok)
        default:
            if !row.stageLabel.isEmpty {
                Text(row.stageLabel)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundColor(stageColor(row))
            }
        }
    }

    private var durText: String {
        guard let d = session.currentTrack?.duration, d > 0 else { return "--:--" }
        return mmss(d)
    }

    /// 歌曲播放位置：采录时长 + 确认前已播的头；元信息总时长已知时夹在以内（防半路接入时超出总时长）
    private var songPos: Double {
        let pos = session.songOffset
        if let d = session.currentTrack?.duration, d > 0 { return min(pos, d) }
        return pos
    }

    private func mmss(_ t: Double) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// 进度文字颜色：完成绿 / 跳过灰绿 / 失败红 / 进行中珊瑚红
    private func stageColor(_ row: TrackRow) -> Color {
        if row.status == .captured { return th.ok }
        if row.status == .skipped { return th.skip }
        if row.stageLabel.contains("失败") { return failColor }
        return th.accentText
    }

    private func artColor(for row: TrackRow) -> Color {
        let palette: [Color] = [th.accent, th.live, th.ok]
        let idx = abs(row.title.hashValue) % palette.count
        return palette[idx].opacity(0.85)
    }

    /// 第二行副标题：歌手 · 专辑（缺项自动省略，全空显示 —）
    private func rowSubtitle(_ row: TrackRow) -> String {
        var parts: [String] = []
        if !row.artist.isEmpty { parts.append(row.artist) }
        if !row.album.isEmpty && row.album != row.title { parts.append(row.album) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statusBadge(_ s: TrackRow.Status) -> some View {
        switch s {
        case .recording:
            Label("采录中", systemImage: "circle.fill")
                .font(.system(size: 11))
                .foregroundColor(th.accentText)
        case .pending:
            Text("收卷中")
                .font(.system(size: 11))
                .foregroundColor(th.text2)
        case .processing:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16)
        case .captured:
            Label("已收录", systemImage: "checkmark")
                .font(.system(size: 11))
                .foregroundColor(th.ok)
        case .skipped:
            Text("⏭ 库中已有 · 跳过")
                .font(.system(size: 11))
                .foregroundColor(th.skip)
        }
    }

    // MARK: 收卷裁曲中
    private var failColor: Color { Color(red: 0xE2/255, green: 0x4B/255, blue: 0x4A/255) }

    private var cuttingView: some View {
        let total = session.cutTasks.count
        let processed = session.cutTasks.filter { [.done, .skipped, .failed].contains($0.stage) }.count
        let active = session.cutTasks.first { ![.done, .skipped, .failed].contains($0.stage) }
        let doneCount = session.cutTasks.filter { $0.stage == .done }.count
        let skipCount = session.cutTasks.filter { $0.stage == .skipped }.count
        let failCount = session.cutTasks.filter { $0.stage == .failed }.count
        let fraction = total > 0 ? Double(processed) / Double(total) : 0
        return VStack(spacing: 0) {
            // 顶部：标题 + 统计徽章
            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(th.accentText)
                Text("收卷裁曲")
                    .font(.lefu(.headline))
                    .tracking(4)
                    .foregroundColor(th.text)
                Spacer()
                if doneCount > 0 { statChip("\(doneCount) 成", color: th.ok) }
                if skipCount > 0 { statChip("\(skipCount) 跳过", color: th.skip) }
                if failCount > 0 { statChip("\(failCount) 失败", color: failColor) }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            // 中央：裁曲进度环
            VStack(spacing: 12) {
                ZStack {
                    // 封卷仪式：CA 层光环 + 外圈呼吸（沿用待机页「开始采诗」的同一套组件）
                    PulseHalo(color: th.accent)
                        .frame(width: 184, height: 184)
                    PulseRing(color: th.accent.opacity(0.35))
                        .frame(width: 144, height: 144)
                    ZStack {
                        Circle()
                            .stroke(th.border, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: max(0.02, fraction))
                            .stroke(
                                AngularGradient(colors: [th.accent.opacity(0.55), th.accent, th.live],
                                                center: .center,
                                                startAngle: .degrees(-90), endAngle: .degrees(270)),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
                        VStack(spacing: 1) {
                            Text("\(processed)")
                                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundColor(th.text)
                            Text(total > 0 ? "共 \(total) 阕" : "准备中")
                                .font(.system(size: 11))
                                .foregroundColor(th.text2)
                        }
                    }
                    .frame(width: 128, height: 128)
                }
                .frame(width: 184, height: 184)

                if let a = active {
                    VStack(spacing: 9) {
                        Text(a.entry.title)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(th.text)
                            .frame(maxWidth: 400)
                        HStack(spacing: 16) {
                            stageStep("切段", current: a.stage, target: .slice)
                            stageStep("编码", current: a.stage, target: .encode)
                            stageStep("签章", current: a.stage, target: .tags)
                            stageStep("歌词", current: a.stage, target: .lyrics)
                        }
                    }
                } else {
                    Text(total > 0 && processed >= total ? "收笔 · 正在整理入库" : "整备中…")
                        .font(.system(size: 13))
                        .foregroundColor(th.text2)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 20)

            // 曲目清单
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(session.cutTasks) { task in
                            cutRow(task, isActive: active?.id == task.id)
                                .id(task.id)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
                }
                .onChange(of: active?.id) { id in
                    if let id = id {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            Text("裁曲在后台进行，完成后自动入库 · 可先去忙别的")
                .font(.system(size: 10))
                .foregroundColor(th.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    // 单曲行：状态图标 + 歌名 + 阶段
    private func cutRow(_ task: CutTask, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            statusIcon(task.stage)
                .frame(width: 16)
            Text(task.entry.title)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .foregroundColor(th.text.opacity(isActive ? 1 : 0.82))
            Spacer(minLength: 8)
            Text(task.stageLabel)
                .font(.system(size: 11))
                .foregroundColor(colorForStage(task.stage))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? th.panel2 : th.panel.opacity(0.72))
        )
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle().fill(th.accent).frame(width: 2)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ stage: CutTask.Stage) -> some View {
        switch stage {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(th.ok)
        case .skipped:
            Image(systemName: "minus.circle").font(.system(size: 13)).foregroundColor(th.skip)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundColor(failColor)
        case .queue:
            Image(systemName: "circle.dashed").font(.system(size: 12)).foregroundColor(th.text2)
        default:
            ProgressView().controlSize(.mini)
        }
    }

    // 四道工序步骤（切段 → 编码 → 签章 → 歌词）
    private func stageStep(_ name: String, current: CutTask.Stage, target: CutTask.Stage) -> some View {
        let order: [CutTask.Stage] = [.slice, .encode, .tags, .lyrics]
        let curIdx = order.firstIndex(of: current)
        let tgtIdx = order.firstIndex(of: target) ?? 0
        let state = (curIdx != nil && tgtIdx < curIdx!) ? 2 : (current == target ? 1 : 0)
        return HStack(spacing: 4) {
            Circle()
                .fill(state == 2 ? th.ok : (state == 1 ? th.accent : th.border))
                .frame(width: 5, height: 5)
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(state == 0 ? th.text2 : (state == 1 ? th.accentText : th.ok))
        }
    }

    private func statChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func colorForStage(_ s: CutTask.Stage) -> Color {
        switch s {
        case .done: return th.ok
        case .failed: return failColor
        case .skipped: return th.skip
        case .queue: return th.text2
        default: return th.accentText
        }
    }

    // MARK: 本次完成
    /// 完成徽章主色：有成品用成功色，空手用跳过色（与徽章填充一致）
    private var doneAccent: Color { session.doneStats.count == 0 ? th.skip : th.ok }

    private var doneView: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                // 封卷仪式：完成徽章同样走 CA 层呼吸，与收卷进度环同一套组件
                PulseHalo(color: doneAccent)
                    .frame(width: 96, height: 96)
                PulseRing(color: doneAccent.opacity(0.35))
                    .frame(width: 76, height: 76)
                ZStack {
                    Circle().fill(doneAccent).frame(width: 64, height: 64)
                    Image(systemName: session.doneStats.count == 0 ? "tray" : "checkmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            Text(session.doneStats.count == 0 ? "没有采到成品" : "本次完成")
                .font(.lefu(.title2))
                .foregroundColor(th.text)
                .padding(.top, 12)
            Text(statsText)
                .font(.lefu(.callout))
                .foregroundColor(th.text2)
                .padding(.top, 4)
            if !skipSummary.isEmpty {
                Text(skipSummary)
                    .font(.system(size: 12))
                    .foregroundColor(th.text2)
                    .padding(.top, 6)
                    .padding(.horizontal, 30)
                    .multilineTextAlignment(.center)
            }

            ScrollView {
                VStack(spacing: 5) {
                    ForEach(session.doneStats.rows) { row in
                        HStack(spacing: 10) {
                            Text(String(format: "%02d", row.id - 999))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(th.text3)
                            Text(row.title).font(.system(size: 13)).foregroundColor(th.text).lineLimit(1)
                            sourceBadge(row)
                            Spacer()
                            Text(row.artist).font(.system(size: 11)).foregroundColor(th.text2)
                            Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(th.ok)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(th.panel))
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(maxHeight: 220)
            .padding(.top, 18)

            HStack(spacing: 10) {
                Button {
                    session.openOutputFolder()
                } label: { Text("打开文件夹") }
                .buttonStyle(PillStyle(theme: th, kind: .normal))
                Button {
                    session.reset()
                } label: { Text("返回首页") }
                .buttonStyle(PillStyle(theme: th, kind: .primary))
            }
            .padding(.vertical, 16)
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 18)
    }

    private var statsText: String {
        let s = session.doneStats
        var parts = ["采得 \(s.count) 首"]
        if s.skippedCount > 0 { parts.append("跳过 \(s.skippedCount)") }
        if s.failedCount > 0 { parts.append("失败 \(s.failedCount)") }
        parts.append(String(format: "%.1f", Double(s.sizeBytes) / 1024 / 1024) + " MB")
        parts.append("共 \(Int(s.seconds / 60)) 分钟")
        return parts.joined(separator: " · ")
    }

    // 跳过/失败的原因汇总（过短 / 静音 / 库中已有 / 失败）——逐首收卷后由统计承载，不再走 cutTasks
    private var skipSummary: String { "" }

    // MARK: 环境引导遮罩
    private var envGuide: some View {
        ZStack {
            th.bg.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(th.panel2).frame(width: 72, height: 72)
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 30))
                        .foregroundColor(th.accentText)
                }
                Text("先装一个 BlackHole")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(th.text)
                    .padding(.top, 16)
                Text("macOS 不允许直接录别的应用的声音，BlackHole 是免费开源的虚拟声卡。点下面一键安装，输一次管理员密码就好，之后不用再管。")
                    .font(.system(size: 12))
                    .foregroundColor(th.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 6)

                // 一键安装主按钮
                Button {
                    session.installBlackHole()
                } label: {
                    HStack(spacing: 8) {
                        if session.installingBlackHole {
                            ProgressView().controlSize(.small).tint(th.accentContrast)
                            Text("正在安装，请留意密码框…")
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("一键安装 BlackHole")
                        }
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(th.accentContrast)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 11)
                    .background(
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [th.accent, th.accent.opacity(0.82)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: th.accent.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(session.installingBlackHole)
                .padding(.top, 20)

                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://existential.audio/blackhole/")!)
                    } label: { Text("打开官网手动下载") }
                    .buttonStyle(PillStyle(theme: th, kind: .normal))
                    Button {
                        guideDismissed = true
                    } label: { Text("稍后再说") }
                    .buttonStyle(PillStyle(theme: th, kind: .normal))
                }
                .padding(.top, 14)
            }
        }
        .transition(.opacity)
    }


    // MARK: 采诗通道引导（驱动装好后的第二步）
    private var routeGuide: some View {
        ZStack {
            th.bg.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(th.panel2).frame(width: 72, height: 72)
                    Image(systemName: "hifispeaker.2")
                        .font(.system(size: 30))
                        .foregroundColor(th.accentText)
                }
                Text("接通采诗通道")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(th.text)
                    .padding(.top, 16)
                Text("还差最后一步：让你的音乐软件的声音同时进 BlackHole（乐府录）和扬声器（你听）。点下面会自动切好系统输出；若还没有多输出设备，会打开音频 MIDI 设置引导你建一个「\(AudioRouting.aggregateName)」（一次性操作）。")
                    .font(.system(size: 12))
                    .foregroundColor(th.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 6)

                Button {
                    session.setupAudioRoute()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                        Text("一键接通采诗通道")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(th.accentContrast)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 11)
                    .background(
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [th.accent, th.accent.opacity(0.82)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: th.accent.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)

                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                    } label: { Text("打开音频 MIDI 设置手动配") }
                    .buttonStyle(PillStyle(theme: th, kind: .normal))
                    Button {
                        guideDismissed = true
                    } label: { Text("稍后再说") }
                    .buttonStyle(PillStyle(theme: th, kind: .normal))
                }
                .padding(.top, 14)
            }
        }
        .transition(.opacity)
    }

    // MARK: Toast
    private func toast(text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(th.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(th.panel2))
                .overlay(Capsule().stroke(th.border2, lineWidth: 0.5))
                .padding(.bottom, 18)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - 呼吸描边（采录中行的半透明薄框）
// 动画交给 Core Animation 层（PulseBorder），不再用 SwiftUI repeatForever——
// 后者每帧 dirty 视图图，会把上百行会话队列所在的整棵树按 60Hz 重算根布局
struct BreathingStroke: View {
    let color: Color
    var body: some View {
        PulseBorder(color: color)
    }
}

// MARK: - 胶囊按钮
struct PillStyle: ButtonStyle {
    enum Kind { case normal, primary, danger }
    let theme: LefuTheme
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: kind == .normal ? .medium : .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(
                    kind == .primary ? LinearGradient(colors: [theme.accent, theme.accent.opacity(0.82)], startPoint: .top, endPoint: .bottom) :
                    kind == .danger ? LinearGradient(colors: [Color(red: 0xF0/255, green: 0x56/255, blue: 0x4A/255), Color(red: 0xD8/255, green: 0x3E/255, blue: 0x36/255)], startPoint: .top, endPoint: .bottom) :
                    LinearGradient(colors: [theme.panel2, theme.panel], startPoint: .top, endPoint: .bottom)
                )
            )
            .foregroundColor(kind == .normal ? theme.text : (kind == .primary ? theme.accentContrast : .white))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(kind == .normal ? theme.border2 : .clear, lineWidth: 0.5))
            .shadow(color: kind == .normal ? .clear : theme.shadow, radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - 安全下标（越界返回 nil：lyricIndex 可能是 -1，next 可能越界）
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
