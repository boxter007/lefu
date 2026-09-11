import SwiftUI
import AppKit

struct LibraryGrid: View {
    @ObservedObject var session: SessionController
    @Environment(\.lefuTheme) var th
    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 16)]

    var body: some View {
        ScrollView {
            if session.library.all.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list").font(.system(size: 28)).foregroundColor(th.text3)
                    Text("府库还空着").font(.lefu(.body)).foregroundColor(th.text2)
                }.frame(maxWidth: .infinity).padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(session.library.all) { item in
                        LibraryCell(item: item, theme: th)
                    }
                }.padding(20)
            }
        }
        .background(th.bg)
    }
}

private struct LibraryCell: View {
    let item: OutputItem
    let theme: LefuTheme
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.panel2)
                if let cover = item.cover {
                    Image(nsImage: cover).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.system(size: 24)).foregroundColor(theme.text3)
                }
            }
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: hover ? theme.shadow : .clear, radius: 10, y: 4)
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hover)
            Text(item.name).font(.lefu(.callout)).foregroundColor(theme.text).lineLimit(1)
        }
        .onHover { hover = $0 }
        .contextMenu {
            Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.id]) }
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.id) }
    }
}
