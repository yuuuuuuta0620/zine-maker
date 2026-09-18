import AppKit
import Combine
import CoreGraphics
import Foundation

final class AppState: ObservableObject, Identifiable {
    /// タブ1枚ぶん＝ドキュメント1つ
    let id = UUID()

    @Published var settings = DocSettings() { didSet { if settings != oldValue { dirty = true } } }
    @Published var meta = DocumentMeta() { didSet { if meta != oldValue { dirty = true } } }
    @Published var series: [Series] = []
    @Published var assets: [PhotoAsset] = []
    @Published var boards: [Artboard] = [Artboard()]
    @Published var currentIndex = 0
    @Published var selection: Set<UUID> = []
    /// 写真トレイで選ばれている写真
    @Published var traySelection: Set<UUID> = []
    @Published var fileURL: URL?
    @Published var dirty = false
    @Published var status = ""
    /// 書き出し中の進み具合（0〜1）。終わったら nil。
    @Published var exportProgress: Double?
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

    /// 作品番号・ページ番号・作品一覧を含む、ドキュメント全体を見た文脈
    var documentContext: DocumentContext {
        DocumentContext(settings: settings, meta: meta, series: series, assets: assets, boards: boards)
    }

    /// 現在のページを描くための文脈
    var currentScene: CanvasRenderer.Scene {
        documentContext.scene(forBoardAt: currentIndex)
    }

