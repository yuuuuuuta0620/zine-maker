import AppKit
import Combine
import CoreGraphics
import Foundation

final class AppState: ObservableObject {
    /// Finder からの .zine オープンを AppDelegate 経由で受けるため共有インスタンスを持つ
    static let shared = AppState()

    @Published var settings = DocSettings() { didSet { if settings != oldValue { dirty = true } } }
    @Published var assets: [PhotoAsset] = []
    @Published var boards: [Artboard] = [Artboard()]
    @Published var currentIndex = 0
    @Published var selection: Set<UUID> = []
    /// 写真トレイで選ばれている写真
    @Published var traySelection: Set<UUID> = []
    @Published var fileURL: URL?
    @Published var dirty = false
    @Published var status = ""
    @Published private(set) var fitToken = 0

    // 表示のオン／オフ（ドキュメントには保存しない）
    @Published var showRulers = true
    @Published var showColumns = true
    @Published var showCustomGuides = true
    @Published var snapEnabled = true
    /// 1 で 1pt 刻み。0 でグリッド吸着なし
    @Published var gridStep: CGFloat = 0

    private var undoStack: [ZineFile] = []
    private var redoStack: [ZineFile] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - 参照

    var assetIndex: [UUID: PhotoAsset] {
        Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    }

    var currentBoard: Artboard {
        get { boards.indices.contains(currentIndex) ? boards[currentIndex] : Artboard() }
        set {
            guard boards.indices.contains(currentIndex) else { return }
            boards[currentIndex] = newValue
            dirty = true
        }
    }

    var selectedElements: [Element] {
        currentBoard.elements.filter { selection.contains($0.id) }
    }

    var singleSelection: Element? {
        selection.count == 1 ? selectedElements.first : nil
    }

