import SwiftUI
import UniformTypeIdentifiers

// MARK: - 裁曲 · 长录音裁成单曲
struct ReworkView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController
    @Environment(\.lefuTheme) var th
    @State private var isOver = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dropZone
                .padding(.top, 16)

            HStack(spacing: 10) {
                paramField("最短收录时长") {
                    Picker("", selection: Binding(get: { settings.minLength }, set: { settings.minLength = $0 })) {
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                        Text("120 秒").tag(120)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                paramField("歌词来源") {
                    Picker("", selection: Binding(get: { settings.offlineMode }, set: { settings.offlineMode = $0 })) {
                        Text("本地优先").tag(false)
                        Text("仅本地").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                paramField("默认格式") {
                    Picker("", selection: Binding(get: { settings.format }, set: { settings.format = $0 })) {
                        ForEach(AppSettings.OutputFormat.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
            .padding(.vertical, 14)

            HStack {
                Text("裁曲进度").font(.system(size: 13, weight: .medium)).foregroundColor(th.text)
                Spacer()
                Text("切段 → 歌词 → 编码 → 标签").font(.system(size: 11)).foregroundColor(th.text3)
            }
            .padding(.bottom, 8)

            if session.cutTasks.isEmpty {
                emptyRework
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                progressHeader
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(session.cutTasks) { task in
                                taskRow(task)
                                    .id(task.id)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(activeID == task.id ? th.panel2 : th.panel)
                                            .opacity(activeID == task.id ? 1 : 0.8)
                                    )
                            }
                        }
                        .padding(2)
                    }
                    .onChange(of: activeID) { id in
                        if let id = id {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: session.cutTasks.count) { _ in
                        if let last = session.cutTasks.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                Button {
                    startRework()
                } label: {
                    if isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("裁曲中…")
                        }
                    } else {
                        Text("开始裁曲")
                    }
                }
                .buttonStyle(PillStyle(theme: th, kind: .primary))
                .disabled(isRunning || session.reworkFileURL == nil)
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 18)
        .background(th.bg)
    }

    // MARK: 运行状态
    private var isRunning: Bool { session.activeCutter != nil }

    private var activeID: Int? {
        session.cutTasks.first {
            ![.done, .skipped, .failed].contains($0.stage)
        }?.id
    }

    // MARK: 总进度头部（进行中=进度条；完成=绿色横幅）
    private var progressHeader: some View {
        let total = session.cutTasks.count
        let done = session.cutTasks.filter { $0.stage == .done }.count
        let skipped = session.cutTasks.filter { $0.stage == .skipped }.count
        let failed = session.cutTasks.filter { $0.stage == .failed }.count
        let processed = done + skipped + failed
        let running = processed < total
        return VStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: running ? "scissors" : "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundColor(running ? th.accent : th.ok)
                Text(running ? "正在裁曲" : "裁曲完成")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(running ? th.accent : th.ok)
                Spacer()
                if running {
                    Text("\(processed) / \(total)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(th.text2)
                } else {
                    Text("成功 \(done) · 跳过 \(skipped) · 失败 \(failed)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(th.text2)
                }
            }
            if running {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(th.panel2)
                        Capsule()
                            .fill(th.accent)
                            .frame(width: g.size.width * (total > 0 ? Double(processed) / Double(total) : 0))
                    }
                }
                .frame(height: 4)
            } else {
                HStack {
                    Button("打开输出目录") {
                        NSWorkspace.shared.open(settings.resolvedOutputDir.appendingPathComponent("裁曲"))
                    }
                    .buttonStyle(PillStyle(theme: th, kind: .normal))
                    Button("清空重来") {
                        session.cutTasks = []
                        session.reworkFileURL = nil
                    }
                    .buttonStyle(PillStyle(theme: th, kind: .normal))
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(th.panel.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(running ? th.accent.opacity(0.4) : th.ok.opacity(0.4), lineWidth: 0.8))
        .padding(.bottom, 8)
    }

    private func taskRow(_ task: CutTask) -> some View {
        let isSkip = task.stage == .skipped
        let isFail = task.stage == .failed
        return HStack(spacing: 10) {
            Text(String(format: "%02d", task.id + 1))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(th.text3)
            if let cover = task.entry.cover, let img = NSImage(data: cover) {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .opacity(isSkip ? 0.5 : 1)
            }
            Text(task.entry.title).font(.system(size: 13)).foregroundColor(isSkip ? th.text3 : th.text).lineLimit(1)
            if !task.entry.artist.isEmpty {
                Text(task.entry.artist).font(.system(size: 11)).foregroundColor(th.text3).lineLimit(1)
            }
            Spacer()
            if task.stage == .done, task.sizeBytes > 0 {
                Text(String(format: "%.1f MB", Double(task.sizeBytes) / 1048576))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(th.text3)
            }
            Text(task.stageLabel)
                .font(.system(size: 11, weight: isSkip ? .regular : .medium))
                .foregroundColor(task.stage == .done ? th.ok : (isFail ? th.live : th.skip))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .opacity(isSkip ? 0.55 : 1)
    }

    // 空态：三步流程说明
    private var emptyRework: some View {
        VStack(spacing: 14) {
            Spacer()
            HStack(spacing: 10) {
                reworkStep(1, icon: "square.and.arrow.down.on.square", title: "拖入录音", desc: "采诗页的整场录音 WAV")
                reworkArrow
                reworkStep(2, icon: "list.number", title: "识别时间轴", desc: "自动读取同名 .jsonl 切歌点")
                reworkArrow
                reworkStep(3, icon: "scissors", title: "按歌裁出单曲", desc: "切段 → 配词 → 编码 → 标签")
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(th.text3)
                Text("没有时间轴的录音也能裁——按静音段落自动分曲")
                    .font(.system(size: 11))
                    .foregroundColor(th.text3)
            }
            Spacer()
        }
    }

    private func reworkStep(_ n: Int, icon: String, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(th.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(th.panel2))
                Text("STEP \(n)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(th.text3)
                    .tracking(1)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(th.text)
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(th.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(th.panel.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(th.border, lineWidth: 0.5))
    }

    private var reworkArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(th.text3)
    }

    // 拖放区
    private var dropZone: some View {
        Button {
            pickFile()
        } label: {
            VStack(spacing: 8) {
                if let url = session.reworkFileURL {
                    Image(systemName: "waveform.badge.checkmark")
                        .font(.system(size: 26))
                        .foregroundColor(th.ok)
                    Text(url.lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(th.text)
                        .lineLimit(1)
                    Text("已选录音 · 点按可更换")
                        .font(.system(size: 11))
                        .foregroundColor(th.text3)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 26))
                        .foregroundColor(th.accent)
                    Text(isOver ? "松开导入" : "把录音 WAV 拖进来，或点击选择")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(th.text)
                    Text("支持带时间轴 .jsonl —— 有时间轴就能按歌精确裁，没有就按静音自动裁")
                        .font(.system(size: 11))
                        .foregroundColor(th.text3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(RoundedRectangle(cornerRadius: 12).fill(isOver ? th.panel2 : th.panel))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(session.reworkFileURL != nil ? th.ok : th.accent,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .opacity(session.reworkFileURL != nil ? 0.9 : (isOver ? 1 : 0.6))
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL], isTargeted: $isOver) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { session.reworkFileURL = url }
        }
        return true
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                session.reworkFileURL = url
            }
        }
    }

    private func paramField(_ k: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.system(size: 11)).foregroundColor(th.text3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(th.panel))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(th.border, lineWidth: 0.5))
    }

    private func startRework() {
        guard let url = session.reworkFileURL else {
            session.showToast("先选一个录音文件")
            return
        }
        guard !isRunning else { return }
        session.cutTasks = [] // 清掉上一轮任务，避免新旧混排
        // 解析时间轴：同名 .jsonl → 录制器产物 timeline_<时间戳>.jsonl（epoch 自动换算）
        let entries = loadTimeline(for: url)
        if entries.isEmpty {
            // 兜底：没有时间轴就按静音间隙切分（Python 早期静音切分思路：长静音取中点做切点）
            session.showToast("未找到时间轴，按静音间隙自动切分…")
            let fallback = SilenceSplitter.split(wavURL: url, minSegment: Double(settings.minLength))
            if fallback.isEmpty {
                session.showToast("没切出任何分段（录音过短或全是静音）")
                return
            }
            runCutter(wav: url, entries: fallback)
            return
        }
        runCutter(wav: url, entries: entries)
    }

    // MARK: 时间轴发现与解析（兼容录制器 session_*.wav + timeline_*.jsonl + .epoch）
    private func loadTimeline(for wav: URL) -> [TimelineEntry] {
        let dir = wav.deletingLastPathComponent()
        let stem = wav.deletingPathExtension().lastPathComponent
        // 1) 候选 jsonl：同名 → 同目录 timeline_<时间戳>.jsonl → 上级目录
        var candidates = [wav.deletingPathExtension().appendingPathExtension("jsonl")]
        if let ts = timestamp(in: stem) {
            candidates.append(dir.appendingPathComponent("timeline_\(ts).jsonl"))
            candidates.append(dir.deletingLastPathComponent().appendingPathComponent("timeline_\(ts).jsonl"))
        }
        guard let jsonl = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let raw = try? String(contentsOf: jsonl, encoding: .utf8) else { return [] }

        // 2) 开录基准：同名 .epoch（精确）→ 文件名时间戳兜底
        var recEpoch: Double?
        if let s = try? String(contentsOfFile: wav.path + ".epoch", encoding: .utf8),
           let v = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            recEpoch = v
        }
        if recEpoch == nil, let ts = timestamp(in: stem) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd_HHmmss"
            f.timeZone = .current
            if let d = f.date(from: ts) { recEpoch = d.timeIntervalSince1970 }
        }

        // 3) 逐行解析 + 合并同歌重复上报（与 engine/soda_split_v2.py 同规则）
        var events: [[String: Any]] = []
        for line in raw.components(separatedBy: .newlines) where !line.isEmpty {
            if let d = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                events.append(obj)
            }
        }
        var merged: [[String: Any]] = []
        for ev in events {
            if let prev = merged.last,
               (ev["replay"] as? Bool) != true,
               ev["title"] as? String == prev["title"] as? String,
               ev["artist"] as? String == prev["artist"] as? String,
               let pd = (prev["duration"] as? NSNumber)?.doubleValue, pd > 0,
               let e1 = (prev["epoch"] as? NSNumber)?.doubleValue,
               let e2 = (ev["epoch"] as? NSNumber)?.doubleValue,
               e2 - e1 <= pd + 5 {
                continue
            }
            merged.append(ev)
        }

        // 4) 转 TimelineEntry：t = epoch − 开录基准；artwork 文件读为 cover 数据
        let artDir = jsonl.deletingLastPathComponent()
            .appendingPathComponent(jsonl.deletingPathExtension().lastPathComponent + ".artworks")
        var entries: [TimelineEntry] = []
        for ev in merged {
            let t: Double
            if let v = (ev["t"] as? NSNumber)?.doubleValue {
                t = v
            } else if let ep = (ev["epoch"] as? NSNumber)?.doubleValue, let base = recEpoch {
                t = max(ep - base, 0)
            } else {
                continue
            }
            var cover: Data?
            if let art = ev["artwork"] as? String {
                cover = try? Data(contentsOf: artDir.appendingPathComponent(art))
            }
            entries.append(TimelineEntry(t: t,
                                         title: ev["title"] as? String ?? "",
                                         artist: ev["artist"] as? String ?? "",
                                         album: ev["album"] as? String ?? "",
                                         duration: (ev["duration"] as? NSNumber)?.doubleValue ?? 0,
                                         cover: cover))
        }
        return entries.sorted { $0.t < $1.t }
    }

    private func timestamp(in stem: String) -> String? {
        guard let r = stem.range(of: "\\d{8}_\\d{6}", options: .regularExpression) else { return nil }
        return String(stem[r])
    }

    private func runCutter(wav url: URL, entries: [TimelineEntry]) {
        settings.format = settings.format // 触发刷新
        let cutter = Cutter(wavURL: url, outDir: settings.resolvedOutputDir.appendingPathComponent("裁曲"), settings: settings)
        session.activeCutter = cutter // 异步期间持有，防止释放
        cutter.onTaskUpdate = { task in
            if let i = session.cutTasks.firstIndex(where: { $0.id == task.id }) {
                session.cutTasks[i] = task
            } else {
                session.cutTasks.append(task)
            }
        }
        cutter.onAllDone = { tasks in
            DispatchQueue.main.async {
                let done = tasks.filter { $0.stage == .done }.count
                session.showToast("裁曲完成 · \(done) 首已入库")
                session.activeCutter = nil
            }
        }
        cutter.run(entries: entries)
    }
}
