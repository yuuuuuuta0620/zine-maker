import Foundation

/// キャプションの差し込み。`{camera}` のような記号を撮影情報や作品番号に置き換える。
/// テキストフレームが写真に紐づいていれば、写真を差し替えるだけで文面が追従する。
enum CaptionTemplate {

    struct Token: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        var text: String { "{\(key)}" }
    }

    static let photoTokens: [Token] = [
        .init(key: "plate",     label: "作品番号"),
        .init(key: "title",     label: "作品名（IPTC）"),
        .init(key: "caption",   label: "説明（IPTC）"),
        .init(key: "date",      label: "撮影日"),
        .init(key: "year",      label: "撮影年"),
        .init(key: "location",  label: "撮影地（IPTC）"),
        .init(key: "camera",    label: "カメラ"),
        .init(key: "lens",      label: "レンズ"),
        .init(key: "focal",     label: "焦点距離"),
        .init(key: "aperture",  label: "絞り"),
        .init(key: "shutter",   label: "シャッター"),
        .init(key: "iso",       label: "ISO"),
        .init(key: "exposure",  label: "撮影データ一式"),
        .init(key: "filename",  label: "ファイル名"),
        .init(key: "size",      label: "画素数"),
    ]

    static let documentTokens: [Token] = [
        .init(key: "doc.title",    label: "作品集タイトル"),
        .init(key: "doc.subtitle", label: "サブタイトル"),
        .init(key: "doc.author",   label: "著者名"),
        .init(key: "doc.email",    label: "メール"),
        .init(key: "doc.website",  label: "サイト"),
        .init(key: "doc.phone",    label: "電話"),
        .init(key: "doc.year",     label: "制作年"),
        .init(key: "doc.statement", label: "ステートメント"),
        .init(key: "series",       label: "シリーズ名"),
        .init(key: "series.subtitle", label: "シリーズ副題"),
        .init(key: "page",         label: "ページ番号"),
        .init(key: "pages",        label: "総ページ数"),
        .init(key: "index",        label: "作品一覧（自動生成）"),
    ]

    static var allTokens: [Token] { photoTokens + documentTokens }

    // MARK: - よく使う組み合わせ

    struct Preset: Identifiable {
        var id: String { name }
        let name: String
        let template: String
    }

    static let presets: [Preset] = [
        .init(name: "番号のみ",       template: "{plate}"),
        .init(name: "番号＋作品名",   template: "{plate}　{title}"),
        .init(name: "作品名＋撮影地", template: "{title}\n{location}　{year}"),
        .init(name: "撮影データ",     template: "{exposure}"),
        .init(name: "機材と撮影データ", template: "{camera} + {lens}\n{exposure}"),
        .init(name: "番号＋日付＋機材", template: "{plate}　{date}\n{camera} / {lens} / {exposure}"),
        .init(name: "ファイル名",     template: "{filename}"),
    ]

    // MARK: - 展開

    /// 差し込みに必要な周辺情報
    struct Context {
        var meta: DocumentMeta = DocumentMeta()
        var seriesTitle: String = ""
        var seriesSubtitle: String = ""
        var pageNumber: Int = 1
        var totalPages: Int = 1
        /// assetID → 作品番号
        var plateNumbers: [UUID: Int] = [:]
        /// 作品一覧（{index} に差し込む行）
        var indexLines: [String] = []
        var platePadding: Int = 2
    }

    static func render(_ template: String, asset: PhotoAsset?, context: Context) -> String {
        var values: [String: String] = [:]

        if let asset {
            let m = ImageStore.shared.metadata(of: asset.url)
            values["title"]    = m.title ?? asset.url.deletingPathExtension().lastPathComponent
            values["caption"]  = m.caption ?? ""
            values["date"]     = m.dateLabel() ?? ""
            values["year"]     = m.dateLabel("yyyy") ?? ""
            values["location"] = m.location ?? ""
            values["camera"]   = m.cameraLabel ?? ""
            values["lens"]     = m.lens ?? ""
            values["focal"]    = m.focalLabel ?? ""
            values["aperture"] = m.apertureLabel ?? ""
            values["shutter"]  = m.shutterLabel ?? ""
            values["iso"]      = m.isoLabel ?? ""
            values["exposure"] = m.exposureLine
            values["filename"] = asset.name
            values["size"]     = m.pixelSize.map { "\(Int($0.width))×\(Int($0.height)) px" } ?? ""
            if let n = context.plateNumbers[asset.id] {
                values["plate"] = String(format: "%0\(context.platePadding)d", n)
            } else {
                values["plate"] = ""
            }
        }

        values["doc.title"]     = context.meta.title
        values["doc.subtitle"]  = context.meta.subtitle
        values["doc.author"]    = context.meta.author
        values["doc.email"]     = context.meta.email
        values["doc.website"]   = context.meta.website
        values["doc.phone"]     = context.meta.phone
        values["doc.year"]      = context.meta.year
        values["doc.statement"] = context.meta.statement
        values["series"]          = context.seriesTitle
        values["series.subtitle"] = context.seriesSubtitle
        values["page"]  = "\(context.pageNumber)"
        values["pages"] = "\(context.totalPages)"
        values["index"] = context.indexLines.joined(separator: "\n")

        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return tidy(result)
    }

    /// 値が空だったところに残る区切り記号と空行を掃除する。
    /// 「{camera} / {lens}」でレンズが無いときに " / " が残らないようにする。
    private static func tidy(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var l = String(line)
                for separator in [" / ", " · ", "　/　", " | ", " — ", " - "] {
                    while l.hasPrefix(separator) { l.removeFirst(separator.count) }
                    while l.hasSuffix(separator) { l.removeLast(separator.count) }
                    // 中身が消えて区切りが連続したものを1つに畳む
                    l = l.replacingOccurrences(of: separator + separator, with: separator)
                }
                return l.trimmingCharacters(in: .whitespaces)
            }
            // 先頭・末尾の空行だけ落とす（本文中の意図的な空行は残す）
            .drop(while: \.isEmpty)
            .reversed().drop(while: \.isEmpty).reversed()
            .joined(separator: "\n")
    }
}