    /// 選択範囲を囲む矩形
    var selectionBounds: CGRect? {
        let rects = selectedElements.map(\.rect)
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    /// まだどの枠にも入っていない写真
    var unplacedAssets: [PhotoAsset] {
        let used = Set(boards.flatMap { $0.imageFrames.compactMap(\.assetID) })
        return assets.filter { !used.contains($0.id) }
    }

    func requestFit() { fitToken += 1 }

    // MARK: - Undo

    private var snapshot: ZineFile { ZineFile(settings: settings, assets: assets, boards: boards) }

    /// 1操作の直前に一度だけ呼ぶ（ドラッグ中は呼ばない）
    func beginUndoGroup() {
        undoStack.append(snapshot)
        if undoStack.count > 120 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        apply(next)
    }

    private func apply(_ file: ZineFile) {
        settings = file.settings
        assets = file.assets
        boards = file.boards.isEmpty ? [Artboard()] : file.boards
        currentIndex = min(currentIndex, boards.count - 1)
        let ids = Set(currentBoard.elements.map(\.id))
        selection = selection.intersection(ids)
        dirty = true
    }

    // MARK: - 選択

    func select(_ id: UUID?, additive: Bool = false) {
        guard let id else { if !additive { selection.removeAll() }; return }
        if additive {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    func selectAll() { selection = Set(currentBoard.elements.filter { !$0.locked && !$0.hidden }.map(\.id)) }

    /// 操作できる要素だけ（ロック・非表示を除く）
    var selectableElements: [Element] {
        currentBoard.elements.filter { !$0.locked && !$0.hidden }
    }

    // MARK: - 編集

    func updateSelected(_ transform: (inout Element) -> Void) {
        guard !selection.isEmpty else { return }
        var board = currentBoard
        for i in board.elements.indices where selection.contains(board.elements[i].id) {
            transform(&board.elements[i])
        }
        currentBoard = board
        objectWillChange.send()
    }

    func update(id: UUID, _ transform: (inout Element) -> Void) {
        guard let idx = currentBoard.elements.firstIndex(where: { $0.id == id }) else { return }
        var board = currentBoard
        transform(&board.elements[idx])
        currentBoard = board
        objectWillChange.send()
    }

    func deleteSelected() {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        currentBoard.elements.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func duplicateSelected() {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        let offset = Pt.fromMM(4)
        var board = currentBoard
        var newIDs: Set<UUID> = []
        for element in currentBoard.elements where selection.contains(element.id) {
            var copy = element
            switch copy {
            case .image(var f): f.id = UUID(); f.rect = f.rect.offsetBy(dx: offset, dy: -offset); copy = .image(f)
            case .text(var f):  f.id = UUID(); f.rect = f.rect.offsetBy(dx: offset, dy: -offset); copy = .text(f)
            }
            newIDs.insert(copy.id)
            board.elements.append(copy)
        }
        currentBoard = board
        selection = newIDs
    }

    func bringToFront() { reorderSelection(toFront: true) }
    func sendToBack()   { reorderSelection(toFront: false) }

    private func reorderSelection(toFront: Bool) {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        var board = currentBoard
        let moving = board.elements.filter { selection.contains($0.id) }
        board.elements.removeAll { selection.contains($0.id) }
        board.elements.insert(contentsOf: moving, at: toFront ? board.elements.count : 0)
        currentBoard = board
    }

    // MARK: - ロック・表示・レイヤー

    func toggleLock(_ id: UUID) {
        beginUndoGroup()
        update(id: id) { $0.locked.toggle() }
        if currentBoard.elements.first(where: { $0.id == id })?.locked == true { selection.remove(id) }
    }

    func toggleHidden(_ id: UUID) {
        beginUndoGroup()
        update(id: id) { $0.hidden.toggle() }
        if currentBoard.elements.first(where: { $0.id == id })?.hidden == true { selection.remove(id) }
    }

    func rename(_ id: UUID, to name: String) {
        beginUndoGroup()
        update(id: id) { $0.customName = name.isEmpty ? nil : name }
    }

    func lockSelected(_ locked: Bool) {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        updateSelected { $0.locked = locked }
        if locked { selection.removeAll() }
    }

    /// レイヤー一覧は手前から並べるので、表示順は elements の逆順
    var layerOrder: [Element] { currentBoard.elements.reversed() }

    /// レイヤー一覧の index（手前が0）で並び替える
    func moveLayer(fromDisplay source: Int, toDisplay destination: Int) {
        let count = currentBoard.elements.count
        guard source >= 0, source < count else { return }
        let from = count - 1 - source
        let rawTo = count - destination
        let to = max(0, min(rawTo, count))
        guard from != to, from != to - 1 else { return }
        beginUndoGroup()
        var board = currentBoard
        let element = board.elements.remove(at: from)
        board.elements.insert(element, at: to > from ? to - 1 : to)
        currentBoard = board
    }

    // MARK: - 回転

    func rotateSelected(to degrees: CGFloat) {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        updateSelected { $0.rotation = degrees }
    }

    func rotateSelected(by degrees: CGFloat) {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        updateSelected { $0.rotation = ($0.rotation + degrees).truncatingRemainder(dividingBy: 360) }
    }

    // MARK: - ガイド

    /// `position` は仕上がり枠に対する 0...1
    func addGuide(vertical: Bool, at position: Double) {
        beginUndoGroup()
        let v = min(max(position, -0.2), 1.2)
        if vertical { settings.verticalGuides.append(v) } else { settings.horizontalGuides.append(v) }
    }

    func moveGuide(vertical: Bool, index: Int, to position: Double) {
        if vertical, settings.verticalGuides.indices.contains(index) {
            settings.verticalGuides[index] = position
        } else if !vertical, settings.horizontalGuides.indices.contains(index) {
            settings.horizontalGuides[index] = position
        }
    }

    func removeGuide(vertical: Bool, index: Int) {
        beginUndoGroup()
        if vertical, settings.verticalGuides.indices.contains(index) {
            settings.verticalGuides.remove(at: index)
        } else if !vertical, settings.horizontalGuides.indices.contains(index) {
            settings.horizontalGuides.remove(at: index)
        }
    }

    func clearGuides() {
        beginUndoGroup()
        settings.verticalGuides.removeAll()
        settings.horizontalGuides.removeAll()
    }

    /// 選択中の枠の四辺からガイドを引く
    func guidesFromSelection() {
        guard let b = selectionBounds else { return }
        beginUndoGroup()
        let trim = settings.trimBox
        settings.verticalGuides.append(contentsOf: [
            Double((b.minX - trim.minX) / trim.width), Double((b.maxX - trim.minX) / trim.width)])
        settings.horizontalGuides.append(contentsOf: [
            Double((b.minY - trim.minY) / trim.height), Double((b.maxY - trim.minY) / trim.height)])
    }

    // MARK: - 繰り返し配置と間隔

    /// 選択中を指定の間隔で複製する（ステップ＆リピート）
    func stepAndRepeat(count: Int, dx: CGFloat, dy: CGFloat) {
        guard !selection.isEmpty, count > 0 else { return }
        beginUndoGroup()
        let originals = selectedElements
        var board = currentBoard
        var newIDs: Set<UUID> = []
        for step in 1...count {
            for element in originals {
                var copy = element
                let offset = CGPoint(x: dx * CGFloat(step), y: dy * CGFloat(step))
                switch copy {
                case .image(var f): f.id = UUID(); f.rect = f.rect.offsetBy(dx: offset.x, dy: offset.y); copy = .image(f)
                case .text(var f):  f.id = UUID(); f.rect = f.rect.offsetBy(dx: offset.x, dy: offset.y); copy = .text(f)
                }
                newIDs.insert(copy.id)
                board.elements.append(copy)
            }
        }
        currentBoard = board
        selection.formUnion(newIDs)
        status = "\(count) 回複製しました"
    }

    /// 選択中を、指定の間隔で並べ直す（位置は保ったまま隙間だけ揃える）
    func setSpacing(_ gap: CGFloat, horizontally: Bool) {
        guard selection.count > 1, let bounds = selectionBounds else { return }
        beginUndoGroup()
        var picked = selectedElements
        picked.sort { horizontally ? $0.rect.midX < $1.rect.midX : $0.rect.midY < $1.rect.midY }

        var cursor = horizontally ? bounds.minX : bounds.minY
        for element in picked {
            update(id: element.id) { e in
                if horizontally { e.rect.origin.x = cursor } else { e.rect.origin.y = cursor }
            }
            cursor += (horizontally ? element.rect.width : element.rect.height) + gap
        }
    }

    /// 段組みのセルにぴったり合わせる
    func snapSelectionToColumns() {
        let cells = settings.columnRects
        guard !cells.isEmpty, !selection.isEmpty else { return }
        beginUndoGroup()
        updateSelected { element in
            let r = element.rect
            // 重なりが最大のセルを起点に、覆っているセル全体へ広げる
            let covered = cells.filter { $0.intersects(r.insetBy(dx: 1, dy: 1)) }
            guard let first = covered.first else { return }
            element.rect = covered.dropFirst().reduce(first) { $0.union($1) }
        }
    }

    // MARK: - 整列

    enum Align { case left, hCenter, right, top, vCenter, bottom }

    func align(_ mode: Align) {
        guard selection.count > 1, let bounds = selectionBounds else { return }
        beginUndoGroup()
        updateSelected { element in
            var r = element.rect
            switch mode {
            case .left:    r.origin.x = bounds.minX
            case .hCenter: r.origin.x = bounds.midX - r.width / 2
            case .right:   r.origin.x = bounds.maxX - r.width
            case .top:     r.origin.y = bounds.maxY - r.height
            case .vCenter: r.origin.y = bounds.midY - r.height / 2
            case .bottom:  r.origin.y = bounds.minY
            }
            element.rect = r
        }
    }

    func distribute(horizontally: Bool) {
        guard selection.count > 2, let bounds = selectionBounds else { return }
        beginUndoGroup()
        var picked = currentBoard.elements.filter { selection.contains($0.id) }
        picked.sort { horizontally ? $0.rect.midX < $1.rect.midX : $0.rect.midY < $1.rect.midY }

        let totalSize = picked.reduce(CGFloat(0)) { $0 + (horizontally ? $1.rect.width : $1.rect.height) }
        let space = ((horizontally ? bounds.width : bounds.height) - totalSize) / CGFloat(picked.count - 1)

        var cursor = horizontally ? bounds.minX : bounds.minY
        for element in picked {
            update(id: element.id) { e in
                if horizontally { e.rect.origin.x = cursor } else { e.rect.origin.y = cursor }
            }
            cursor += (horizontally ? element.rect.width : element.rect.height) + space
        }
    }

    /// 枠を用紙／ボードいっぱいに広げる
    func fillBoard() {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        let target = settings.kind == .zine ? settings.mediaBox : settings.trimBox
        updateSelected { $0.rect = target }
    }

    func fitToMargins() {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        updateSelected { $0.rect = settings.contentBox }
    }

    // MARK: - 要素の追加

    func addTextFrame() {
        beginUndoGroup()
        let box = settings.marginBox(0)
        let height = settings.kind == .zine ? Pt.fromMM(36) : box.height * 0.16
        var frame = TextFrame(rect: CGRect(x: box.minX, y: box.minY, width: box.width, height: height))
        frame.text = "ここにテキスト"
        frame.fontSize = settings.kind == .zine ? 10 : max(box.width * 0.035, 12)
        frame.color = settings.background.contrastingInk
        currentBoard.elements.append(.text(frame))
        selection = [frame.id]
    }

    func addImageFrame(assetID: UUID? = nil, at point: CGPoint? = nil) {
        beginUndoGroup()
        let box = settings.contentBox
        let size = CGSize(width: box.width * 0.5, height: box.height * 0.5)
        let origin = point.map { CGPoint(x: $0.x - size.width / 2, y: $0.y - size.height / 2) }
            ?? CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2)
        var frame = ImageFrame(rect: CGRect(origin: origin, size: size))
        frame.assetID = assetID
        currentBoard.elements.append(.image(frame))
        selection = [frame.id]
    }

    // MARK: - ボード

    func addBoard() {
        beginUndoGroup()
        boards.insert(Artboard(), at: currentIndex + 1)
        currentIndex += 1
        selection.removeAll()
    }

    func duplicateBoard() {
        beginUndoGroup()
        var copy = currentBoard
        copy.id = UUID()
        copy.elements = copy.elements.map { element in
            var e = element
            switch e {
            case .image(var f): f.id = UUID(); e = .image(f)
            case .text(var f):  f.id = UUID(); e = .text(f)
            }
            return e
        }
        boards.insert(copy, at: currentIndex + 1)
        currentIndex += 1
        selection.removeAll()
    }

    func deleteCurrentBoard() {
        guard boards.count > 1 else { return }
        beginUndoGroup()
        boards.remove(at: currentIndex)
        currentIndex = min(currentIndex, boards.count - 1)
        selection.removeAll()
    }

    func moveBoard(from source: Int, to destination: Int) {
        guard boards.indices.contains(source), source != destination else { return }
        beginUndoGroup()
        let board = boards.remove(at: source)
        boards.insert(board, at: destination > source ? destination - 1 : destination)
        currentIndex = boards.firstIndex(where: { $0.id == board.id }) ?? currentIndex
    }

    // MARK: - 写真の取り込み

    @discardableResult
    func importPhotos(urls: [URL]) -> [PhotoAsset] {
        guard !urls.isEmpty else { return [] }
        beginUndoGroup()
        let existing = Set(assets.map(\.path))
        let added = urls
            .filter { !existing.contains($0.path) }
            .map { PhotoAsset(path: $0.path) }
        assets.append(contentsOf: added)
        dirty = true
        status = added.isEmpty ? "すでに読み込み済みです" : "\(added.count) 枚をトレイに追加しました"
        // メタデータを裏で温めておく（枚数表示や比率計算が待たされないように）
        let urlsToWarm = added.map(\.url)
        DispatchQueue.global(qos: .utility).async {
            for url in urlsToWarm { _ = ImageStore.shared.pixelSize(of: url) }
            DispatchQueue.main.async { NotificationCenter.default.post(name: ImageStore.didLoad, object: nil) }
        }
        return added
    }

    func removeAssets(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        beginUndoGroup()
        assets.removeAll { ids.contains($0.id) }
        for i in boards.indices {
            for j in boards[i].elements.indices {
                if case .image(var f) = boards[i].elements[j], let a = f.assetID, ids.contains(a) {
                    f.assetID = nil
                    boards[i].elements[j] = .image(f)
                }
            }
        }
        traySelection.subtract(ids)
        dirty = true
    }

    /// 選択中の枠に写真を入れる。枠が選ばれていなければ空き枠へ、それも無ければ新規に置く。
    func assign(assetID: UUID) {
        beginUndoGroup()
        if let target = selectedElements.first(where: { $0.imageFrame != nil }) {
            update(id: target.id) { if case .image(var f) = $0 { f.assetID = assetID; f.contentOffset = .zero; f.contentScale = 1; $0 = .image(f) } }
        } else if let empty = currentBoard.elements.first(where: { $0.imageFrame?.assetID == nil }) {
            update(id: empty.id) { if case .image(var f) = $0 { f.assetID = assetID; $0 = .image(f) } }
            selection = [empty.id]
        } else {
            addImageFrame(assetID: assetID)
        }
    }

    // MARK: - テンプレート

    /// レイアウトを現在のボードに適用し、空き枠に写真を流し込む。
    /// `photos` を渡すとそれを、渡さなければトレイの選択（なければ未配置の写真）を使う。
    func applyTemplate(_ template: LayoutTemplate, photos: [UUID]? = nil, replaceExisting: Bool = true) {
        beginUndoGroup()

        let box = settings.kind == .zine ? settings.marginBox(0).union(settings.marginBox(settings.pagesPerSpread - 1))
                                         : settings.contentBox
        let gutter = settings.kind == .zine ? Pt.fromMM(4) : settings.boardGutter
        let rects = template.frames(in: box, gutter: gutter)

        // 使う写真を決める
        var queue: [UUID]
        if let photos { queue = photos }
        else if !traySelection.isEmpty { queue = assets.filter { traySelection.contains($0.id) }.map(\.id) }
        else {
            let reuse = replaceExisting ? currentBoard.imageFrames.compactMap(\.assetID) : []
            queue = reuse + unplacedAssets.map(\.id)
        }

        var board = currentBoard
        if replaceExisting { board.elements.removeAll { $0.imageFrame != nil } }

        // スロット順のまま、ひとかたまりで最背面に差し込む（テキストより奥に置く）
        var newFrames: [Element] = []
        for rect in rects {
            var frame = ImageFrame(rect: rect)
            frame.assetID = queue.isEmpty ? nil : queue.removeFirst()
            newFrames.append(.image(frame))
        }
        board.elements.insert(contentsOf: newFrames, at: 0)
        currentBoard = board
        selection = []
        traySelection.removeAll()
        status = "「\(template.name)」を適用しました"
    }

    /// トレイの写真を、テンプレートを繰り返し使って複数ボードへ流し込む
    func autoFlow(template: LayoutTemplate, photos: [PhotoAsset]? = nil) {
        let source = photos ?? (traySelection.isEmpty ? unplacedAssets
                                                      : assets.filter { traySelection.contains($0.id) })
        guard !source.isEmpty else { status = "流し込む写真がありません"; return }
        beginUndoGroup()

        let chunks = stride(from: 0, to: source.count, by: max(template.count, 1)).map {
            Array(source[$0..<min($0 + template.count, source.count)])
        }
        let startIndex = currentIndex
        for (offset, chunk) in chunks.enumerated() {
            let index = startIndex + offset
            if index >= boards.count { boards.append(Artboard()) }
            currentIndex = index
            applyTemplateWithoutUndo(template, photos: chunk.map(\.id))
        }
        currentIndex = startIndex
        traySelection.removeAll()
        selection.removeAll()
        status = "\(source.count) 枚を \(chunks.count) \(settings.kind.unitLabel)に流し込みました"
    }

    private func applyTemplateWithoutUndo(_ template: LayoutTemplate, photos: [UUID]) {
        let box = settings.kind == .zine ? settings.marginBox(0).union(settings.marginBox(settings.pagesPerSpread - 1))
                                         : settings.contentBox
        let gutter = settings.kind == .zine ? Pt.fromMM(4) : settings.boardGutter
        var queue = photos
        var board = currentBoard
        board.elements.removeAll { $0.imageFrame != nil }
        var newFrames: [Element] = []
        for rect in template.frames(in: box, gutter: gutter) {
            var frame = ImageFrame(rect: rect)
            frame.assetID = queue.isEmpty ? nil : queue.removeFirst()
            newFrames.append(.image(frame))
        }
        board.elements.insert(contentsOf: newFrames, at: 0)
        currentBoard = board
    }

    // MARK: - モード切り替え

    func switchKind(to kind: DocKind) {
        guard settings.kind != kind else { return }
        beginUndoGroup()
        let old = settings.trimBox
        settings.kind = kind
        remapElements(from: old, to: settings.trimBox)
        requestFit()
        status = kind == .zine ? "ZINE モードに切り替えました" : "組写真モードに切り替えました"
    }

    /// アスペクト比を変える。レイアウトは比率を保ったまま新しい枠に移し替える。
    func setAspect(_ ratio: AspectRatio) {
        guard settings.aspect != ratio else { return }
        beginUndoGroup()
        let old = settings.trimBox
        settings.aspect = ratio
        remapElements(from: old, to: settings.trimBox)
        requestFit()
    }

    /// 誌面サイズが大きく変わったとき、要素を正規化座標で移し替える。
    /// 文字サイズは面積比の平方根でスケールして、見た目の比率を保つ。
    private func remapElements(from old: CGRect, to new: CGRect) {
        guard old.width > 0, old.height > 0, new.width > 0, new.height > 0 else { return }
        let sx = new.width / old.width
        let sy = new.height / old.height
        let fontScale = (sx * sy).squareRoot()
        guard abs(sx - 1) > 0.001 || abs(sy - 1) > 0.001 else { return }

        for b in boards.indices {
            for e in boards[b].elements.indices {
                let r = boards[b].elements[e].rect
                let unit = CGRect(x: (r.minX - old.minX) / old.width,
                                  y: (r.minY - old.minY) / old.height,
                                  width: r.width / old.width, height: r.height / old.height)
                boards[b].elements[e].rect = new.unitRect(unit)

                if case .text(var f) = boards[b].elements[e] {
                    f.rect = new.unitRect(unit)
                    f.fontSize = max(f.fontSize * fontScale, 1)
                    f.tracking *= fontScale
                    boards[b].elements[e] = .text(f)
                }
            }
        }
        dirty = true
    }

    // MARK: - 保存・読み込み

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url)
        fileURL = url
        dirty = false
        status = "保存しました: \(url.lastPathComponent)"
    }

    func load(from url: URL) throws {
        let file = try JSONDecoder().decode(ZineFile.self, from: Data(contentsOf: url))
        undoStack.removeAll(); redoStack.removeAll()
        settings = file.settings
        assets = file.assets
        boards = file.boards.isEmpty ? [Artboard()] : file.boards
        currentIndex = 0
        selection.removeAll()
        traySelection.removeAll()
        fileURL = url
        dirty = false
        status = "読み込みました: \(url.lastPathComponent)"
        requestFit()
    }

    func newDocument(kind: DocKind) {
        undoStack.removeAll(); redoStack.removeAll()
        var s = DocSettings()
        s.kind = kind
        if kind == .board { s.background = .white }
        settings = s
        assets = []
        boards = [Artboard()]
        currentIndex = 0
        selection.removeAll()
        traySelection.removeAll()
        fileURL = nil
        dirty = false
        status = ""
        requestFit()
    }
}
