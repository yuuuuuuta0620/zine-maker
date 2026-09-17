import CoreGraphics
import Foundation

/// 表紙・ステートメント・プロフィール・作品一覧・中扉の雛形。
/// 中身は差し込みテンプレートにしてあるので、ドキュメント情報を直せば全ページ追従する。
enum PortfolioPages {

    /// 判型に対して素直な文字サイズ（ZINEは pt、ボードは px なので基準が違う）
    private static func scale(_ settings: DocSettings) -> CGFloat {
        settings.kind == .zine ? 1 : settings.trimBox.height / 900
    }

    private static func text(_ rect: CGRect, _ template: String, size: CGFloat,
                             settings: DocSettings, weight: String = "HiraginoSans-W3",
                             align: TextAlign = .left, leading: CGFloat = 1.7,
                             color: RGBA? = nil) -> Element {
        var f = TextFrame(rect: rect)
        f.template = template
        f.text = template
        f.fontName = weight
        f.fontSize = size * scale(settings)
        f.alignment = align
        f.lineHeightScale = leading
        f.color = color ?? settings.background.contrastingInk
        return .text(f)
    }

    // MARK: - 表紙

    static func cover(settings: DocSettings, withPhoto assetID: UUID? = nil) -> Artboard {
        var board = Artboard(role: .cover)
        let trim = settings.trimBox
        let box = settings.contentBox

        if let assetID {
            // 全面に敷いて裁ち落とす
            var photo = ImageFrame(rect: settings.mediaBox)
            photo.assetID = assetID
            board.elements.append(.image(photo))
        }

        // 写真を敷くなら、その上で読めるように白抜きにする
        let ink: RGBA? = assetID == nil ? nil : .white
        let titleHeight = trim.height * 0.16
        board.elements.append(text(
            CGRect(x: box.minX, y: box.minY + box.height * 0.22, width: box.width, height: titleHeight),
            "{doc.title}", size: 30, settings: settings, weight: "HiraMinProN-W6",
            align: .center, leading: 1.4, color: ink))
        board.elements.append(text(
            CGRect(x: box.minX, y: box.minY + box.height * 0.14, width: box.width, height: titleHeight * 0.5),
            "{doc.subtitle}", size: 12, settings: settings, align: .center, color: ink))
        board.elements.append(text(
            CGRect(x: box.minX, y: box.minY, width: box.width, height: titleHeight * 0.5),
            "{doc.author}", size: 11, settings: settings, align: .center, color: ink))
        return board
    }

    // MARK: - ステートメント

    static func statement(settings: DocSettings) -> Artboard {
        var board = Artboard(role: .statement)
        let box = settings.marginBox(settings.pagesPerSpread - 1)   // 見開きなら右ページ
        board.elements.append(text(
            CGRect(x: box.minX, y: box.maxY - box.height * 0.1, width: box.width, height: box.height * 0.1),
            "Statement", size: 11, settings: settings, weight: "HiraginoSans-W6"))
        board.elements.append(text(
            CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height * 0.84),
            "{doc.statement}", size: 9.5, settings: settings, leading: 2.0))
        return board
    }

    // MARK: - プロフィール

    static func profile(settings: DocSettings) -> Artboard {
        var board = Artboard(role: .profile)
        let box = settings.marginBox(settings.pagesPerSpread - 1)
        let unit = box.height * 0.09
        board.elements.append(text(
            CGRect(x: box.minX, y: box.maxY - unit, width: box.width, height: unit),
            "{doc.author}", size: 16, settings: settings, weight: "HiraMinProN-W6"))
        board.elements.append(text(
            CGRect(x: box.minX, y: box.minY + unit * 2.4, width: box.width, height: box.height * 0.5),
            "{doc.statement}", size: 9, settings: settings, leading: 2.0))
        board.elements.append(text(
            CGRect(x: box.minX, y: box.minY, width: box.width, height: unit * 2.2),
            "{doc.email}\n{doc.website}\n{doc.phone}", size: 9, settings: settings, leading: 1.9))
        return board
    }

    // MARK: - 作品一覧

    static func index(settings: DocSettings) -> Artboard {
        var board = Artboard(role: .index)
        let box = settings.contentBox
        board.elements.append(text(
            CGRect(x: box.minX, y: box.maxY - box.height * 0.08, width: box.width, height: box.height * 0.08),
            "List of Works", size: 11, settings: settings, weight: "HiraginoSans-W6"))
        board.elements.append(text(
            CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height * 0.86),
            "{index}", size: 8.5, settings: settings, leading: 2.1))
        return board
    }

    // MARK: - 中扉

    static func divider(settings: DocSettings, series: Series?) -> Artboard {
        var board = Artboard(role: .divider)
        board.seriesID = series?.id
        board.title = series?.title ?? ""
        let box = settings.contentBox
        board.elements.append(text(
            CGRect(x: box.minX, y: box.midY, width: box.width, height: box.height * 0.16),
            "{series}", size: 20, settings: settings, weight: "HiraMinProN-W6", align: .center, leading: 1.5))
        board.elements.append(text(
            CGRect(x: box.minX, y: box.midY - box.height * 0.08, width: box.width, height: box.height * 0.08),
            "{series.subtitle}", size: 10, settings: settings, align: .center))
        return board
    }

    static func make(_ role: BoardRole, settings: DocSettings, series: Series? = nil,
                     coverPhoto: UUID? = nil) -> Artboard {
        switch role {
        case .cover:     cover(settings: settings, withPhoto: coverPhoto)
        case .statement: statement(settings: settings)
        case .profile:   profile(settings: settings)
        case .index:     index(settings: settings)
        case .divider:   divider(settings: settings, series: series)
        case .content:   Artboard()
        }
    }

    // MARK: - キャプションの自動付与

    /// 写真枠の下に、その写真へ紐づいたキャプション枠を作る
    static func caption(for frame: ImageFrame, settings: DocSettings,
                        template: String, height: CGFloat? = nil) -> TextFrame {
        let h = height ?? max(frame.rect.height * 0.1, settings.kind == .zine ? Pt.fromMM(8) : 40)
        var caption = TextFrame(rect: CGRect(x: frame.rect.minX, y: frame.rect.minY - h - h * 0.2,
                                             width: frame.rect.width, height: h))
        caption.linkedAssetID = frame.assetID
        caption.template = template
        caption.text = template
        caption.fontName = "HiraginoSans-W3"
        caption.fontSize = (settings.kind == .zine ? 7 : 22) * scale(settings)
        caption.lineHeightScale = 1.5
        caption.color = settings.background.contrastingInk
        return caption
    }
}
