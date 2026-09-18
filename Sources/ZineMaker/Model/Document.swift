import CoreGraphics
import Foundation

/// 保存済みドキュメントの前方互換のための補助。
///
/// Swift の自動生成デコーダは、キーが無いときにプロパティの初期値へ落ちてくれず
/// `keyNotFound` を投げる。つまりフィールドを1つ足すだけで過去の .zine が全部開けなくなる。
/// 値を持つ型は自前の `init(from:)` を書き、この `value(_:_:)` を通して読む。
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}


// MARK: - ドキュメントの種類

enum DocKind: String, Codable, CaseIterable, Identifiable {
    /// 冊子。ページ・塗り足し・見開きがある
    case zine
    /// 任意アスペクト比の1枚もの（SNSの組写真）
    case board

    var id: String { rawValue }
    var label: String { self == .zine ? "ZINE・写真集" : "組写真（SNS）" }
    var icon: String { self == .zine ? "book.closed" : "square.grid.2x2" }
    var unitLabel: String { self == .zine ? "見開き" : "ボード" }
}

// MARK: - 判型

struct PagePreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let widthMM: Double
    let heightMM: Double

    static let all: [PagePreset] = [
        .init(name: "A5", widthMM: 148, heightMM: 210),
        .init(name: "B5", widthMM: 182, heightMM: 257),
        .init(name: "A4", widthMM: 210, heightMM: 297),
        .init(name: "A6 / 文庫", widthMM: 105, heightMM: 148),
        .init(name: "正方形 180", widthMM: 180, heightMM: 180),
        .init(name: "正方形 210", widthMM: 210, heightMM: 210),
        .init(name: "A4 ヨコ", widthMM: 297, heightMM: 210),
        .init(name: "A5 ヨコ", widthMM: 210, heightMM: 148),
        .init(name: "4:3 ヨコ（画面・PDF向け）", widthMM: 280, heightMM: 210),
        .init(name: "16:9 ヨコ", widthMM: 320, heightMM: 180),
    ]
    var label: String { "\(name)（\(Int(widthMM))×\(Int(heightMM))）" }
}

struct DocSettings: Codable, Equatable {
    var kind: DocKind = .zine

    // ZINE
    var pageWidthMM: Double = 148
    var pageHeightMM: Double = 210
    var bleedMM: Double = 3
    var marginMM: Double = 12
    var facing: Bool = true

    // 組写真ボード
    var aspect: AspectRatio = .portrait45
    /// 長辺のピクセル数（書き出し時の実寸）
    var boardLongEdge: Double = 2048
    /// 外周の余白（長辺に対する%）
    var boardPaddingPct: Double = 3
    /// 写真同士の間隔（長辺に対する%）
    var boardGutterPct: Double = 1.5

    var background: RGBA = .white

    /// 全ページの下に敷く共通要素（罫線・ノンブルなど）。ページ側で個別に外せる。
    var masterElements: [Element] = []

    // MARK: ガイドと段組み

    /// 自分で引いた縦ガイド。仕上がり枠に対する 0...1 の正規化座標で持つので、
    /// 判型やアスペクト比を変えても相対位置が保たれる。
    var verticalGuides: [Double] = []
    var horizontalGuides: [Double] = []

    /// 段組み（0 で無効）
    var columns: Int = 0
    var rows: Int = 0
    /// 段間。ZINE は mm、ボードは長辺に対する%
    var columnGutter: Double = 4

    // MARK: 派生値

    var pageWidth: CGFloat { Pt.fromMM(pageWidthMM) }
    var pageHeight: CGFloat { Pt.fromMM(pageHeightMM) }
    var bleed: CGFloat { kind == .zine ? Pt.fromMM(bleedMM) : 0 }
    var margin: CGFloat { kind == .zine ? Pt.fromMM(marginMM) : boardPadding }

    var pagesPerSpread: Int { kind == .zine && facing ? 2 : 1 }

