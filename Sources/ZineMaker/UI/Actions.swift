import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// パネルを伴う操作（メニューとツールバーの両方から呼ぶ）
extension AppState {

    func presentImportPhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ImageStore.readableTypes
        panel.message = "取り込む写真を選択（JPEG / PNG / TIFF / AVIF / JPEG XL / HEIC など）"
        panel.prompt = "取り込む"
        guard panel.runModal() == .OK else { return }
        importPhotos(urls: panel.urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }

    func presentOpen() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["zine", "json"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try load(from: url) } catch { present(error) }
    }

    func saveDocument(forceNewLocation: Bool = false) {
        if let url = fileURL, !forceNewLocation {
            do { try save(to: url) } catch { present(error) }
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "untitled") + ".zine"
        panel.allowedFileTypes = ["zine"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try save(to: url); RecentDocuments.add(url) } catch { present(error) }
    }

    /// 見つからない写真をフォルダから探し直す
    func presentRelink() {
        let missing = missingAssets
        guard !missing.isEmpty else { status = "見つからない写真はありません"; return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "\(missing.count) 枚の写真が見つかりません。入っているフォルダを選んでください（下位フォルダも探します）"
        panel.prompt = "このフォルダを探す"
        if let first = missing.first {
            panel.directoryURL = URL(fileURLWithPath: first.path).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relinkMissing(in: url)
    }

    // MARK: - 書き出し

    func exportPDF(options: PDFExporter.Options) {
        let panel = NSSavePanel()
        applyRememberedFolder(panel)
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultName + ".pdf"
        panel.message = settings.kind == .zine && options.printBoxes
            ? "入稿用PDF（MediaBox=塗り足し込み / TrimBox=仕上がり）"
            : "PDF として書き出します"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rememberFolder(url)

        runExport { [self] report in
            try PDFExporter.export(context: documentContext, to: url, options: options, progress: report)
            let pages = PDFExporter.pageCount(boards: boards.count, settings: settings, mode: options.mode)
            return "\(pages) ページのPDFを書き出しました: \(url.lastPathComponent)"
        }
    }

    func exportImage(options: ImageExporter.Options, allBoards: Bool) {
        guard let ut = options.format.utType ?? UTType(filenameExtension: options.format.ext) else { return }
        let panel = NSSavePanel()
        applyRememberedFolder(panel)
        panel.allowedContentTypes = [ut]
        panel.nameFieldStringValue = "\(defaultName).\(options.format.ext)"
        panel.message = allBoards
            ? "\(boards.count) 枚を連番で書き出します"
            : "現在の\(settings.kind.unitLabel)を書き出します"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rememberFolder(url)

        runExport { [self] report in
            if allBoards {
                let stem = url.deletingPathExtension()
                let scenes = documentContext.allScenes()
                for (i, board) in boards.enumerated() {
                    let each = URL(fileURLWithPath: String(format: "%@-%02d.%@", stem.path, i + 1, options.format.ext))
                    try ImageExporter.export(board: board, settings: settings, scene: scenes[i],
                                             to: each, options: options)
                    report(Double(i + 1) / Double(max(boards.count, 1)))
                }
                return "\(boards.count) 枚を書き出しました: \(url.deletingLastPathComponent().lastPathComponent)/"
            } else {
                let size = try ImageExporter.export(board: currentBoard, settings: settings,
                                                    scene: currentScene, to: url, options: options)
                return "\(Int(size.width))×\(Int(size.height)) px で書き出しました: \(url.lastPathComponent)"
            }
        }
    }

    /// 前回の書き出し先を思い出す
    private func applyRememberedFolder(_ panel: NSSavePanel) {
        let prefs = Preferences.shared
        guard prefs.rememberExportFolder, !prefs.lastExportFolder.isEmpty else { return }
        panel.directoryURL = URL(fileURLWithPath: prefs.lastExportFolder)
    }

    private func rememberFolder(_ url: URL) {
        let prefs = Preferences.shared
        if prefs.rememberExportFolder { prefs.lastExportFolder = url.deletingLastPathComponent().path }
    }

    private var defaultName: String {
        if !meta.title.isEmpty { return meta.title }
        return fileURL?.deletingPathExtension().lastPathComponent
            ?? (settings.kind == .zine ? "zine" : "layout")
    }

    /// 書き出しは重いので UI を止めないように回す。進み具合はメインへ返す。
    private func runExport(_ work: @escaping (@escaping (Double) -> Void) throws -> String) {
        status = "書き出し中…"
        exportProgress = 0
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var last = Date.distantPast
            let report: (Double) -> Void = { value in
                // 毎ページ更新すると描画が忙しいので、間引く
                guard Date().timeIntervalSince(last) > 0.08 || value >= 1 else { return }
                last = Date()
                DispatchQueue.main.async { self?.exportProgress = value }
            }
            do {
                let message = try work(report)
                DispatchQueue.main.async { self?.exportProgress = nil; self?.status = message }
            } catch {
                DispatchQueue.main.async { self?.exportProgress = nil; self?.status = ""; self?.present(error) }
            }
        }
    }

    func present(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "うまくいきませんでした"
        alert.informativeText = Self.describe(error)
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// DecodingError の既定のメッセージは英語でどこが悪いかも分からないので、
    /// どのキーで詰まったのかを日本語で見せる。
    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: " › ")
        }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "ファイルの中身が想定と違います。「\(key.stringValue)」が見つかりません（\(path(context))）。"
        case .typeMismatch(let type, let context):
            return "「\(path(context))」の型が合いません（\(type) のはずです）。"
        case .valueNotFound(_, let context):
            return "「\(path(context))」の値が空です。"
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty
                ? "ファイルを読めませんでした。JSON として壊れている可能性があります。"
                : "「\(path(context))」を読めませんでした。"
        @unknown default:
            return error.localizedDescription
        }
    }
}