    func scene(forBoardAt index: Int) -> CanvasRenderer.Scene {
        documentContext.scene(forBoardAt: index)
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

    /// ファイルが見つからなくなった写真（別のMacで開いた、フォルダを動かした、など）
    var missingAssets: [PhotoAsset] {
        assets.filter { !FileManager.default.fileExists(atPath: $0.path) }
    }

    /// ブックマークを頼りに、動いた写真を自動で追い直す
    @discardableResult
    func followMovedPhotos() -> Int {
        var recovered = 0
        for i in assets.indices where !FileManager.default.fileExists(atPath: assets[i].path) {
            if assets[i].resolveFromBookmark() { recovered += 1 }
        }
        if recovered > 0 { dirty = true; ImageStore.shared.purgeAll() }
        return recovered
    }

    /// まだどの枠にも入っていない写真
    var unplacedAssets: [PhotoAsset] {
        let used = Set(boards.flatMap { $0.imageFrames.compactMap(\.assetID) })
        return assets.filter { !used.contains($0.id) }
    }

    func requestFit() { fitToken += 1 }

    /// タブに出す名前
    var displayName: String {
        if let url = fileURL { return url.deletingPathExtension().lastPathComponent }
        if !meta.title.isEmpty { return meta.title }
        return settings.kind == .zine ? "名称未設定のZINE" : "名称未設定の組写真"
    }

    /// 設定を反映した新規ドキュメント
    convenience init(kind: DocKind) {
        self.init()
        let prefs = Preferences.shared
        settings = prefs.makeSettings(kind: kind)
        showRulers = prefs.showRulers
        showColumns = prefs.showColumns
        showCustomGuides = prefs.showGuides
        snapEnabled = prefs.snapEnabled
        dirty = false
    }

    // MARK: - Undo

    private var snapshot: ZineFile {
        ZineFile(settings: settings, meta: meta, series: series, assets: assets, boards: boards)
    }

    /// 自動保存の控え用
    var snapshotFile: ZineFile { snapshot }

    /// 控えから戻す
    func restore(_ file: ZineFile, from original: URL?) {
        undoStack.removeAll(); redoStack.removeAll()
        settings = file.settings
        meta = file.meta
        series = file.series
        assets = file.assets
        boards = file.boards.isEmpty ? [Artboard()] : file.boards
        currentIndex = 0
        selection.removeAll()
        fileURL = original
        dirty = true        // 元のファイルにはまだ書いていない
        requestFit()
    }

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
        meta = file.meta
        series = file.series
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
            case .shape(var f): f.id = UUID(); f.rect = f.rect.offsetBy(dx: offset, dy: -offset); copy = .shape(f)
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
                case .shape(var f): f.id = UUID(); f.rect = f.rect.offsetBy(dx: offset.x, dy: offset.y); copy = .shape(f)
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

    func addShape(_ kind: ShapeKind, at point: CGPoint? = nil) {
        beginUndoGroup()
        let box = settings.contentBox
        let size: CGSize
        switch kind {
        case .line: size = CGSize(width: box.width * 0.4, height: 1)
        default:    size = CGSize(width: box.width * 0.3, height: box.height * 0.3)
        }
        let origin = point.map { CGPoint(x: $0.x - size.width / 2, y: $0.y - size.height / 2) }
            ?? CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2)
        var frame = ShapeFrame(rect: CGRect(origin: origin, size: size), kind: kind)
        frame.fill = kind == .line ? nil : settings.background.contrastingInk
        if kind == .line {
            frame.stroke = settings.background.contrastingInk
            frame.strokeWidth = settings.kind == .zine ? 0.5 : max(settings.boardLongEdge / 1400, 1)
        }
        currentBoard.elements.append(.shape(frame))
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
            case .shape(var f): f.id = UUID(); e = .shape(f)
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
        if Preferences.shared.autoResolvePlaces, !added.isEmpty { resolvePlaces() }
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

    // MARK: - ポートフォリオ

    /// 種別つきのページを追加する（表紙は先頭へ）
    func addPortfolioPage(_ role: BoardRole, series seriesRef: Series? = nil) {
        beginUndoGroup()
        let coverPhoto = role == .cover ? (traySelection.first ?? assets.first?.id) : nil
        let board = PortfolioPages.make(role, settings: settings, series: seriesRef, coverPhoto: coverPhoto)
        if role == .cover {
            boards.insert(board, at: 0)
            currentIndex = 0
        } else {
            boards.insert(board, at: currentIndex + 1)
            currentIndex += 1
        }
        selection.removeAll()
        status = "「\(role.label)」を追加しました"
    }

    func setRole(_ role: BoardRole) {
        beginUndoGroup()
        currentBoard.role = role
    }

    /// 表紙・ステートメント・作品一覧・プロフィールをまとめて用意する
    func scaffoldPortfolio() {
        beginUndoGroup()
        let cover = PortfolioPages.cover(settings: settings, withPhoto: traySelection.first ?? assets.first?.id)
        let statement = PortfolioPages.statement(settings: settings)
        let index = PortfolioPages.index(settings: settings)
        let profile = PortfolioPages.profile(settings: settings)
        boards.insert(contentsOf: [cover, statement], at: 0)
        boards.append(contentsOf: [index, profile])
        currentIndex = 0
        selection.removeAll()
        status = "表紙・ステートメント・作品一覧・プロフィールを追加しました"
    }

    // MARK: 写真集の型

    /// 現在のページを写真集の型で組み直す
    func applyBookStyle(_ key: String, title: String = "", subtitle: String = "") {
        beginUndoGroup()
        let style = BookLayouts.styles.first { $0.key == key }
        let need = style?.photoCount ?? 1
        var photos: [UUID] = []
        if need > 0 {
            let fromTray = assets.filter { traySelection.contains($0.id) }.map(\.id)
            let existing = currentBoard.imageFrames.compactMap(\.assetID)
            photos = Array((fromTray.isEmpty ? existing + unplacedAssets.map(\.id) : fromTray).prefix(need))
        }
        var board = BookLayouts.make(key, settings: settings, photos: photos, assets: assetIndex,
                                     title: title, subtitle: subtitle)
        board.seriesID = currentBoard.seriesID
        currentBoard = board
        traySelection.removeAll()
        selection.removeAll()
        status = "「\(style?.name ?? key)」で組み直しました"
    }

    /// 型を新しいページとして足す
    func addBookStyle(_ key: String, title: String = "", subtitle: String = "") {
        beginUndoGroup()
        boards.insert(Artboard(), at: currentIndex + 1)
        currentIndex += 1
        applyBookStyleWithoutUndo(key, title: title, subtitle: subtitle)
    }

    private func applyBookStyleWithoutUndo(_ key: String, title: String, subtitle: String) {
        let style = BookLayouts.styles.first { $0.key == key }
        let need = style?.photoCount ?? 1
        let photos = need > 0 ? Array(unplacedAssets.map(\.id).prefix(need)) : []
        currentBoard = BookLayouts.make(key, settings: settings, photos: photos, assets: assetIndex,
                                        title: title, subtitle: subtitle)
    }

    /// トレイの写真を「1枚＋撮影データ」で1枚ずつページにする
    func flowAsPlates(style: String = "plate") {
        let source = traySelection.isEmpty ? unplacedAssets : assets.filter { traySelection.contains($0.id) }
        guard !source.isEmpty else { status = "流し込む写真がありません"; return }
        beginUndoGroup()
        let per = max(BookLayouts.styles.first { $0.key == style }?.photoCount ?? 1, 1)
        let chunks = stride(from: 0, to: source.count, by: per).map {
            Array(source[$0..<min($0 + per, source.count)])
        }
        let start = currentIndex
        for (offset, chunk) in chunks.enumerated() {
            let index = start + offset
            if index >= boards.count { boards.append(Artboard()) }
            var board = BookLayouts.make(style, settings: settings, photos: chunk.map(\.id), assets: assetIndex)
            board.seriesID = boards[index].seriesID
            boards[index] = board
        }
        currentIndex = start
        traySelection.removeAll()
        selection.removeAll()
        status = "\(source.count) 枚を \(chunks.count) ページに組みました"
    }

    // MARK: 全ページ共通の要素

    func setPageNumberMaster(corner: BookLayouts.Corner, stacked: Bool) {
        beginUndoGroup()
        settings.masterElements = BookLayouts.pageNumberMaster(settings, corner: corner, stacked: stacked)
        status = "ノンブルを全ページに置きました"
    }

    func clearMaster() {
        beginUndoGroup()
        settings.masterElements = []
    }

    /// 選択中の要素を全ページ共通に移す
    func moveSelectionToMaster() {
        guard !selection.isEmpty else { return }
        beginUndoGroup()
        let moving = selectedElements
        currentBoard.elements.removeAll { selection.contains($0.id) }
        settings.masterElements.append(contentsOf: moving)
        selection.removeAll()
        status = "\(moving.count) 個を全ページ共通にしました"
    }

    func toggleMasterOnCurrentBoard() {
        beginUndoGroup()
        currentBoard.hidesMaster.toggle()
    }

    // MARK: シリーズ

    @discardableResult
    func addSeries(title: String = "新しいシリーズ") -> Series {
        beginUndoGroup()
        let s = Series(title: title)
        series.append(s)
        dirty = true
        return s
    }

    func renameSeries(_ id: UUID, title: String, subtitle: String) {
        guard let i = series.firstIndex(where: { $0.id == id }) else { return }
        beginUndoGroup()
        series[i].title = title
        series[i].subtitle = subtitle
    }

    func removeSeries(_ id: UUID) {
        beginUndoGroup()
        series.removeAll { $0.id == id }
        for i in boards.indices where boards[i].seriesID == id { boards[i].seriesID = nil }
    }

    func assignCurrentBoard(to seriesID: UUID?) {
        beginUndoGroup()
        currentBoard.seriesID = seriesID
    }

    /// 現在のページ以降、次の中扉までを同じシリーズにまとめる
    func assignFollowingBoards(to seriesID: UUID?) {
        beginUndoGroup()
        var i = currentIndex
        while i < boards.count {
            if i > currentIndex, boards[i].role == .divider { break }
            boards[i].seriesID = seriesID
            i += 1
        }
        status = "\(i - currentIndex) ページをまとめました"
    }

    // MARK: 見つからない写真の付け直し

    /// フォルダを指定して、同じファイル名の写真を探して繋ぎ直す
    func relinkMissing(in folder: URL) {
        let missing = missingAssets
        guard !missing.isEmpty else { status = "見つからない写真はありません"; return }

        var byName: [String: URL] = [:]
        if let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in e where byName[url.lastPathComponent] == nil {
                byName[url.lastPathComponent] = url
            }
        }

        beginUndoGroup()
        var fixed = 0
        for i in assets.indices {
            guard !FileManager.default.fileExists(atPath: assets[i].path),
                  let found = byName[assets[i].name] else { continue }
            assets[i].path = found.path
            assets[i].bookmark = PhotoAsset.makeBookmark(found)
            fixed += 1
        }
        dirty = true
        ImageStore.shared.purgeAll()
        status = fixed == 0
            ? "同じ名前の写真が見つかりませんでした"
            : "\(fixed) 枚を繋ぎ直しました" + (missing.count > fixed ? "（残り \(missing.count - fixed) 枚）" : "")
    }

