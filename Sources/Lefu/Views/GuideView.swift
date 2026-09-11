import SwiftUI

// MARK: - 指南页（操作引导 + 常见问题）
struct GuideView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: SessionController
    @Environment(\.lefuTheme) var th

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                routeCard
                sectionTitle("三步上手")
                stepCard(1, "准备环境", "环境自检没全绿时，引导页会带你装 BlackHole 驱动、接通采诗通道。采诗通道是音频 MIDI 设置里的一个「多输出设备」，第一次需要手工建（乐府会自动打开设置页并给出口径），建一次终身生效，无需管理员密码。") {
                    Button("查看环境自检") { session.runEnvCheck() }
                        .buttonStyle(.link).font(.system(size: 11))
                }
                stepCard(2, "开始采诗", "在你的音乐软件里放歌，回到乐府点大圆环「开始采诗」。切歌会自动实时裁歌入库；想连续挂机就打开「挂机监听」，开播自动采、停播自动收卷。") {
                    if session.state == .live {
                        Button("收卷") { session.stopAndCut() }
                            .buttonStyle(.link).font(.system(size: 11))
                    } else {
                        Button("开始采诗") { session.startSession() }
                            .buttonStyle(.link).font(.system(size: 11))
                    }
                }
                sectionTitle("它怎么工作")
                principleCard
                sectionTitle("常见问题")
                faqCard("录出来是静音？", "放音路由没接通。系统输出必须是「乐府 通道」多输出设备。看本页顶部的「采诗通道」卡：状态徽章显示未接通时，按卡里的三步建好，状态会实时变绿。")
                faqCard("听不见歌了？", "说明系统输出被切到了 BlackHole 本体（虚拟黑洞，无声）或别的设备。到系统设置（或音频 MIDI 设置）把输出切回「乐府 通道」，乐府的放音路由状态会实时恢复绿灯。")
                faqCard("歌词是空的？", "歌词按 本地歌词 -> 自家缓存 -> LRCLIB -> 网易云 顺序抓取。纯器乐或小众歌可能全网没有；联网抓到过的歌会存进缓存，之后离线也有。")
                faqCard("需要装什么软件？", "什么都不用。MP3 编码器（LAME）已内置在 App 里，歌词零依赖，BlackHole 会引导你安装。")
                faqCard("没开播会怎样？", "开着挂机监听它就一直待命；没开播时菜单栏面板显示「府中清静」。挂机监听关着的话，点开始采诗才会录。")
                faqCard("成品在哪？", "默认在 ~/Music/乐府，按日期分文件夹，MP3 已内嵌封面和标签，同目录附 .lrc 歌词。可在设置页改输出位置。")
                sectionTitle("快捷操作")
                shortcutsCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(th.bg)
    }

    // MARK: 头图
    private var hero: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(
                    LinearGradient(colors: [th.accent.opacity(0.2), th.live.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                ).frame(width: 56, height: 56)
                Image(systemName: "book.pages")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(th.accentText)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("乐府指南")
                    .font(.lefu(.title2))
                    .foregroundColor(th.text)
                Text("从零环境到出成品，五分钟跑通全程")
                    .font(.lefu(.callout))
                    .foregroundColor(th.text2)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(th.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(th.border, lineWidth: 0.5))
        .padding(.bottom, 16)
    }

    // MARK: 采诗通道卡（置顶必读：为什么手动建 + 怎么建 + 实时状态）
    private let failRed = Color(red: 0xE2/255, green: 0x4B/255, blue: 0x4A/255)

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(
                        LinearGradient(colors: [th.accent.opacity(0.22), th.live.opacity(0.14)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    ).frame(width: 44, height: 44)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(th.accentText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("采诗通道 · 需要你手动建一次")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(th.text)
                    Text("最重要的一步：一次配置，终身生效")
                        .font(.system(size: 11))
                        .foregroundColor(th.text2)
                }
                Spacer()
                routeStatusBadge
            }

            // 原理对比：为什么不能全自动
            VStack(alignment: .leading, spacing: 6) {
                routeCompare(ok: false, icon: "rectangle.split.2x1",
                             title: "程序自动建的「聚合设备」——不行",
                             desc: "macOS 公开接口建的聚合是「通道拼接」：立体声只进主设备，另一路永远静音，怎么调参数都是跷跷板")
                routeCompare(ok: true, icon: "hifispeaker.2",
                             title: "音频 MIDI 设置建的「多输出设备」——正解",
                             desc: "系统私有实现：同一份声音复制到扬声器和 BlackHole 两路，边听边录两全")
            }

            Divider().overlay(th.border)

            // 三步操作
            VStack(alignment: .leading, spacing: 8) {
                Text("怎么建（30 秒）")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(th.text)
                routeStep(1, icon: "plus.app", text: "打开音频 MIDI 设置，点左下角 ＋ → 创建多输出设备")
                routeStep(2, icon: "checkmark.square", text: "勾选 Mac mini扬声器 和 BlackHole 2ch；主设备选扬声器；BlackHole 勾上「漂移修正」")
                routeStep(3, icon: "character.cursor.ibeam", text: "左侧双击改名为「乐府 通道」（一字不差）——建好乐府自动认出，状态实时变绿")
            }

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.app")
                    Text("打开音频 MIDI 设置")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(th.accentContrast)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(th.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(th.panel))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(th.accent.opacity(0.4), lineWidth: 1))
        .padding(.bottom, 16)
    }

    // 实时状态徽章（随 CoreAudio 监听自动刷新）
    private var routeStatusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(session.routeReady ? th.ok : failRed)
                .frame(width: 7, height: 7)
            Text(session.routeReady ? "已接通" : "未接通")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(session.routeReady ? th.ok : failRed)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill((session.routeReady ? th.ok : failRed).opacity(0.1)))
    }

    private func routeCompare(ok: Bool, icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundColor(ok ? th.ok : failRed)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(ok ? th.ok : failRed)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(th.text)
                }
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(th.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(th.panel2))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(th.border, lineWidth: 0.5))
    }

    private func routeStep(_ n: Int, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(th.accentContrast)
                .frame(width: 20, height: 20)
                .background(Circle().fill(th.accent))
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(th.accentText)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(th.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .medium)).foregroundColor(th.text2).padding(.bottom, 8)
    }

    // MARK: 步骤卡
    private func stepCard(_ n: Int, _ k: String, _ d: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(th.accentContrast)
                .frame(width: 26, height: 26)
                .background(Circle().fill(th.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(k).font(.system(size: 13, weight: .semibold)).foregroundColor(th.text)
                Text(d).font(.lefu(.callout)).foregroundColor(th.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(th.panel))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(th.border, lineWidth: 0.5))
        .padding(.bottom, 8)
    }

    // MARK: 原理卡
    private var principleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            flowRow(icon: "music.note", title: "你的音乐软件", desc: "正常放歌，输出走「乐府 通道」")
            arrowDown
            HStack(spacing: 10) {
                flowNode(icon: "waveform.badge.plus", title: "BlackHole", desc: "乐府从这里录", tint: th.live)
                flowNode(icon: "hifispeaker", title: "扬声器", desc: "你照常听", tint: th.accentText)
            }
            flowRow(icon: "scissors", title: "实时裁歌", desc: "按切歌点切段 → 配歌词 → 编码 → 写标签封面 → 入库")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(th.panel.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(th.border, lineWidth: 0.5))
        .padding(.bottom, 14)
    }

    private var arrowDown: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(th.text3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, -2)
    }

    private func flowRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(th.accentText)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(th.panel2))
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(th.text)
            Text(desc).font(.system(size: 11)).foregroundColor(th.text3)
            Spacer()
        }
    }

    private func flowNode(icon: String, title: String, desc: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(th.panel2))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(th.text)
                Text(desc).font(.system(size: 10)).foregroundColor(th.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(th.panel))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(th.border, lineWidth: 0.5))
    }

    // MARK: FAQ 行
    @State private var openFAQ: Set<Int> = []
    private func faqCard(_ q: String, _ a: String) -> some View {
        let idx = faqIndex(q)
        let open = openFAQ.contains(idx)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if open { openFAQ.remove(idx) } else { openFAQ.insert(idx) }
            }
        } label: {
            VStack(alignment: .leading, spacing: open ? 6 : 0) {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .font(.system(size: 12))
                        .foregroundColor(th.accentText)
                    Text(q).font(.system(size: 13, weight: .medium)).foregroundColor(th.text)
                    Spacer()
                }
                if open {
                    Text(a)
                        .font(.lefu(.callout))
                        .foregroundColor(th.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(th.panel))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(th.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    private var faqOrder: [String] {
        ["录出来是静音？", "听不见歌了？", "歌词是空的？", "需要装什么软件？", "没开播会怎样？", "成品在哪？"]
    }
    private func faqIndex(_ q: String) -> Int {
        faqOrder.firstIndex(of: q) ?? q.hashValue
    }

    // MARK: 快捷操作
    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 14))
                    .foregroundColor(th.accentText)
                VStack(alignment: .leading, spacing: 1) {
                    Text("菜单栏控制台").font(.system(size: 12, weight: .semibold)).foregroundColor(th.text)
                    Text("关窗后乐府常驻菜单栏：看状态、收卷、开挂机监听都在那点").font(.system(size: 10)).foregroundColor(th.text3)
                }
                Spacer()
            }
            Divider().overlay(th.border)
            HStack(spacing: 10) {
                Image(systemName: "circle.and.line.horizontal")
                    .font(.system(size: 14))
                    .foregroundColor(th.accentText)
                VStack(alignment: .leading, spacing: 1) {
                    Text("下一阕").font(.system(size: 12, weight: .semibold)).foregroundColor(th.text)
                    Text("采诗中手动打点：当前歌从这句开始算作下一首").font(.system(size: 10)).foregroundColor(th.text3)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(th.panel))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(th.border, lineWidth: 0.5))
        .padding(.bottom, 8)
    }
}
