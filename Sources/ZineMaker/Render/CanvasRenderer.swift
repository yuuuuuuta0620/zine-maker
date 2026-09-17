import CoreGraphics
import CoreText
import Foundation

/// 誌面／ボードを描く唯一の場所。
/// 画面・PDF・書き出し画像・サムネイルは「どの CGContext を渡すか」だけが違い、
/// 描画コードは共有する。これが preview と書き出しのズレを構造的に防ぐ。
enum CanvasRenderer {

    /// 画像をどの解像度でデコードするか。
    enum ImageQuality {
        /// 画面用。長辺上限を決めて非同期に読む
        case screen(maxPixel: Int)
        /// 書き出し用。「配置サイズ × 目標DPI」から必要画素数を逆算して同期で読む。
        /// `jpegQuality` を渡すと JPEG で裏打ちした CGImage を描く（PDF が桁違いに小さくなる）。
        case output(dpi: Double, jpegQuality: Double?)
    }

    struct Options {
        /// 仕上がり線・塗り足し・余白ガイドを描く（画面のみ true）
        var guides = false
        /// 段組みのガイドを描く
        var showColumns = false
        /// 自分で引いたガイドを描く
        var showCustomGuides = true
        var quality: ImageQuality = .screen(maxPixel: 2048)
        /// ガイド線の太さ（画面上で 1px になる pt 値）
        var hairline: CGFloat = 0.5
        /// 背景を塗るか（PNG を透過で出したいときだけ false）
        var drawBackground = true
    }

    // MARK: - 本体

    static func draw(_ board: Artboard, settings: DocSettings, assets: [UUID: PhotoAsset],
                     in ctx: CGContext, options: Options = .init()) {
        ctx.saveGState()
        if options.drawBackground {
            ctx.setFillColor(settings.background.cgColor)
            ctx.fill(settings.mediaBox)
        }

        for element in board.elements {
            // 非表示の要素は画面でも書き出しでも描かない
            if element.hidden { continue }

            ctx.saveGState()
            if element.rotation != 0 { ctx.concatenate(element.transform) }
            switch element {
            case .image(let frame): drawImage(frame, assets: assets, in: ctx, options: options)
            case .text(let frame):  drawText(frame, in: ctx)
            }
            ctx.restoreGState()
        }

        if options.guides {
            drawGuides(settings: settings, in: ctx, hairline: options.hairline,
                       showColumns: options.showColumns, showCustom: options.showCustomGuides)
        }
        ctx.restoreGState()
    }

    // MARK: - 写真

