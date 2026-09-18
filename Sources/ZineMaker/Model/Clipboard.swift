import UniformTypeIdentifiers
import AppKit
import CoreGraphics
import Foundation

/// 要素の切り取り・コピー・貼り付け。
/// 判型の違うドキュメント間でも貼れるよう、位置は仕上がり枠に対する比率で持ち運ぶ。
/// 写真は参照だけだと別ドキュメントで解決できないので、実体も一緒に運ぶ。
struct ElementClipboard: Codable {
    var elements: [Element]
    /// elements が参照している写真
    var assets: [PhotoAsset] = []
    /// コピー元の仕上がり枠。貼り付け先の判型に合わせて比率で置き直す。
    var sourceTrim: CGRect
    var sourceKind: DocKind

    static let pasteboardType = NSPasteboard.PasteboardType("com.zinemaker.elements")
}

extension NSPasteboard {
    /// ZineMaker の要素が入っているか
    var hasZineElements: Bool {
        types?.contains(ElementClipboard.pasteboardType) == true
    }

    /// 画像ファイルが入っているか（Finder や他アプリからの貼り付け）
    var imageFileURLs: [URL] {
        guard let urls = readObjects(forClasses: [NSURL.self]) as? [URL] else { return [] }
        let readable = Set(ImageStore.readableTypes.map(\.identifier))
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
                .flatMap { readable.contains($0) } ?? false
        }
    }
}

extension AppState {

    // MARK: - 切り取り・コピー

    func copySelection() {
        guard !selection.isEmpty else { return }
        let picked = selectedElements
        let usedAssetIDs = Set(picked.compactMap { $0.imageFrame?.assetID }
                             + picked.compactMap { $0.textFrame?.linkedAssetID })
        let payload = ElementClipboard(
            elements: picked,
            assets: assets.filter { usedAssetIDs.contains($0.id) },
            sourceTrim: settings.trimBox,
            sourceKind: settings.kind
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: ElementClipboard.pasteboardType)
        // ほかのアプリでも拾えるよう、文字は素のテキストでも置いておく
        let text = picked.compactMap { element -> String? in
            guard let t = element.textFrame else { return nil }
            return CanvasRenderer.resolvedText(for: t, scene: currentScene)
        }.joined(separator: "\n")
        if !text.isEmpty { pb.setString(text, forType: .string) }

        status = "\(picked.count) 個をコピーしました"
    }

    func cutSelection() {
        guard !selection.isEmpty else { return }
        let count = selection.count
        copySelection()
        deleteSelected()
        status = "\(count) 個を切り取りました"
    }

    // MARK: - 貼り付け

    var canPaste: Bool {
        let pb = NSPasteboard.general
        return pb.hasZineElements || !pb.imageFileURLs.isEmpty
    }

    /// `at` を渡すとその位置を中心に置く（右クリックからの貼り付け）
    func paste(at point: CGPoint? = nil) {
        let pb = NSPasteboard.general

        // 画像ファイルが入っていれば取り込む
        let files = pb.imageFileURLs
        if !files.isEmpty, !pb.hasZineElements {
            let added = importPhotos(urls: files.sorted { $0.lastPathComponent < $1.lastPathComponent })
            if let first = added.first { addImageFrame(assetID: first.id, at: point) }
            return
        }

        guard let data = pb.data(forType: ElementClipboard.pasteboardType),
              let payload = try? JSONDecoder().decode(ElementClipboard.self, from: data),
              !payload.elements.isEmpty else { return }

        beginUndoGroup()

        // 足りない写真を取り込む。同じファイルなら使い回す。
        var idMap: [UUID: UUID] = [:]
        for asset in payload.assets {
            if let existing = assets.first(where: { $0.path == asset.path }) {
                idMap[asset.id] = existing.id
            } else {
                var copy = asset
                copy.id = UUID()
                assets.append(copy)
                idMap[asset.id] = copy.id
            }
        }

        // 判型が違っても崩れないよう、比率で置き直す
        let source = payload.sourceTrim
        let target = settings.trimBox
        let sameSize = abs(source.width - target.width) < 0.5 && abs(source.height - target.height) < 0.5

        func place(_ rect: CGRect) -> CGRect {
            guard !sameSize, source.width > 0, source.height > 0 else {
                // 同じ判型なら少しずらして重ならないようにする
                let d = settings.kind == .zine ? Pt.fromMM(4) : settings.boardLongEdge * 0.012
                return rect.offsetBy(dx: d, dy: -d)
            }
            let unit = CGRect(x: (rect.minX - source.minX) / source.width,
                              y: (rect.minY - source.minY) / source.height,
                              width: rect.width / source.width, height: rect.height / source.height)
            return target.unitRect(unit)
        }

        let fontScale = sameSize ? 1 : (target.width / max(source.width, 1) * target.height / max(source.height, 1)).squareRoot()

        var board = currentBoard
        var newIDs: Set<UUID> = []
        var placed: [Element] = []

        for element in payload.elements {
            var copy = element
            switch copy {
            case .image(var f):
                f.id = UUID()
                f.rect = place(f.rect)
                if let old = f.assetID { f.assetID = idMap[old] ?? old }
                copy = .image(f)
            case .text(var f):
                f.id = UUID()
                f.rect = place(f.rect)
                f.fontSize = max(f.fontSize * fontScale, 1)
                f.tracking *= fontScale
                if let old = f.linkedAssetID { f.linkedAssetID = idMap[old] ?? old }
                copy = .text(f)
            case .shape(var f):
                f.id = UUID()
                f.rect = place(f.rect)
                f.strokeWidth *= fontScale
                copy = .shape(f)
            }
            newIDs.insert(copy.id)
            placed.append(copy)
        }

        // 位置を指定されたら、まとまりの中心をそこへ移す
        if let point, let bounds = placed.map(\.rect).reduce(nil, { (acc: CGRect?, r) in acc?.union(r) ?? r }) {
            let dx = point.x - bounds.midX, dy = point.y - bounds.midY
            for i in placed.indices { placed[i].rect = placed[i].rect.offsetBy(dx: dx, dy: dy) }
        }

        board.elements.append(contentsOf: placed)
        currentBoard = board
        selection = newIDs
        status = sameSize
            ? "\(placed.count) 個を貼り付けました"
            : "\(placed.count) 個を貼り付けました（判型に合わせて置き直しました）"
    }

    /// 同じ位置に複製して、すぐ別ページへ持っていける形にする
    func duplicateToBoard(_ index: Int) {
        guard !selection.isEmpty, boards.indices.contains(index), index != currentIndex else { return }
        let picked = selectedElements
        beginUndoGroup()
        var target = boards[index]
        for element in picked {
            var copy = element
            switch copy {
            case .image(var f): f.id = UUID(); copy = .image(f)
            case .text(var f):  f.id = UUID(); copy = .text(f)
            case .shape(var f): f.id = UUID(); copy = .shape(f)
            }
            target.elements.append(copy)
        }
        boards[index] = target
        dirty = true
        status = "\(picked.count) 個を \(index + 1) ページ目へ送りました"
    }
}