    /// ボードの内部サイズ（1pt = 1px）
    var boardSize: CGSize { aspect.size(longEdge: boardLongEdge) }
    var boardPadding: CGFloat { CGFloat(boardLongEdge * boardPaddingPct / 100) }
    var boardGutter: CGFloat { CGFloat(boardLongEdge * boardGutterPct / 100) }

    /// 仕上がりサイズ（トンボ内側）
    var trimBox: CGRect {
        switch kind {
        case .zine:
            return CGRect(x: bleed, y: bleed,
                          width: pageWidth * CGFloat(pagesPerSpread), height: pageHeight)
        case .board:
            return CGRect(origin: .zero, size: boardSize)
        }
    }

    /// 塗り足しを含む外周＝PDF の MediaBox
    var mediaBox: CGRect {
        kind == .zine
            ? CGRect(x: 0, y: 0, width: trimBox.width + bleed * 2, height: trimBox.height + bleed * 2)
            : trimBox
    }

    /// 要素を置く内側の領域
    var contentBox: CGRect { trimBox.insetBy(dx: margin, dy: margin) }

    /// ノド（見開き中央）
    var gutterX: CGFloat? { kind == .zine && facing ? trimBox.midX : nil }

    /// ページ i の仕上がり矩形
    func pageRect(_ i: Int) -> CGRect {
        CGRect(x: trimBox.minX + pageWidth * CGFloat(i), y: trimBox.minY,
               width: pageWidth, height: pageHeight)
    }

    /// ページ i の余白内側
    func marginBox(_ i: Int) -> CGRect {
        kind == .zine ? pageRect(i).insetBy(dx: margin, dy: margin) : contentBox
    }

    /// 段間の実寸（pt）
    var gutterLength: CGFloat {
        kind == .zine ? Pt.fromMM(columnGutter) : CGFloat(boardLongEdge * columnGutter / 100)
    }

    /// 縦ガイドの実座標（pt）
    var verticalGuideXs: [CGFloat] {
        verticalGuides.map { trimBox.minX + CGFloat($0) * trimBox.width }
    }
    var horizontalGuideYs: [CGFloat] {
        horizontalGuides.map { trimBox.minY + CGFloat($0) * trimBox.height }
    }

    /// 段組みの各カラムの矩形。ZINE の見開きではページごとに割る。
    var columnRects: [CGRect] {
        guard columns > 0 || rows > 0 else { return [] }
        let cols = max(columns, 1), rws = max(rows, 1)
        let g = gutterLength
        var result: [CGRect] = []
        for page in 0..<pagesPerSpread {
            let box = marginBox(page)
            let cw = (box.width - g * CGFloat(cols - 1)) / CGFloat(cols)
            let ch = (box.height - g * CGFloat(rws - 1)) / CGFloat(rws)
            guard cw > 0, ch > 0 else { continue }
            for r in 0..<rws {
                for c in 0..<cols {
                    result.append(CGRect(x: box.minX + (cw + g) * CGFloat(c),
                                         y: box.maxY - ch - (ch + g) * CGFloat(r),
                                         width: cw, height: ch))
                }
            }
        }
        return result
    }

    /// 段組みが作る吸着候補の x / y
    var columnSnapXs: [CGFloat] {
        Array(Set(columnRects.flatMap { [$0.minX, $0.maxX] })).sorted()
    }
    var columnSnapYs: [CGFloat] {
        Array(Set(columnRects.flatMap { [$0.minY, $0.maxY] })).sorted()
    }

    // MARK: 互換デコード

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind             = c.value(.kind, .zine)
        pageWidthMM      = c.value(.pageWidthMM, 148)
        pageHeightMM     = c.value(.pageHeightMM, 210)
        bleedMM          = c.value(.bleedMM, 3)
        marginMM         = c.value(.marginMM, 12)
        facing           = c.value(.facing, true)
        aspect           = c.value(.aspect, .portrait45)
        boardLongEdge    = c.value(.boardLongEdge, 2048)
        boardPaddingPct  = c.value(.boardPaddingPct, 3)
        boardGutterPct   = c.value(.boardGutterPct, 1.5)
        background       = c.value(.background, .white)
        verticalGuides   = c.value(.verticalGuides, [])
        horizontalGuides = c.value(.horizontalGuides, [])
        columns          = c.value(.columns, 0)
        rows             = c.value(.rows, 0)
        columnGutter     = c.value(.columnGutter, 4)
        masterElements   = c.value(.masterElements, [])
    }

    var displaySize: String {
        switch kind {
        case .zine:
            let w = pageWidthMM * Double(pagesPerSpread)
            return "\(Int(w))×\(Int(pageHeightMM)) mm"
        case .board:
            return "\(Int(boardSize.width))×\(Int(boardSize.height)) px"
        }
    }
}

