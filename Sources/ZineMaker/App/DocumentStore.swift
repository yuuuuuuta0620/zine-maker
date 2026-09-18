import AppKit
import Combine
import SwiftUI

/// 開いているドキュメントをタブとしてまとめて持つ。
/// 1ウインドウの中で作品を切り替えられるようにするための入れ物。
final class DocumentStore: ObservableObject {
    static let shared = DocumentStore()

    @Published private(set) var documents: [AppState] = []
    @Published var activeID: UUID?

    private var cancellables: [UUID: AnyCancellable] = [:]

    var active: AppState? {
        documents.first { $0.id == activeID } ?? documents.first
    }

    var hasUnsaved: Bool { documents.contains { $0.dirty } }

    init() {}

    // MARK: - 開く・作る

    @discardableResult
    func newDocument(kind: DocKind? = nil) -> AppState {
        let doc = AppState(kind: kind ?? Preferences.shared.defaultKind)
        attach(doc)
        return doc
    }

    /// すでに開いていればそのタブに切り替える
    @discardableResult
    func open(_ url: URL) -> AppState? {
        if let existing = documents.first(where: { $0.fileURL == url }) {
            activeID = existing.id
            return existing
        }
        let doc = AppState()
        do {
            try doc.load(from: url)
        } catch {
            doc.present(error)
            return nil
        }
        attach(doc)
        RecentDocuments.add(url)
        return doc
    }

    private func attach(_ doc: AppState) {
        // どのタブの変更でもタブ列の見た目（名前・未保存の点）を更新する
        cancellables[doc.id] = doc.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
        documents.append(doc)
        activeID = doc.id
    }

    // MARK: - 閉じる

    /// 未保存なら確認する。閉じたら true。
    @discardableResult
    func close(_ doc: AppState, askToSave: Bool = true) -> Bool {
        if askToSave, doc.dirty {
            switch confirmClose(doc) {
            case .save:
                doc.saveDocument()
                if doc.dirty { return false }   // 保存をキャンセルした
            case .discard: break
            case .cancel: return false
            }
        }
        cancellables[doc.id] = nil
        let index = documents.firstIndex { $0.id == doc.id }
        documents.removeAll { $0.id == doc.id }
        if activeID == doc.id {
            if let index { activeID = documents[safe: min(index, documents.count - 1)]?.id }
            else { activeID = documents.first?.id }
        }
        return true
    }

    func closeActive() { if let active { _ = close(active) } }

    /// 終了前に呼ぶ。すべて閉じられたら true。
    func closeAll() -> Bool {
        for doc in documents.reversed() where !close(doc) { return false }
        return true
    }

    private enum CloseChoice { case save, discard, cancel }

    private func confirmClose(_ doc: AppState) -> CloseChoice {
        let alert = NSAlert()
        alert.messageText = "「\(doc.displayName)」の変更を保存しますか？"
        alert.informativeText = "保存しないと、加えた変更は失われます。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "保存しない")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .cancel
        default: return .discard
        }
    }

    // MARK: - タブ操作

    func select(_ doc: AppState) { activeID = doc.id }

    func selectNext() {
        guard let i = documents.firstIndex(where: { $0.id == activeID }), documents.count > 1 else { return }
        activeID = documents[(i + 1) % documents.count].id
    }

    func selectPrevious() {
        guard let i = documents.firstIndex(where: { $0.id == activeID }), documents.count > 1 else { return }
        activeID = documents[(i - 1 + documents.count) % documents.count].id
    }

    func select(index: Int) {
        guard documents.indices.contains(index) else { return }
        activeID = documents[index].id
    }

    func move(from source: Int, to destination: Int) {
        guard documents.indices.contains(source) else { return }
        let doc = documents.remove(at: source)
        documents.insert(doc, at: min(destination > source ? destination - 1 : destination, documents.count))
    }

    /// 現在のドキュメントを複製して新しいタブに
    func duplicateActive() {
        guard let active else { return }
        let copy = AppState()
        copy.settings = active.settings
        copy.meta = active.meta
        copy.series = active.series
        copy.assets = active.assets
        copy.boards = active.boards
        copy.dirty = true
        attach(copy)
    }
}

/// 最近使ったファイル
enum RecentDocuments {
    private static let key = "recentDocuments"
    private static let limit = 10

    static var urls: [URL] {
        (UserDefaults.standard.array(forKey: key) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func add(_ url: URL) {
        var paths = urls.map(\.path)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: key)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
