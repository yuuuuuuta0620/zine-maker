import AppKit
import SwiftUI

/// タブ列＋現在のドキュメント。ウインドウ全体の入れ物。
struct RootView: View {
    @ObservedObject var store: DocumentStore
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        Group {
            if let active = store.active {
                // NavigationSplitView はウインドウ直下に置く。
                // VStack で挟むとツールバーぶんの余白が二重に入り、
                // インスペクタの上に隙間ができてしまう。
                // タブはブラウザと同じくツールバー行に出す。
                ContentView(state: active, store: store)
                    .id(active.id)
            } else {
                WelcomeView(store: store)
            }
        }
        .frame(minWidth: 1180, minHeight: 800)
    }
}

// MARK: - タブ列

/// ブラウザのタブに寄せた見た目。
/// 選択中は明るい面で浮かせ、それ以外は地に沈める。枚数が増えると幅が縮む。
struct DocumentTabBar: View {
    @ObservedObject var store: DocumentStore
    @State private var hovering: UUID?

    private let height: CGFloat = 26
    private let maxWidth: CGFloat = 190
    private let minWidth: CGFloat = 76

    @Namespace private var glassNS

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(store.documents.enumerated()), id: \.element.id) { index, doc in
                            tab(doc, index: index)
                                .id(doc.id)
                        }
                    }
                    .padding(.horizontal, 2)
                    .glassGroup(spacing: 6)
                }
                .onChange(of: store.activeID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }

            Button {
                store.newDocument()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 26, height: height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassControl(cornerRadius: 7)
            .help("新しいドキュメント（⌘N）")
            .contextMenu {
                Button("新規 ZINE") { store.newDocument(kind: .zine) }
                Button("新規 組写真") { store.newDocument(kind: .board) }
                Divider()
                Button("開く…") { presentOpen() }
                if !RecentDocuments.urls.isEmpty {
                    Menu("最近使った項目") {
                        ForEach(RecentDocuments.urls, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) { store.open(url) }
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: 760)
    }

    /// タブが増えるほど幅を詰める
    private var tabWidth: CGFloat {
        let n = CGFloat(max(store.documents.count, 1))
        return max(minWidth, min(maxWidth, 700 / n))
    }

    private func tab(_ doc: AppState, index: Int) -> some View {
        _ = index
        let isActive = doc.id == store.activeID
        let isHover = hovering == doc.id
        return HStack(spacing: 5) {
            Image(systemName: doc.settings.kind.icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

            Text(doc.displayName)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            // 閉じる。触っていないときは未保存の点だけ出す
            ZStack {
                if isHover || isActive {
                    Button { _ = store.close(doc) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 15, height: 15)
                            .background(
                                Circle().fill(Color.primary.opacity(isHover ? 0.10 : 0))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("タブを閉じる（⌘W）")
                } else if doc.dirty {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                }
            }
            .frame(width: 16)
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(width: tabWidth, height: height)
        .tabSurface(isActive: isActive, isHover: isHover, id: doc.id, namespace: glassNS)
        .contentShape(Rectangle())
        .onTapGesture { store.select(doc) }
        .onHover { inside in hovering = inside ? doc.id : (hovering == doc.id ? nil : hovering) }
        .help(doc.fileURL?.path ?? doc.displayName)
        .contextMenu {
            Button("保存") { doc.saveDocument() }
            Button("別名で保存…") { doc.saveDocument(forceNewLocation: true) }
            Divider()
            Button("複製") { store.select(doc); store.duplicateActive() }
            if let url = doc.fileURL {
                Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            Button("閉じる") { _ = store.close(doc) }
            Button("ほかのタブを閉じる") {
                for other in store.documents where other.id != doc.id { _ = store.close(other) }
            }
        }
    }

    private func presentOpen() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = ["zine", "json"]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.open(url) }
    }
}

// MARK: - 何も開いていないとき

struct WelcomeView: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "book.pages")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.tertiary)
            VStack(spacing: 5) {
                Text("ZineMaker").font(.system(size: 20, weight: .medium))
                Text("写真のZINE・写真集・組写真を組む")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                start("ZINE・写真集", "book.closed", "見開き・塗り足し・入稿PDF") {
                    store.newDocument(kind: .zine)
                }
                start("組写真", "square.grid.2x2", "任意の比率・SNS向け") {
                    store.newDocument(kind: .board)
                }
            }
            .glassGroup(spacing: 14)

            if !RecentDocuments.urls.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近使った項目")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(RecentDocuments.urls.prefix(5), id: \.self) { url in
                        Button {
                            store.open(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc").font(.system(size: 10))
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 11))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 280)
                .padding(12)
                .glassPanel(cornerRadius: 12)
                .padding(.top, 6)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func start(_ title: String, _ icon: String, _ detail: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 20, weight: .light))
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(width: 176, height: 110)
            .glassControl(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}