// MARK: - ポートフォリオ

/// 作品集全体の情報。表紙やプロフィールページに差し込む。
struct DocumentMeta: Codable, Equatable {
    var title = ""
    var subtitle = ""
    var author = ""
    var email = ""
    var website = ""
    var phone = ""
    var statement = ""
    var year = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title     = c.value(.title, "")
        subtitle  = c.value(.subtitle, "")
        author    = c.value(.author, "")
        email     = c.value(.email, "")
        website   = c.value(.website, "")
        phone     = c.value(.phone, "")
        statement = c.value(.statement, "")
        year      = c.value(.year, "")
    }
}

/// 作品のまとまり（章）
struct Series: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var title = ""
    var subtitle = ""

    init(title: String = "", subtitle: String = "") {
        self.title = title
        self.subtitle = subtitle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = c.value(.id, UUID())
        title    = c.value(.title, "")
        subtitle = c.value(.subtitle, "")
    }
}

/// ページの役割。作品ページ以外は通し番号から外す。
enum BoardRole: String, Codable, CaseIterable, Identifiable {
    case content, cover, statement, profile, index, divider

    var id: String { rawValue }
    var label: String {
        switch self {
        case .content: "作品"; case .cover: "表紙"; case .statement: "ステートメント"
        case .profile: "プロフィール"; case .index: "作品一覧"; case .divider: "中扉"
        }
    }
    var icon: String {
        switch self {
        case .content: "photo"; case .cover: "book.closed"; case .statement: "text.quote"
        case .profile: "person.crop.square"; case .index: "list.number"; case .divider: "rectangle.split.1x2"
        }
    }
    /// 作品番号を振る対象か
    var countsAsPlate: Bool { self == .content }
}

// MARK: - 写真アセット

/// ドキュメントが抱える写真。トレイに並び、フレームから ID で参照される。
struct PhotoAsset: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var path: String
    /// GPS から引いた地名。一度引けば保存され、以後はオフラインでも出る。
    var placeShort: String?
    var placeFull: String?

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }

    init(path: String) { self.path = path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = c.value(.id, UUID())
        path       = c.value(.path, "")
        placeShort = c.value(.placeShort, String?.none)
        placeFull  = c.value(.placeFull, String?.none)
    }
}

// MARK: - 要素

enum FitMode: String, Codable, CaseIterable {
    case fill   // 枠を埋める（はみ出しをクロップ）
    case fit    // 枠に収める
    var label: String { self == .fill ? "埋める" : "収める" }
    var icon: String { self == .fill ? "rectangle.fill" : "rectangle.inset.filled" }
}

struct ImageFrame: Codable, Identifiable, Equatable {
    var id = UUID()
    var rect: CGRect
    /// 中心まわりの回転（度・反時計回り）
    var rotation: CGFloat = 0
    var locked = false
    var hidden = false
    var name: String?
    var assetID: UUID?
    var fitMode: FitMode = .fill
    /// fit 結果に対する追加倍率（1.0 = ぴったり）
    var contentScale: CGFloat = 1.0
    /// 枠内での写真のずらし量（pt）
    var contentOffset: CGPoint = .zero
    var cornerRadius: CGFloat = 0
    /// 枠線
    var strokeWidth: CGFloat = 0
    var strokeColor: RGBA = .ink

