import AppKit
import SwiftUI

@main
struct ZineMakerApp: App {
    @StateObject private var state = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("ZineMaker", id: "main") {
            ContentView(state: state)
                .frame(minWidth: 1180, minHeight: 800)
        }
        .commands { commands }
    }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新規 ZINE") { state.newDocument(kind: .zine) }
                .keyboardShortcut("n")
            Button("新規 組写真") { state.newDocument(kind: .board) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("開く…") { state.presentOpen() }.keyboardShortcut("o")
        }

        CommandGroup(after: .saveItem) {
            Button("保存") { state.saveDocument() }.keyboardShortcut("s")
            Button("別名で保存…") { state.saveDocument(forceNewLocation: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("書き出し…") { NotificationCenter.default.post(name: .zineShowExport, object: nil) }
                .keyboardShortcut("e")
        }

        CommandGroup(replacing: .undoRedo) {
            Button("取り消す") { state.undo() }.keyboardShortcut("z").disabled(!state.canUndo)
            Button("やり直す") { state.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!state.canRedo)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("すべて選択") { state.selectAll() }.keyboardShortcut("a")
            Button("複製") { state.duplicateSelected() }.keyboardShortcut("d")
            Button("削除") { state.deleteSelected() }.keyboardShortcut(.delete, modifiers: [])
        }

        CommandMenu("誌面") {
            Button("写真を取り込む…") { state.presentImportPhotos() }.keyboardShortcut("i")
            Button("レイアウトを選ぶ…") {
                NotificationCenter.default.post(name: .zineShowTemplates, object: nil)
            }
            .keyboardShortcut("l")
            Button("テキストを追加") { state.addTextFrame() }.keyboardShortcut("t")
            Button("空の写真枠を追加") { state.addImageFrame() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Menu("図形を追加") {
                ForEach(ShapeKind.allCases) { kind in
                    Button(kind.label) { state.addShape(kind) }
                }
            }
            Button("罫線を追加") { state.addShape(.line) }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()
            Button("\(state.settings.kind.unitLabel)を追加") { state.addBoard() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("\(state.settings.kind.unitLabel)を複製") { state.duplicateBoard() }
            Button("\(state.settings.kind.unitLabel)を削除") { state.deleteCurrentBoard() }
                .disabled(state.boards.count <= 1)

            Divider()
            Button("最前面へ") { state.bringToFront() }.keyboardShortcut("]")
            Button("最背面へ") { state.sendToBack() }.keyboardShortcut("[")
            Divider()
            Button("用紙いっぱいに広げる") { state.fillBoard() }
            Button("余白に合わせる") { state.fitToMargins() }
        }

        CommandMenu("ポートフォリオ") {
            Button("一式そろえる（表紙・ステートメント・一覧・プロフィール）") { state.scaffoldPortfolio() }
            Divider()
            ForEach(BoardRole.allCases.filter { $0 != .content }) { role in
                Button("\(role.label)を追加") { state.addPortfolioPage(role) }
            }
            Divider()
            Button("シリーズを追加") { state.addSeries() }
            Divider()
            Button("写真にキャプションを付ける") {
                state.addCaptions(template: CaptionTemplate.presets[1].template)
            }
            .keyboardShortcut("k")
            Button("撮影データのキャプションを付ける") {
                state.addCaptions(template: "{exposure}")
            }
        }

        CommandMenu("表示") {
            Toggle("定規", isOn: Binding(get: { state.showRulers }, set: { state.showRulers = $0 }))
                .keyboardShortcut("r", modifiers: [.command, .option])
            Toggle("ガイド", isOn: Binding(get: { state.showCustomGuides }, set: { state.showCustomGuides = $0 }))
                .keyboardShortcut(";")
            Toggle("段組み", isOn: Binding(get: { state.showColumns }, set: { state.showColumns = $0 }))
                .keyboardShortcut("'")
            Toggle("吸着", isOn: Binding(get: { state.snapEnabled }, set: { state.snapEnabled = $0 }))
                .keyboardShortcut(";", modifiers: [.command, .shift])
            Divider()
            Button("選択範囲からガイドを引く") { state.guidesFromSelection() }
                .disabled(state.selection.isEmpty)
            Button("ガイドをすべて消す") { state.clearGuides() }
        }

        CommandMenu("変形") {
            Button("左に90°回転") { state.rotateSelected(by: -90) }
            Button("右に90°回転") { state.rotateSelected(by: 90) }
            Button("回転をリセット") { state.rotateSelected(to: 0) }
            Divider()
            Button("ロックする") { state.lockSelected(true) }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("ロックを外す") { state.lockSelected(false) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
            Button("段組みのセルに合わせる") { state.snapSelectionToColumns() }
                .disabled(state.settings.columnRects.isEmpty)
        }

        CommandMenu("整列") {
            Button("左揃え") { state.align(.left) }
            Button("左右中央") { state.align(.hCenter) }
            Button("右揃え") { state.align(.right) }
            Divider()
            Button("上揃え") { state.align(.top) }
            Button("上下中央") { state.align(.vCenter) }
            Button("下揃え") { state.align(.bottom) }
            Divider()
            Button("横に等間隔") { state.distribute(horizontally: true) }
            Button("縦に等間隔") { state.distribute(horizontally: false) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finder からの .zine ダブルクリック／`open` コマンド
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if url.pathExtension.lowercased() == "zine" {
            do { try AppState.shared.load(from: url) } catch { AppState.shared.present(error) }
        } else {
            AppState.shared.importPhotos(urls: urls)
        }
    }
}
