import AppKit
import SwiftUI

@main
struct ZineMakerApp: App {
    @StateObject private var store = DocumentStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("ZineMaker", id: "main") {
            RootView(store: store)
        }
        .commands { commands }

        Settings { SettingsView() }
    }

    /// いま開いているドキュメント。無いときはメニューを無効にする。
    private var doc: AppState? { store.active }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新規") { store.newDocument() }.keyboardShortcut("n")
            Button("新規 ZINE") { store.newDocument(kind: .zine) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("新規 組写真") { store.newDocument(kind: .board) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("開く…") { presentOpen() }.keyboardShortcut("o")
            Menu("最近使った項目") {
                ForEach(RecentDocuments.urls, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { store.open(url) }
                }
                if RecentDocuments.urls.isEmpty { Text("なし") }
                Divider()
                Button("メニューをクリア") { RecentDocuments.clear() }
            }
        }

        CommandGroup(after: .saveItem) {
            Button("保存") { doc?.saveDocument() }.keyboardShortcut("s").disabled(doc == nil)
            Button("別名で保存…") { doc?.saveDocument(forceNewLocation: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(doc == nil)
            Button("複製") { store.duplicateActive() }.disabled(doc == nil)
            Divider()
            Button("書き出し…") { NotificationCenter.default.post(name: .zineShowExport, object: nil) }
                .keyboardShortcut("e").disabled(doc == nil)
            Divider()
            Button("タブを閉じる") { store.closeActive() }
                .keyboardShortcut("w").disabled(doc == nil)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("取り消す") { doc?.undo() }.keyboardShortcut("z").disabled(!(doc?.canUndo ?? false))
            Button("やり直す") { doc?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(doc?.canRedo ?? false))
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("すべて選択") { doc?.selectAll() }.keyboardShortcut("a").disabled(doc == nil)
            Button("複製") { doc?.duplicateSelected() }.keyboardShortcut("d").disabled(doc == nil)
            Button("削除") { doc?.deleteSelected() }.keyboardShortcut(.delete, modifiers: [])
                .disabled(doc == nil)
        }

        CommandMenu("誌面") {
            Button("写真を取り込む…") { doc?.presentImportPhotos() }.keyboardShortcut("i")
            Button("レイアウトを選ぶ…") {
                NotificationCenter.default.post(name: .zineShowTemplates, object: nil)
            }
            .keyboardShortcut("l")
            Button("テキストを追加") { doc?.addTextFrame() }.keyboardShortcut("t")
            Button("空の写真枠を追加") { doc?.addImageFrame() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Menu("図形を追加") {
                ForEach(ShapeKind.allCases) { kind in
                    Button(kind.label) { doc?.addShape(kind) }
                }
            }
            Button("罫線を追加") { doc?.addShape(.line) }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()
            Button("ページを追加") { doc?.addBoard() }
                .keyboardShortcut("n", modifiers: [.command, .control])
            Button("ページを複製") { doc?.duplicateBoard() }
            Button("ページを削除") { doc?.deleteCurrentBoard() }

            Divider()
            Button("最前面へ") { doc?.bringToFront() }.keyboardShortcut("]")
            Button("最背面へ") { doc?.sendToBack() }.keyboardShortcut("[")
            Divider()
            Button("用紙いっぱいに広げる") { doc?.fillBoard() }
            Button("余白に合わせる") { doc?.fitToMargins() }
        }

        CommandMenu("ポートフォリオ") {
            Button("一式そろえる（表紙・ステートメント・一覧・プロフィール）") { doc?.scaffoldPortfolio() }
            Divider()
            ForEach(BoardRole.allCases.filter { $0 != .content }) { role in
                Button("\(role.label)を追加") { doc?.addPortfolioPage(role) }
            }
            Divider()
            Menu("写真集の型で組む") {
                ForEach(BookLayouts.styles) { style in
                    Button(style.name) { doc?.applyBookStyle(style.key) }
                }
            }
            Divider()
            Button("シリーズを追加") { doc?.addSeries() }
            Divider()
            Button("見つからない写真を探す…") { doc?.presentRelink() }
            Divider()
            Button("GPSから撮影地を調べる") { doc?.resolvePlaces() }
            Button("撮影地をリボンで重ねる") { doc?.addPlaceRibbons() }
            Button("写真にキャプションを付ける") {
                doc?.addCaptions(template: CaptionTemplate.presets[1].template)
            }
            .keyboardShortcut("k")
        }

        CommandMenu("表示") {
            Toggle("定規", isOn: binding(\.showRulers))
                .keyboardShortcut("r", modifiers: [.command, .option])
            Toggle("ガイド", isOn: binding(\.showCustomGuides)).keyboardShortcut(";")
            Toggle("段組み", isOn: binding(\.showColumns)).keyboardShortcut("'")
            Toggle("吸着", isOn: binding(\.snapEnabled)).keyboardShortcut(";", modifiers: [.command, .shift])
            Divider()
            Button("選択範囲からガイドを引く") { doc?.guidesFromSelection() }
            Button("ガイドをすべて消す") { doc?.clearGuides() }
            Divider()
            Button("次のタブ") { store.selectNext() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("前のタブ") { store.selectPrevious() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }

        CommandMenu("変形") {
            Button("左に90°回転") { doc?.rotateSelected(by: -90) }
            Button("右に90°回転") { doc?.rotateSelected(by: 90) }
            Button("回転をリセット") { doc?.rotateSelected(to: 0) }
            Divider()
            Button("ロックする") { doc?.lockSelected(true) }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("ロックを外す") { doc?.lockSelected(false) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
            Button("段組みのセルに合わせる") { doc?.snapSelectionToColumns() }
            Divider()
            Button("左揃え") { doc?.align(.left) }
            Button("左右中央") { doc?.align(.hCenter) }
            Button("右揃え") { doc?.align(.right) }
            Button("上揃え") { doc?.align(.top) }
            Button("上下中央") { doc?.align(.vCenter) }
            Button("下揃え") { doc?.align(.bottom) }
            Divider()
            Button("横に等間隔") { doc?.distribute(horizontally: true) }
            Button("縦に等間隔") { doc?.distribute(horizontally: false) }
        }

        CommandGroup(replacing: .help) {
            Button("ZineMaker のヘルプ") {
                NSWorkspace.shared.open(URL(string: "https://github.com/yuuuuuuta0620/zine-maker")!)
            }
        }
    }

    /// 表示メニューのトグルは、ドキュメントが無いときも壊れないように包む
    private func binding(_ keyPath: ReferenceWritableKeyPath<AppState, Bool>) -> Binding<Bool> {
        Binding(
            get: { doc?[keyPath: keyPath] ?? false },
            set: { doc?[keyPath: keyPath] = $0 }
        )
    }

    private func presentOpen() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = ["zine", "json"]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.open(url) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// ⌘W はまずタブを閉じる。タブが無くなったときだけウインドウを閉じる。
    /// これをやらないと、システム側の「ウインドウを閉じる」に取られてアプリごと終わってしまう。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let store = DocumentStore.shared
        guard !store.documents.isEmpty else { return true }
        store.closeActive()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI がウインドウを作り終えてから受け持つ
        DispatchQueue.main.async { [weak self] in
            NSApp.windows.first { $0.isVisible && $0.contentView != nil }?.delegate = self
        }

        let store = DocumentStore.shared
        store.offerRecoveryIfNeeded()
        guard store.documents.isEmpty else { return }   // Finder から開かれていれば触らない
        switch Preferences.shared.launch {
        case .newDocument: store.newDocument()
        case .lastDocument:
            if let last = RecentDocuments.urls.first { store.open(last) } else { store.newDocument() }
        case .nothing: break
        }
    }

    /// 終了前に未保存を確認する
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard DocumentStore.shared.closeAll() else { return .terminateCancel }
        Autosave.markCleanExit()
        return .terminateNow
    }

    /// Finder からの .zine ダブルクリック／`open` コマンド
    func application(_ application: NSApplication, open urls: [URL]) {
        let store = DocumentStore.shared
        for url in urls {
            if url.pathExtension.lowercased() == "zine" || url.pathExtension.lowercased() == "json" {
                store.open(url)
            } else {
                (store.active ?? store.newDocument()).importPhotos(urls: [url])
            }
        }
    }
}