    init(rect: CGRect) { self.rect = rect }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = c.value(.id, UUID())
        rect          = c.value(.rect, .zero)
        rotation      = c.value(.rotation, 0)
        locked        = c.value(.locked, false)
        hidden        = c.value(.hidden, false)
        name          = c.value(.name, String?.none)
        assetID       = c.value(.assetID, UUID?.none)
        fitMode       = c.value(.fitMode, .fill)
        contentScale  = c.value(.contentScale, 1)
        contentOffset = c.value(.contentOffset, .zero)
        cornerRadius  = c.value(.cornerRadius, 0)
        strokeWidth   = c.value(.strokeWidth, 0)
        strokeColor   = c.value(.strokeColor, .ink)
    }
}

/// テキストの下に敷く地。写真の上に載せる見出しやキャプションに使う。
enum TextPlate: String, Codable, CaseIterable, Identifiable {
    case none, block, ribbon, underline

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "なし"; case .block: "べた帯"; case .ribbon: "リボン"; case .underline: "下線"
        }
    }
    var icon: String {
        switch self {
        case .none: "textformat"; case .block: "rectangle.fill"
        case .ribbon: "bookmark.fill"; case .underline: "underline"
        }
    }
}

enum TextAlign: String, Codable, CaseIterable {
    case left, center, right, justified
    var label: String {
        switch self {
        case .left: "左"; case .center: "中央"; case .right: "右"; case .justified: "両端"
        }
    }
    var icon: String {
        switch self {
        case .left: "text.alignleft"; case .center: "text.aligncenter"
        case .right: "text.alignright"; case .justified: "text.justify"
        }
    }
}

struct TextFrame: Codable, Identifiable, Equatable {
    var id = UUID()
    var rect: CGRect
    var rotation: CGFloat = 0
    var locked = false
    var hidden = false
    var name: String?
    var text: String = "テキスト"
    var fontName: String = "HiraginoSans-W3"
    var fontSize: CGFloat = 10
    var lineHeightScale: CGFloat = 1.75
    var tracking: CGFloat = 0
    var alignment: TextAlign = .left
    var vertical: Bool = false
    var color: RGBA = .ink

    /// 文字の下に敷く地
    var plate: TextPlate = .none
    var plateColor: RGBA?
    /// 地を文字の周りにどれだけ広げるか（pt）
    var platePadding: CGFloat = 0

    /// 差し込みの元になる写真。テンプレートと組で使う。
    var linkedAssetID: UUID?
    /// `{plate}` のような記号を含む差し込み文。nil なら `text` をそのまま出す。
    var template: String?

    var isDynamic: Bool { template?.isEmpty == false }

    init(rect: CGRect) { self.rect = rect }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = c.value(.id, UUID())
        rect            = c.value(.rect, .zero)
        rotation        = c.value(.rotation, 0)
        locked          = c.value(.locked, false)
        hidden          = c.value(.hidden, false)
        name            = c.value(.name, String?.none)
        text            = c.value(.text, "")
        fontName        = c.value(.fontName, "HiraginoSans-W3")
        fontSize        = c.value(.fontSize, 10)
        lineHeightScale = c.value(.lineHeightScale, 1.75)
        tracking        = c.value(.tracking, 0)
        alignment       = c.value(.alignment, .left)
        vertical        = c.value(.vertical, false)
        color           = c.value(.color, .ink)
        linkedAssetID   = c.value(.linkedAssetID, UUID?.none)
        template        = c.value(.template, String?.none)
        plate           = c.value(.plate, .none)
        plateColor      = c.value(.plateColor, RGBA?.none)
        platePadding    = c.value(.platePadding, 0)
    }
}

/// 罫線・囲み・地色帯・図形。写真集では見出しの下線やサイドバーの帯として多用する。
enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    case rectangle, ellipse, line, diamond, triangle, ribbon

    var id: String { rawValue }
    var label: String {
        switch self {
        case .rectangle: "四角"; case .ellipse: "楕円"; case .line: "罫線"
        case .diamond: "菱形"; case .triangle: "三角"; case .ribbon: "リボン"
        }
    }
    var icon: String {
        switch self {
        case .rectangle: "rectangle"; case .ellipse: "circle"; case .line: "minus"
        case .diamond: "diamond"; case .triangle: "triangle"; case .ribbon: "bookmark.fill"
        }
    }
}

