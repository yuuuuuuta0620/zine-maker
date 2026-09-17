import CoreGraphics
import Foundation

/// PDF 書き出し。
/// 画面と同じ CanvasRenderer.draw を CGPDFContext に対して呼ぶので、
/// プレビューと出力がズレない。
enum PDFExporter {

    enum PageMode: String, CaseIterable, Identifiable, Codable {
        case spread      // 見開きのまま（写真集の閲覧用・面付け前）
        case singlePage  // 単ページ（多くの印刷所の標準入稿形式）
        var id: String { rawValue }
        var label: String { self == .spread ? "見開き" : "単ページ" }
    }

    /// PDF に写真をどう埋め込むか
    enum ImageCompression: Equatable {
        /// JPEG ストリームをそのまま埋め込む。実用上はこちら
        case jpeg(quality: Double)
        /// 可逆。ファイルは桁違いに大きくなる
        case lossless

        var jpegQuality: Double? { if case .jpeg(let q) = self { q } else { nil } }
        var label: String { self == .lossless ? "可逆（大きい）" : "JPEG（推奨）" }
    }

    struct Options {
        var mode: PageMode = .singlePage
        var dpi: Double = 350
        var compression: ImageCompression = .jpeg(quality: 0.92)
        /// トンボ・裁ち落としのボックス情報を入れる（印刷入稿向け）
        var printBoxes = true
        var title = "ZINE"
        var author = ""
    }

    enum ExportError: LocalizedError {
        case cannotCreateContext
        var errorDescription: String? { "PDF を作成できませんでした" }
    }

    static func export(boards: [Artboard], settings: DocSettings, assets: [UUID: PhotoAsset],
                       to url: URL, options: Options = .init()) throws {
        var docBox = settings.mediaBox
        let info: [CFString: Any] = [
            kCGPDFContextTitle: options.title,
            kCGPDFContextAuthor: options.author,
            kCGPDFContextCreator: "ZineMaker",
        ]
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &docBox, info as CFDictionary)
        else { throw ExportError.cannotCreateContext }

        // ボードは 1pt = 1px なので、等倍（72dpi）で出さないと無駄に巨大になる
        let effectiveDPI = settings.kind == .board ? 72.0 : options.dpi
        let renderOptions = CanvasRenderer.Options(
            guides: false,
            quality: .output(dpi: effectiveDPI, jpegQuality: options.compression.jpegQuality))

        // 組写真ボードは1枚1ページ。塗り足しもトンボもない。
        guard settings.kind == .zine else {
            for board in boards {
                ctx.beginPDFPage(pageInfo(media: settings.mediaBox, trim: nil, bleed: nil))
                CanvasRenderer.draw(board, settings: settings, assets: assets, in: ctx, options: renderOptions)
                ctx.endPDFPage()
            }
            ctx.closePDF()
            ImageStore.shared.purgeFullResolution()
            return
        }

        for board in boards {
            switch options.mode {
            case .spread:
                // MediaBox = 塗り足し込み、TrimBox = 仕上がり。この2つが入稿の要。
                ctx.beginPDFPage(pageInfo(media: settings.mediaBox,
                                          trim: options.printBoxes ? settings.trimBox : nil,
                                          bleed: options.printBoxes ? settings.mediaBox : nil))
                CanvasRenderer.draw(board, settings: settings, assets: assets, in: ctx, options: renderOptions)
                ctx.endPDFPage()

            case .singlePage:
                for i in 0..<settings.pagesPerSpread {
                    let pageTrim = settings.pageRect(i)
                    // ノド側にも塗り足しを付ける（隣ページの絵柄がそのまま回り込む）
                    let pageMedia = pageTrim.insetBy(dx: -settings.bleed, dy: -settings.bleed)
                    let localMedia = CGRect(origin: .zero, size: pageMedia.size)
                    let localTrim = CGRect(x: settings.bleed, y: settings.bleed,
                                           width: settings.pageWidth, height: settings.pageHeight)

                    ctx.beginPDFPage(pageInfo(media: localMedia,
                                              trim: options.printBoxes ? localTrim : nil,
                                              bleed: options.printBoxes ? localMedia : nil))
                    ctx.saveGState()
                    ctx.translateBy(x: -pageMedia.minX, y: -pageMedia.minY)
                    CanvasRenderer.draw(board, settings: settings, assets: assets, in: ctx, options: renderOptions)
                    ctx.restoreGState()
                    ctx.endPDFPage()
                }
            }
        }

        ctx.closePDF()
        ImageStore.shared.purgeFullResolution()
    }

    /// 書き出されるページ数
    static func pageCount(boards: Int, settings: DocSettings, mode: PageMode) -> Int {
        guard settings.kind == .zine, mode == .singlePage else { return boards }
        return boards * settings.pagesPerSpread
    }

    /// CGPDFContext のページ境界ボックスは CGRect を包んだ CFData で渡す。
    private static func pageInfo(media: CGRect, trim: CGRect?, bleed: CGRect?) -> CFDictionary {
        var info: [CFString: Any] = [
            kCGPDFContextMediaBox: boxData(media),
            kCGPDFContextCropBox: boxData(media),
        ]
        if let bleed { info[kCGPDFContextBleedBox] = boxData(bleed) }
        if let trim { info[kCGPDFContextTrimBox] = boxData(trim) }
        return info as CFDictionary
    }

    private static func boxData(_ rect: CGRect) -> CFData {
        var r = rect
        return withUnsafeBytes(of: &r) { buf in
            CFDataCreate(nil, buf.bindMemory(to: UInt8.self).baseAddress, MemoryLayout<CGRect>.size)!
        }
    }
}