    static func drawImage(_ frame: ImageFrame, assets: [UUID: PhotoAsset],
                          in ctx: CGContext, options: Options) {
        let path = roundedPath(frame.rect, radius: frame.cornerRadius)

        guard let id = frame.assetID, let asset = assets[id],
              let pixelSize = ImageStore.shared.pixelSize(of: asset.url) else {
            if options.guides { drawPlaceholder(frame, path: path, in: ctx, hairline: options.hairline) }
            strokeIfNeeded(frame, path: path, in: ctx)
            return
        }

        let target = contentRect(for: frame, imageSize: pixelSize)
        let cg: CGImage?
        switch options.quality {
        case .screen(let px):
            cg = ImageStore.shared.imageAsync(at: asset.url, maxPixel: px)
        case .output(let dpi, let jpegQuality):
            // 配置される物理サイズに必要な画素数だけ読む。元画像を超えて水増ししない。
            let needed = max(target.width, target.height) / 72.0 * CGFloat(dpi)
            let original = max(pixelSize.width, pixelSize.height)
            let decoded = ImageStore.shared.image(at: asset.url, maxPixel: Int(ceil(min(needed, original))))
            if let decoded, let q = jpegQuality {
                cg = ImageStore.jpegBacked(decoded, quality: q) ?? decoded
            } else {
                cg = decoded
            }
        }

        guard let cg else {
            if options.guides { drawLoading(frame, path: path, in: ctx) }
            strokeIfNeeded(frame, path: path, in: ctx)
            return
        }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: target)
        ctx.restoreGState()
        strokeIfNeeded(frame, path: path, in: ctx)
    }

    /// 枠内に写真をどう置くか。fit/fill の基準倍率に contentScale と contentOffset を重ねる。
    static func contentRect(for frame: ImageFrame, imageSize: CGSize) -> CGRect {
        let r = frame.rect
        guard imageSize.width > 0, imageSize.height > 0 else { return r }

        let sx = r.width / imageSize.width
        let sy = r.height / imageSize.height
        let base = frame.fitMode == .fill ? max(sx, sy) : min(sx, sy)
        let scale = base * frame.contentScale

        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: r.midX - size.width / 2 + frame.contentOffset.x,
                      y: r.midY - size.height / 2 + frame.contentOffset.y,
                      width: size.width, height: size.height)
    }

    static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, min(rect.width, rect.height) / 2)
        return r <= 0 ? CGPath(rect: rect, transform: nil)
                      : CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func strokeIfNeeded(_ frame: ImageFrame, path: CGPath, in ctx: CGContext) {
        guard frame.strokeWidth > 0 else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(frame.strokeColor.cgColor)
        ctx.setLineWidth(frame.strokeWidth)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawPlaceholder(_ frame: ImageFrame, path: CGPath, in ctx: CGContext, hairline: CGFloat) {
        let rect = frame.rect
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 0.72, alpha: 1))
        ctx.setLineWidth(hairline * 2)
        ctx.setLineDash(phase: 0, lengths: [hairline * 6, hairline * 4])
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        // 中央に小さな×
        let s = min(rect.width, rect.height) * 0.12
        ctx.setStrokeColor(CGColor(gray: 0.65, alpha: 1))
        ctx.setLineWidth(hairline * 2)
        ctx.move(to: CGPoint(x: rect.midX - s, y: rect.midY - s))
        ctx.addLine(to: CGPoint(x: rect.midX + s, y: rect.midY + s))
        ctx.move(to: CGPoint(x: rect.midX - s, y: rect.midY + s))
        ctx.addLine(to: CGPoint(x: rect.midX + s, y: rect.midY - s))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawLoading(_ frame: ImageFrame, path: CGPath, in ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0.86, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - テキスト（Core Text）

    /// 組版は Core Text に任せる。禁則処理・縦組みが標準で効き、
    /// 画面と PDF が同じエンジンを通るので行位置が一致する。
    static func attributedString(for frame: TextFrame) -> NSAttributedString {
        let font = CTFontCreateWithName(frame.fontName as CFString, frame.fontSize, nil)
        let style = makeParagraphStyle(alignment: frame.alignment,
                                       lineHeight: frame.fontSize * frame.lineHeightScale)

        var attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): frame.color.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ]
        if frame.tracking != 0 {
            attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = frame.tracking
        }
        if frame.vertical {
            attrs[NSAttributedString.Key(kCTVerticalFormsAttributeName as String)] = true
        }
        return NSAttributedString(string: frame.text, attributes: attrs)
    }

    private static func makeParagraphStyle(alignment: TextAlign, lineHeight: CGFloat) -> CTParagraphStyle {
        var align: CTTextAlignment = {
            switch alignment {
            case .left: .left; case .center: .center; case .right: .right; case .justified: .justified
            }
        }()
        var minLine = lineHeight
        var maxLine = lineHeight

        return withUnsafeBytes(of: &align) { alignPtr in
            withUnsafeBytes(of: &minLine) { minPtr in
                withUnsafeBytes(of: &maxLine) { maxPtr in
                    let settings = [
                        CTParagraphStyleSetting(spec: .alignment,
                                                valueSize: MemoryLayout<CTTextAlignment>.size,
                                                value: alignPtr.baseAddress!),
                        CTParagraphStyleSetting(spec: .minimumLineHeight,
                                                valueSize: MemoryLayout<CGFloat>.size,
                                                value: minPtr.baseAddress!),
                        CTParagraphStyleSetting(spec: .maximumLineHeight,
                                                valueSize: MemoryLayout<CGFloat>.size,
                                                value: maxPtr.baseAddress!),
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }
    }

    static func drawText(_ frame: TextFrame, in ctx: CGContext) {
        guard !frame.text.isEmpty else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(for: frame))
        let path = CGPath(rect: frame.rect, transform: nil)

        var frameAttrs: [CFString: Any] = [:]
        if frame.vertical {
            frameAttrs[kCTFrameProgressionAttributeName] = CTFrameProgression.rightToLeft.rawValue
        }
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path,
                                               frameAttrs.isEmpty ? nil : frameAttrs as CFDictionary)
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(ctFrame, ctx)
        ctx.restoreGState()
    }

    /// テキストが枠に収まりきらないか（あふれ表示に使う）
    static func textOverflows(_ frame: TextFrame) -> Bool {
        guard !frame.text.isEmpty else { return false }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(for: frame))
        let path = CGPath(rect: frame.rect, transform: nil)
        var attrs: [CFString: Any] = [:]
        if frame.vertical { attrs[kCTFrameProgressionAttributeName] = CTFrameProgression.rightToLeft.rawValue }
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path,
                                               attrs.isEmpty ? nil : attrs as CFDictionary)
        let visible = CTFrameGetVisibleStringRange(ctFrame)
        return visible.length < (frame.text as NSString).length
    }

    // MARK: - ガイド（画面のみ／書き出しには出ない）

    private static func drawGuides(settings: DocSettings, in ctx: CGContext, hairline: CGFloat,
                                   showColumns: Bool = false, showCustom: Bool = true) {
        ctx.saveGState()
        ctx.setLineWidth(hairline)

        if settings.kind == .zine {
            ctx.setStrokeColor(CGColor(srgbRed: 0.0, green: 0.55, blue: 0.95, alpha: 0.9))
            ctx.stroke(settings.trimBox)

            ctx.setStrokeColor(CGColor(srgbRed: 0.95, green: 0.25, blue: 0.25, alpha: 0.45))
            ctx.stroke(settings.mediaBox.insetBy(dx: hairline / 2, dy: hairline / 2))
        }

        // 余白ガイド
        ctx.setStrokeColor(CGColor(srgbRed: 0.25, green: 0.8, blue: 0.45, alpha: 0.55))
        ctx.setLineDash(phase: 0, lengths: [hairline * 5, hairline * 4])
        for i in 0..<settings.pagesPerSpread {
            ctx.stroke(settings.marginBox(i))
        }
        ctx.setLineDash(phase: 0, lengths: [])

        // 段組み
        if showColumns, !settings.columnRects.isEmpty {
            ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.55, blue: 1.0, alpha: 0.10))
            for rect in settings.columnRects { ctx.fill(rect) }
        }

        // 自分で引いたガイド
        if showCustom {
            ctx.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.75, blue: 1.0, alpha: 0.95))
            ctx.setLineWidth(hairline)
            let media = settings.mediaBox
            for x in settings.verticalGuideXs {
                ctx.move(to: CGPoint(x: x, y: media.minY)); ctx.addLine(to: CGPoint(x: x, y: media.maxY))
            }
            for y in settings.horizontalGuideYs {
                ctx.move(to: CGPoint(x: media.minX, y: y)); ctx.addLine(to: CGPoint(x: media.maxX, y: y))
            }
            ctx.strokePath()
        }

        // ノド
        if let gx = settings.gutterX {
            ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 0.7))
            ctx.move(to: CGPoint(x: gx, y: settings.trimBox.minY))
            ctx.addLine(to: CGPoint(x: gx, y: settings.trimBox.maxY))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - サムネイル

    /// サイドバーや書き出しプレビュー用のラスタ化。描画経路は本番と同じ。
    static func rasterize(_ board: Artboard, settings: DocSettings, assets: [UUID: PhotoAsset],
                          longEdge: CGFloat, includeBleed: Bool = false,
                          quality: ImageQuality = .screen(maxPixel: 512)) -> CGImage? {
        let source = includeBleed ? settings.mediaBox : settings.trimBox
        guard source.width > 0, source.height > 0 else { return nil }
        let scale = longEdge / max(source.width, source.height)
        let w = max(Int((source.width * scale).rounded()), 1)
        let h = max(Int((source.height * scale).rounded()), 1)

        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -source.minX, y: -source.minY)
        ctx.clip(to: source)
        draw(board, settings: settings, assets: assets, in: ctx,
             options: .init(guides: false, quality: quality))
        return ctx.makeImage()
    }
}