struct ShapeFrame: Codable, Identifiable, Equatable {
    var id = UUID()
    var rect: CGRect
    var rotation: CGFloat = 0
    var locked = false
    var hidden = false
    var name: String?

    var kind: ShapeKind = .rectangle
    /// nil で塗りなし
    var fill: RGBA? = .ink
    var stroke: RGBA?
    var strokeWidth: CGFloat = 0
    var cornerRadius: CGFloat = 0
    var opacity: CGFloat = 1
    /// 罫線を縦に引く（既定は枠の長い方向）
    var lineVertical: Bool?

    init(rect: CGRect, kind: ShapeKind = .rectangle) {
        self.rect = rect
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = c.value(.id, UUID())
        rect         = c.value(.rect, .zero)
        rotation     = c.value(.rotation, 0)
        locked       = c.value(.locked, false)
        hidden       = c.value(.hidden, false)
        name         = c.value(.name, String?.none)
        kind         = c.value(.kind, .rectangle)
        fill         = c.value(.fill, RGBA?.some(.ink))
        stroke       = c.value(.stroke, RGBA?.none)
        strokeWidth  = c.value(.strokeWidth, 0)
        cornerRadius = c.value(.cornerRadius, 0)
        opacity      = c.value(.opacity, 1)
        lineVertical = c.value(.lineVertical, Bool?.none)
    }

    /// 罫線を縦に引くか（未指定なら枠の形で決める）
    var isVerticalLine: Bool { lineVertical ?? (rect.height > rect.width) }
}

enum Element: Codable, Identifiable, Equatable {
    case image(ImageFrame)
    case text(TextFrame)
    case shape(ShapeFrame)

    var id: UUID {
        switch self {
        case .image(let f): f.id
        case .text(let f): f.id
        case .shape(let f): f.id
        }
    }

    var rect: CGRect {
        get {
            switch self {
            case .image(let f): f.rect
            case .text(let f): f.rect
            case .shape(let f): f.rect
            }
        }
        set {
            switch self {
            case .image(var f): f.rect = newValue; self = .image(f)
            case .text(var f): f.rect = newValue; self = .text(f)
            case .shape(var f): f.rect = newValue; self = .shape(f)
            }
        }
    }

    var rotation: CGFloat {
        get {
            switch self {
            case .image(let f): f.rotation
            case .text(let f): f.rotation
            case .shape(let f): f.rotation
            }
        }
        set {
            switch self {
            case .image(var f): f.rotation = newValue; self = .image(f)
            case .text(var f): f.rotation = newValue; self = .text(f)
            case .shape(var f): f.rotation = newValue; self = .shape(f)
            }
        }
    }

    var locked: Bool {
        get {
            switch self {
            case .image(let f): f.locked
            case .text(let f): f.locked
            case .shape(let f): f.locked
            }
        }
        set {
            switch self {
            case .image(var f): f.locked = newValue; self = .image(f)
            case .text(var f): f.locked = newValue; self = .text(f)
            case .shape(var f): f.locked = newValue; self = .shape(f)
            }
        }
    }

    var hidden: Bool {
        get {
            switch self {
            case .image(let f): f.hidden
            case .text(let f): f.hidden
            case .shape(let f): f.hidden
            }
        }
        set {
            switch self {
            case .image(var f): f.hidden = newValue; self = .image(f)
            case .text(var f): f.hidden = newValue; self = .text(f)
            case .shape(var f): f.hidden = newValue; self = .shape(f)
            }
        }
    }

    var customName: String? {
        get {
            switch self {
            case .image(let f): f.name
            case .text(let f): f.name
            case .shape(let f): f.name
            }
        }
        set {
            switch self {
            case .image(var f): f.name = newValue; self = .image(f)
            case .text(var f): f.name = newValue; self = .text(f)
            case .shape(var f): f.name = newValue; self = .shape(f)
            }
        }
    }

