import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var store: DocumentStore
    @State private var showingExport = false
    @State private var showingTemplates = false
    @State private var showingPreflight = false

    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        NavigationSplitView {
            Sidebar(state: state)
                .navigationSplitViewColumnWidth(min: 150, ideal: 168, max: 240)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !state.missingAssets.isEmpty { missingBanner }
                    CanvasContainer(state: state)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    PhotoTray(state: state)
                }
                Divider()
                Inspector(state: state)
            }
        }
        .toolbar { toolbarItems }
        .sheet(isPresented: $showingExport) { ExportSheet(state: state) }
        .sheet(isPresented: $showingTemplates) { TemplatePicker(state: state) }
        .sheet(isPresented: $showingPreflight) { PreflightSheet(state: state) }
        .safeAreaInset(edge: .bottom) { statusBar }
        .onReceive(NotificationCenter.default.publisher(for: .zineShowExport)) { _ in showingExport = true }
        .onReceive(NotificationCenter.default.publisher(for: .zineShowTemplates)) { _ in showingTemplates = true }
        .onReceive(NotificationCenter.default.publisher(for: .zineShowPreflight)) { _ in showingPreflight = true }
        .onChange(of: state.currentIndex) { _, _ in prefetchNeighbours() }
        .onAppear { prefetchNeighbours() }
    }

    /// 次と前のページの写真を先に読んでおく。ページ送りが引っかからないように。
    private func prefetchNeighbours() {
        guard prefs.prefetchNeighbors else { return }
        let assets = state.assetIndex
        let urls = [state.currentIndex + 1, state.currentIndex - 1]
            .filter { state.boards.indices.contains($0) }
            .flatMap { state.boards[$0].imageFrames.compactMap(\.assetID) }
            .compactMap { assets[$0]?.url }
        guard !urls.isEmpty else { return }
        ImageStore.shared.prefetch(urls, maxPixel: 2048)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // タブはブラウザと同じ位置（タイトルバー行）に置く
        ToolbarItem(placement: .principal) {
            DocumentTabBar(store: store)
        }

        ToolbarItemGroup(placement: .navigation) {
            Picker("", selection: Binding(
                get: { state.settings.kind },
                set: { state.switchKind(to: $0) })) {
                    ForEach(DocKind.allCases) { kind in
                        Label(kind.label, systemImage: kind.icon).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("ZINE（冊子）と組写真（SNS）を切り替えます")
        }

        ToolbarItemGroup {
            Button { state.presentImportPhotos() } label: {
                Label("写真を追加", systemImage: "photo.badge.plus")
            }
            .help("写真をトレイに取り込む（⌘I）")

            Button { showingTemplates = true } label: {
                Label("レイアウト", systemImage: "square.grid.3x3")
            }
            .help("レイアウトを選んで一括配置（⌘L）")

            Button { state.addTextFrame() } label: {
                Label("テキスト", systemImage: "textformat")
            }
            .help("テキストを追加（⌘T）")

            Menu {
                ForEach(ShapeKind.allCases) { kind in
                    Button { state.addShape(kind) } label: { Label(kind.label, systemImage: kind.icon) }
                }
            } label: {
                Label("図形", systemImage: "square.on.circle")
            }
            .help("罫線や囲みを追加（罫線は ⌘⇧R）")

        }

        // Liquid Glass では、機能のまとまりごとに区切ると 島が分かれて見やすくなる
        toolbarSpacer

        ToolbarItemGroup {
            Button { state.undo() } label: { Label("取り消す", systemImage: "arrow.uturn.backward") }
                .disabled(!state.canUndo)
            Button { state.redo() } label: { Label("やり直す", systemImage: "arrow.uturn.forward") }
                .disabled(!state.canRedo)
        }

        toolbarSpacer

        ToolbarItemGroup {
            Button { showingPreflight = true } label: {
                Label("点検", systemImage: "checklist")
            }
            .help("書き出す前に、解像度・あふれ・塗り足しなどを点検する（⌘⇧P）")

            Button { showingExport = true } label: {
                Label("書き出し", systemImage: "square.and.arrow.up")
            }
            .help("PDF・JPEG・PNG・AVIF などで書き出す（⌘E）")
        }
    }

    @ToolbarContentBuilder
    private var toolbarSpacer: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }
    }

    /// 写真が見つからないときの案内
    private var missingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.orange)
            Text("\(state.missingAssets.count) 枚の写真が見つかりません")
                .font(.system(size: 11, weight: .medium))
            Text(state.missingAssets.prefix(3).map(\.name).joined(separator: "、")
                 + (state.missingAssets.count > 3 ? " ほか" : ""))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("自動で追う") {
                let n = state.followMovedPhotos()
                state.status = n > 0 ? "\(n) 枚を追跡しました" : "移動先を特定できませんでした"
            }
            .controlSize(.small)
            .help("保存時のブックマークから、移動・改名された写真を探します")
            Button("フォルダから探す…") { state.presentRelink() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassPanel(cornerRadius: 0, tint: .orange)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let progress = state.exportProgress {
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 96)
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassPanel(cornerRadius: 9)
            } else if state.dirty {
                Circle().fill(.orange).frame(width: 6, height: 6)
            }
            Text(state.status.isEmpty
                 ? (state.fileURL?.lastPathComponent ?? "未保存のドキュメント")
                 : state.status)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !state.selection.isEmpty {
                Text("\(state.selection.count) 個選択")
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(state.settings.displaySize)
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
            Text("\(state.settings.kind.unitLabel) \(state.currentIndex + 1) / \(state.boards.count)")
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

// MARK: - キャンバス＋ズーム操作

struct CanvasContainer: View {
    @ObservedObject var state: AppState
    @State private var canvas: CanvasView?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CanvasRepresentable(state: state) { canvas = $0 }
            zoomControls.padding(12)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { canvas?.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
            Button { canvas?.fitToView() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .help("全体表示（⌘0）")
            Button { canvas?.zoomActual() } label: { Text("100%").font(.system(size: 10)) }
            Button { canvas?.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassPanel(cornerRadius: 11)
        .glassGroup(spacing: 10)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
    }
}

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var state: AppState
    var onMake: (CanvasView) -> Void

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.state = state
        DispatchQueue.main.async { onMake(view) }
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        if view.state !== state { view.state = state }
        view.needsDisplay = true
    }
}

extension Notification.Name {
    static let zineShowExport = Notification.Name("ZineMaker.showExport")
    static let zineShowTemplates = Notification.Name("ZineMaker.showTemplates")
    static let zineShowPreflight = Notification.Name("ZineMaker.showPreflight")
}
