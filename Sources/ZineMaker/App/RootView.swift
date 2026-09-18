import AppKit
import SwiftUI

/// タブ列＋現在のドキュメント。ウインドウ全体の入れ物。
struct RootView: View {
    @ObservedObject var store: DocumentStore
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        VStack(spacing: 0) {
            if !store.documents.isEmpty {
                DocumentTabBar(store: store)
                Divider()
            }
            if let active = store.active {
                ContentView(state: active)
                    .id(active.id)
            } else {
                WelcomeView(store: store)
            }
        }
        .frame(minWidth: 1180, minHeight: 800)
    }
}

// MARK: - タブ列

struct DocumentTabBar: View {
    @ObservedObject var store: DocumentStore
    @State private var hovering: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(store.documents) { doc in
                        tab(doc)
                    }
                }
                .padding(.horizontal, 6)
            }
            Divider().frame(height: 18)
            Menu {
                Button("新規 ZINE") { store.newDocument(kind: .zine) }
                Button("新規 組写真") { store.newDocument(kind: .board) }
                Divider()
                Button("開く…") { presentOpen() }
                if !RecentDocuments.urls.isEmpty {
                    Menu("最近使った項目") {
                        ForEach(RecentDocuments.urls, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) { store.open(url) }
                        }
                        Divider()
                        Button("メニューをクリア") { RecentDocuments.clear() }
                    }
                }
            } label: {
                Image(systemName: "plus")
            } primaryAction: {
                store.newDocument()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 34)
            .help("新しいドキュメント（⌘N）")
        }
        .frame(height: 34)
        .background(.bar)
    }

    private func tab(_ doc: AppState) -> some View {
        let isActive = doc.id == store.activeID
        return HStack(spacing: 5) {
            Image(systemName: doc.settings.kind.icon)
                .font(.system(size: 9))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            Text(doc.displayName)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .lineLimit(1)
            if doc.dirty {
                Circle().fill(.orange).frame(width: 5, height: 5)
            }
            Button {
                _ = store.close(doc)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering == doc.id || isActive ? 0.7 : 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .frame(minWidth: 110, maxWidth: 190)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor)
                               : (hovering == doc.id ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { store.select(doc) }
        .onHover { hovering = $0 ? doc.id : (hovering == doc.id ? nil : hovering) }
        .help(doc.fileURL?.path ?? doc.displayName)
        .contextMenu {
            Button("保存") { doc.saveDocument() }
            Button("別名で保存…") { doc.saveDocument(forceNewLocation: true) }
            Divider()
            Button("複製") { store.select(doc); store.duplicateActive() }
            if doc.fileURL != nil {
                Button("Finder で表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([doc.fileURL!])
                }
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

            HStack(spacing: 10) {
                start("ZINE・写真集", "book.closed", "見開き・塗り足し・入稿PDF") {
                    store.newDocument(kind: .zine)
                }
                start("組写真", "square.grid.2x2", "任意の比率・SNS向け") {
                    store.newDocument(kind: .board)
                }
            }

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
            .frame(width: 168, height: 104)
            .background(RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}