    /// 回転を反映した実際の当たり判定
    func contains(_ point: CGPoint) -> Bool {
        localPoint(point).map(rect.contains) ?? false
    }

    /// ビュー座標の点を、この要素の回転を打ち消したローカル座標へ
    func localPoint(_ point: CGPoint) -> CGPoint? {
        guard rotation != 0 else { return point }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let a = -rotation * .pi / 180
        let dx = point.x - c.x, dy = point.y - c.y
        return CGPoint(x: c.x + dx * cos(a) - dy * sin(a),
                       y: c.y + dx * sin(a) + dy * cos(a))
    }

    /// 中心まわりに回転させる変換
    var transform: CGAffineTransform {
        guard rotation != 0 else { return .identity }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: rotation * .pi / 180)
            .translatedBy(x: -c.x, y: -c.y)
    }

    /// 回転後に外接する矩形
    var boundingRect: CGRect {
        rotation == 0 ? rect : rect.applying(transform)
    }

    var imageFrame: ImageFrame? { if case .image(let f) = self { f } else { nil } }
    var textFrame: TextFrame? { if case .text(let f) = self { f } else { nil } }
    var shapeFrame: ShapeFrame? { if case .shape(let f) = self { f } else { nil } }

    var typeLabel: String {
        switch self {
        case .image: "写真"
        case .text: "テキスト"
        case .shape(let f): f.kind.label
        }
    }
    var icon: String {
        switch self {
        case .image: "photo"
        case .text: "textformat"
        case .shape(let f): f.kind.icon
        }
    }
}

/// 1枚の編集単位。ZINEでは見開き、組写真では1ボード。
struct Artboard: Codable, Identifiable, Equatable {
    var id = UUID()
    var elements: [Element] = []
    var role: BoardRole = .content
    var seriesID: UUID?
    /// 中扉などに使う見出し
    var title: String = ""
    /// 表紙など、共通要素を出したくないページ
    var hidesMaster = false

    var imageFrames: [ImageFrame] { elements.compactMap(\.imageFrame) }

    init(role: BoardRole = .content) { self.role = role }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = c.value(.id, UUID())
        elements = c.value(.elements, [])
        role     = c.value(.role, .content)
        seriesID = c.value(.seriesID, UUID?.none)
        title    = c.value(.title, "")
        hidesMaster = c.value(.hidesMaster, false)
    }
}

// MARK: - 保存形式

struct ZineFile: Codable {
    /// 保存形式のバージョン。読み込みは常に前方互換で、足りないキーは初期値に落ちる。
    static let currentVersion = 3

    var version: Int = ZineFile.currentVersion
    var settings: DocSettings
    var meta = DocumentMeta()
    var series: [Series] = []
    var assets: [PhotoAsset] = []
    var boards: [Artboard]

    enum CodingKeys: String, CodingKey {
        case version, settings, meta, series, assets, boards
        case spreads   // v1 では見開きを spreads と呼んでいた
    }

    init(settings: DocSettings, meta: DocumentMeta = DocumentMeta(), series: [Series] = [],
         assets: [PhotoAsset], boards: [Artboard]) {
        self.settings = settings
        self.meta = meta
        self.series = series
        self.assets = assets
        self.boards = boards
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version  = c.value(.version, 1)
        settings = c.value(.settings, DocSettings())
        meta     = c.value(.meta, DocumentMeta())
        series   = c.value(.series, [])
        assets   = c.value(.assets, [])
        let boardsValue: [Artboard]? = c.value(.boards, [Artboard]?.none)
        boards   = boardsValue ?? c.value(.spreads, [Artboard()])
        if boards.isEmpty { boards = [Artboard()] }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ZineFile.currentVersion, forKey: .version)
        try c.encode(settings, forKey: .settings)
        try c.encode(meta, forKey: .meta)
        try c.encode(series, forKey: .series)
        try c.encode(assets, forKey: .assets)
        try c.encode(boards, forKey: .boards)
    }
}
