import CoreGraphics
import Foundation

/// 作品番号・ページ番号・作品一覧など、1ページを描くのに必要な「全体を見た情報」をまとめる。
/// ドキュメント全体を一度走査して作り、各ページの描画に渡す。
struct DocumentContext {
    var settings: DocSettings
    var meta: DocumentMeta
    /// 作品一覧の各行の組み方
    var indexTemplate: String = "{plate}　{title}"
    var series: [Series]
    var assets: [PhotoAsset]
    var boards: [Artboard]

    var assetIndex: [UUID: PhotoAsset] {
        Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    }

    /// 作品ページに置かれた写真へ、出てくる順に番号を振る。
    /// 同じ写真が複数回出てきても番号は1つ。
    var plateNumbers: [UUID: Int] {
        var result: [UUID: Int] = [:]
        var next = 1
        for board in boards where board.role.countsAsPlate {
            // 上から下・左から右の順に読む
            let frames = board.imageFrames
                .filter { !$0.hidden }
                .sorted {
                    abs($0.rect.maxY - $1.rect.maxY) > 1 ? $0.rect.maxY > $1.rect.maxY
                                                         : $0.rect.minX < $1.rect.minX
                }
            for frame in frames {
                guard let id = frame.assetID, result[id] == nil else { continue }
                result[id] = next
                next += 1
            }
        }
        return result
    }

    /// 作品一覧ページに差し込む行
    func indexLines(template: String = "{plate}　{title}") -> [String] {
        let plates = plateNumbers
        let index = assetIndex
        var base = CaptionTemplate.Context()
        base.meta = meta
        base.plateNumbers = plates

        return plates.sorted { $0.value < $1.value }.compactMap { assetID, _ in
            guard let asset = index[assetID] else { return nil }
            let line = CaptionTemplate.render(template, asset: asset, context: base)
            return line.isEmpty ? nil : line
        }
    }

    /// ページ番号。ZINE の見開きは2ページ分進む。表紙は数に入れない。
    func pageNumber(forBoardAt boardIndex: Int) -> Int {
        var page = 1
        for i in 0..<min(boardIndex, boards.count) where boards[i].role != .cover {
            page += settings.pagesPerSpread
        }
        return page
    }

    var totalPages: Int {
        boards.filter { $0.role != .cover }.count * settings.pagesPerSpread
    }

    func seriesTitle(forBoardAt index: Int) -> Series? {
        guard boards.indices.contains(index), let id = boards[index].seriesID else { return nil }
        return series.first { $0.id == id }
    }

    /// 1ページ分の描画文脈
    func scene(forBoardAt index: Int, indexTemplate: String? = nil) -> CanvasRenderer.Scene {
        let indexTemplate = indexTemplate ?? self.indexTemplate
        var caption = CaptionTemplate.Context()
        caption.meta = meta
        caption.plateNumbers = plateNumbers
        caption.pageNumber = pageNumber(forBoardAt: index)
        caption.totalPages = totalPages
        caption.pagesPerSpread = settings.pagesPerSpread
        if let s = seriesTitle(forBoardAt: index) {
            caption.seriesTitle = s.title
            caption.seriesSubtitle = s.subtitle
        }
        // 作品一覧の行は、実際に {index} を使うページでだけ組み立てる
        if boards.indices.contains(index),
           boards[index].elements.contains(where: { $0.textFrame?.template?.contains("{index}") == true }) {
            caption.indexLines = indexLines(template: indexTemplate)
        }
        return CanvasRenderer.Scene(assets: assetIndex, caption: caption)
    }

    /// 全ページ分をまとめて作る（書き出し用。作品番号の走査を1回で済ませる）
    func allScenes(indexTemplate: String? = nil) -> [CanvasRenderer.Scene] {
        let indexTemplate = indexTemplate ?? self.indexTemplate
        let plates = plateNumbers
        let index = assetIndex
        let total = totalPages
        let lines = boards.contains(where: { b in
            b.elements.contains { $0.textFrame?.template?.contains("{index}") == true }
        }) ? indexLines(template: indexTemplate) : []

        return boards.indices.map { i in
            var caption = CaptionTemplate.Context()
            caption.meta = meta
            caption.plateNumbers = plates
            caption.pageNumber = pageNumber(forBoardAt: i)
            caption.totalPages = total
            caption.pagesPerSpread = settings.pagesPerSpread
            if let s = seriesTitle(forBoardAt: i) {
                caption.seriesTitle = s.title
                caption.seriesSubtitle = s.subtitle
            }
            caption.indexLines = lines
            return CanvasRenderer.Scene(assets: index, caption: caption)
        }
    }
}
