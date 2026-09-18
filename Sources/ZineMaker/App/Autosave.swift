import Foundation

/// 自動保存とクラッシュ復帰。
/// 編集中のドキュメントを一定間隔で控えに書き出し、次の起動時に取りこぼしがあれば戻せるようにする。
enum Autosave {

    static let interval: TimeInterval = 30

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZineMaker/Autosave", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 正常終了したかどうかの印。これが残っていたら前回は落ちている。
    private static var runningFlag: URL {
        directory.deletingLastPathComponent().appendingPathComponent("running")
    }

    /// 控え1件ぶん
    struct Entry: Codable, Identifiable {
        var id: UUID
        var name: String
        /// 元のファイル（未保存なら nil）
        var originalPath: String?
        var savedAt: Date

        var fileURL: URL { Autosave.directory.appendingPathComponent("\(id.uuidString).zine") }
        var metaURL: URL { Autosave.directory.appendingPathComponent("\(id.uuidString).json") }
        var original: URL? { originalPath.map { URL(fileURLWithPath: $0) } }
    }

    // MARK: - 起動と終了

    static func markRunning() {
        try? Data().write(to: runningFlag)
    }

    static func markCleanExit() {
        try? FileManager.default.removeItem(at: runningFlag)
        clearAll()
    }

    /// 前回が正常終了でなかったか
    static var crashedLastTime: Bool {
        FileManager.default.fileExists(atPath: runningFlag.path)
    }

    // MARK: - 書き出しと取り出し

    static func write(_ file: ZineFile, id: UUID, name: String, original: URL?) {
        let entry = Entry(id: id, name: name, originalPath: original?.path, savedAt: Date())
        let encoder = JSONEncoder()
        guard let doc = try? encoder.encode(file), let meta = try? encoder.encode(entry) else { return }
        try? doc.write(to: entry.fileURL)
        try? meta.write(to: entry.metaURL)
    }

    static func remove(id: UUID) {
        let base = directory
        try? FileManager.default.removeItem(at: base.appendingPathComponent("\(id.uuidString).zine"))
        try? FileManager.default.removeItem(at: base.appendingPathComponent("\(id.uuidString).json"))
    }

    /// 残っている控え。新しい順。
    static var entries: [Entry] {
        let base = directory
        let files = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Entry? in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? JSONDecoder().decode(Entry.self, from: data),
                      FileManager.default.fileExists(atPath: entry.fileURL.path) else { return nil }
                return entry
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    static func clearAll() {
        let base = directory
        let files = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }
}