    // MARK: 撮影地

    /// GPS を持つ写真の地名をまとめて引いて、アセットに保存する。
    /// 同じ座標はまとめて1回しか問い合わせない。一度引けば .zine に残る。
    func resolvePlaces() {
        let targets = assets.filter { ImageStore.shared.metadata(of: $0.url).hasGPS }
        guard !targets.isEmpty else { status = "GPSを持つ写真がありません"; return }
        status = "撮影地を調べています…"
        PlaceResolver.resolve(targets, progress: { [weak self] i, n in
            DispatchQueue.main.async { self?.status = "撮影地を調べています… \(i + 1)/\(n) 地点" }
        }) { [weak self] places in
            guard let self else { return }
            guard !places.isEmpty else { self.status = "撮影地を取得できませんでした（ネットワークを確認してください）"; return }
            self.beginUndoGroup()
            for i in self.assets.indices {
                if let p = places[self.assets[i].id] {
                    self.assets[i].placeShort = p.short
                    self.assets[i].placeFull = p.full
                }
            }
            self.dirty = true
            let names = Set(places.values.map(\.short)).sorted()
            self.status = "撮影地: \(names.joined(separator: " / "))"
        }
    }

    /// 撮影地をリボンで写真に重ねる
    func addPlaceRibbons() {
        beginUndoGroup()
        let targets = selection.isEmpty
            ? currentBoard.imageFrames.filter { $0.assetID != nil }
            : selectedElements.compactMap(\.imageFrame).filter { $0.assetID != nil }
        guard !targets.isEmpty else { status = "写真の入った枠がありません"; return }

        var board = currentBoard
        var added: Set<UUID> = []
        for frame in targets {
            let h = max(frame.rect.height * 0.075, settings.kind == .zine ? Pt.fromMM(6) : 34)
            let w = min(frame.rect.width * 0.62, frame.rect.width - h)
            var t = TextFrame(rect: CGRect(x: frame.rect.minX + h * 0.5,
                                           y: frame.rect.minY + h * 0.7,
                                           width: w, height: h))
            t.linkedAssetID = frame.assetID
            t.template = "{where}"
            t.text = "{where}"
            t.fontName = "HiraginoSans-W6"
            t.fontSize = h * 0.42
            t.alignment = .center
            t.tracking = h * 0.06
            t.color = .white
            t.plate = .ribbon
            t.plateColor = RGBA(r: 0.10, g: 0.10, b: 0.11, a: 0.82)
            t.platePadding = h * 0.28
            added.insert(t.id)
            board.elements.append(.text(t))
        }
        currentBoard = board
        selection = added
        status = "\(added.count) 枚にリボンを付けました"
    }

    // MARK: キャプション

    /// 選択中（なければページ全体）の写真枠に、紐づいたキャプション枠を付ける
    func addCaptions(template: String) {
        beginUndoGroup()
        let targets = selection.isEmpty
            ? currentBoard.imageFrames.filter { $0.assetID != nil }
            : selectedElements.compactMap(\.imageFrame).filter { $0.assetID != nil }
        guard !targets.isEmpty else { status = "写真の入った枠がありません"; return }

        var board = currentBoard
        var added: Set<UUID> = []
        for frame in targets {
            // すでに同じ写真のキャプションがあるなら作り直さない
            if board.elements.contains(where: { $0.textFrame?.linkedAssetID == frame.assetID && $0.textFrame?.isDynamic == true }) {
                continue
            }
            let caption = PortfolioPages.caption(for: frame, settings: settings, template: template)
            added.insert(caption.id)
            board.elements.append(.text(caption))
        }
        currentBoard = board
        selection = added
        status = added.isEmpty ? "すでにキャプションが付いています" : "\(added.count) 枚にキャプションを付けました"
    }

    /// テキスト枠を写真に紐づけて差し込みにする
    func linkCaption(textID: UUID, to assetID: UUID?, template: String?) {
        beginUndoGroup()
        update(id: textID) {
            if case .text(var f) = $0 {
                f.linkedAssetID = assetID
                f.template = template
                $0 = .text(f)
            }
        }
    }

    /// 差し込みをやめて、いま出ている文面をそのまま固定する
    func freezeCaption(textID: UUID) {
        guard let element = currentBoard.elements.first(where: { $0.id == textID }),
              let frame = element.textFrame else { return }
        let resolved = CanvasRenderer.resolvedText(for: frame, scene: currentScene)
        beginUndoGroup()
        update(id: textID) {
            if case .text(var f) = $0 { f.text = resolved; f.template = nil; $0 = .text(f) }
        }
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
        meta = file.meta
        series = file.series
        assets = file.assets
        boards = file.boards.isEmpty ? [Artboard()] : file.boards
        currentIndex = 0
        selection.removeAll()
        traySelection.removeAll()
        fileURL = url
        dirty = false

        // 写真が動いていたらブックマークで追い直す
        var recovered = 0
        for i in assets.indices where !FileManager.default.fileExists(atPath: assets[i].path) {
            if assets[i].resolveFromBookmark() { recovered += 1 }
        }
        _ = assets.map { $0.startAccessing() }

        status = recovered > 0
            ? "読み込みました: \(url.lastPathComponent)（移動した写真 \(recovered) 枚を追跡しました）"
            : "読み込みました: \(url.lastPathComponent)"
        requestFit()
    }

    func newDocument(kind: DocKind) {
        undoStack.removeAll(); redoStack.removeAll()
        var s = DocSettings()
        s.kind = kind
        if kind == .board { s.background = .white }
        settings = s
        meta = DocumentMeta()
        series = []
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
