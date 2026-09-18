import CoreGraphics
import Foundation

/// 書き出す前の点検。
/// 46ページを目で追って確かめるのは現実的でないので、機械に見せられるところは見せる。
struct PreflightIssue: Identifiable {
    enum Severity: Int, Comparable {
        case warning, error
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
        var label: String { self == .error ? "要修正" : "確認" }
        var icon: String { self == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill" }
    }

    enum Kind: String {
        case missingPhoto      // 写真が見つからない
        case emptyFrame        // 空の写真枠
        case lowResolution     // 解像度が足りない
        case textOverflow      // 文字が枠に入りきらない
        case tinyText          // 文字が小さすぎる
        case shortBleed        // 裁ち落としが足りない
        case textOutsideTrim   // 文字が仕上がりの外にある
        case nearGutter        // ノドに近すぎる

        var title: String {
            switch self {
            case .missingPhoto: "写真が見つからない"
            case .emptyFrame: "空の写真枠"
            case .lowResolution: "解像度が足りない"
            case .textOverflow: "文字が枠に入りきらない"
            case .tinyText: "文字が小さすぎる"
            case .shortBleed: "裁ち落としが足りない"
            case .textOutsideTrim: "文字が仕上がりの外にある"
            case .nearGutter: "ノドに近すぎる"
            }
        }

        var advice: String {
            switch self {
            case .missingPhoto: "「見つからない写真を探す」で繋ぎ直してください。このままだと空白で刷られます。"
            case .emptyFrame: "写真を入れるか、枠を消してください。"
            case .lowResolution: "枠を小さくするか、大きい元データに差し替えてください。"
            case .textOverflow: "枠を広げるか、文字を減らすか、級数を下げてください。入りきらない分は刷られません。"
            case .tinyText: "紙で読める大きさではありません。6pt以上を目安に。"
            case .shortBleed: "紙の端に接する写真は、塗り足しの外周まで伸ばしてください。裁ちズレで白が出ます。"
            case .textOutsideTrim: "仕上がり線の内側へ入れてください。このままだと切り落とされます。"
            case .nearGutter: "見開きのノドは綴じで隠れます。文字や顔を寄せないでください。"
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var severity: Severity
    var boardIndex: Int
    var elementID: UUID?
    var detail: String
}

enum Preflight {

    struct Options {
        /// 印刷の目安。これを下回る写真を拾う
        var targetDPI: Double = 300
        /// これより小さい文字を拾う（pt）
        var minimumTextSize: CGFloat = 6
        /// ノドから何mm以内を危ないとみなすか
        var gutterMarginMM: Double = 6
        /// 画面で見るだけなら印刷向けの項目は外す
        var forPrint = true
    }

    static func run(_ context: DocumentContext, options: Options = .init()) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []
        let s = context.settings
        let assets = context.assetIndex
        let scenes = context.allScenes()
        let isZine = s.kind == .zine
        let print = options.forPrint && isZine

        for (index, board) in context.boards.enumerated() {
            let elements = board.hidesMaster ? board.elements : s.masterElements + board.elements

            for element in elements where !element.hidden {
                switch element {
                case .image(let f):
                    // 塗り足しは幾何の話なので、写真の有無に関わらず先に見る
                    if print, s.bleed > 0, f.assetID != nil {
                        issues.append(contentsOf: bleedIssues(f, settings: s, boardIndex: index,
                                                              name: f.assetID.flatMap { assets[$0]?.name } ?? "写真"))
                    }
                    guard let assetID = f.assetID else {
                        issues.append(.init(kind: .emptyFrame, severity: .warning, boardIndex: index,
                                            elementID: f.id, detail: "写真が入っていません"))
                        continue
                    }
                    // ドキュメントに実体が無い参照。取り込み前の .zine を開いたときなどに起きる。
                    guard let asset = assets[assetID] else {
                        issues.append(.init(kind: .missingPhoto, severity: .error, boardIndex: index,
                                            elementID: f.id, detail: "この枠が指す写真がドキュメントにありません"))
                        continue
                    }
                    guard FileManager.default.fileExists(atPath: asset.path) else {
                        issues.append(.init(kind: .missingPhoto, severity: .error, boardIndex: index,
                                            elementID: f.id, detail: asset.name))
                        continue
                    }
                    // 解像度
                    if print, let size = ImageStore.shared.pixelSize(of: asset.url) {
                        let target = CanvasRenderer.contentRect(for: f, imageSize: size)
                        if target.width > 0 {
                            let dpi = Double(size.width / (target.width / 72))
                            if dpi < options.targetDPI {
                                issues.append(.init(kind: .lowResolution, severity: dpi < options.targetDPI * 0.7 ? .error : .warning,
                                                    boardIndex: index, elementID: f.id,
                                                    detail: "\(asset.name) — \(Int(dpi)) dpi"))
                            }
                        }
                    }
                case .text(let f):
                    let scene = scenes[index]
                    if CanvasRenderer.textOverflows(f, scene: scene) {
                        issues.append(.init(kind: .textOverflow, severity: .error, boardIndex: index,
                                            elementID: f.id,
                                            detail: CanvasRenderer.resolvedText(for: f, scene: scene)
                                                .split(separator: "\n").first.map(String.init) ?? "テキスト"))
                    }
                    if print, f.fontSize < options.minimumTextSize,
                       !CanvasRenderer.resolvedText(for: f, scene: scene).isEmpty {
                        issues.append(.init(kind: .tinyText, severity: .warning, boardIndex: index,
                                            elementID: f.id,
                                            detail: String(format: "%.1f pt", f.fontSize)))
                    }
                    if print, !CanvasRenderer.resolvedText(for: f, scene: scene).isEmpty {
                        let r = Element.text(f).boundingRect
                        if !s.trimBox.insetBy(dx: -0.5, dy: -0.5).contains(r) {
                            issues.append(.init(kind: .textOutsideTrim, severity: .error, boardIndex: index,
                                                elementID: f.id, detail: "仕上がり線からはみ出しています"))
                        } else if let gutter = s.gutterX {
                            let margin = Pt.fromMM(options.gutterMarginMM)
                            if r.minX < gutter + margin, r.maxX > gutter - margin {
                                issues.append(.init(kind: .nearGutter, severity: .warning, boardIndex: index,
                                                    elementID: f.id, detail: "ノドをまたいでいます"))
                            }
                        }
                    }

                case .shape:
                    break
                }
            }
        }

        // 重い順・ページ順
        return issues.sorted {
            $0.severity != $1.severity ? $0.severity > $1.severity : $0.boardIndex < $1.boardIndex
        }
    }

    /// 紙の端に接しているのに塗り足しまで伸びていない辺を拾う。
    /// 裁ちズレで白い筋が出るので、入稿では致命的。
    private static func bleedIssues(_ f: ImageFrame, settings s: DocSettings,
                                    boardIndex: Int, name: String) -> [PreflightIssue] {
        let r = Element.image(f).boundingRect
        let trim = s.trimBox, media = s.mediaBox
        let tolerance = Pt.fromMM(0.4)
        var edges: [String] = []
        if r.minX <= trim.minX + tolerance, r.minX > media.minX + tolerance { edges.append("左") }
        if r.maxX >= trim.maxX - tolerance, r.maxX < media.maxX - tolerance { edges.append("右") }
        if r.minY <= trim.minY + tolerance, r.minY > media.minY + tolerance { edges.append("下") }
        if r.maxY >= trim.maxY - tolerance, r.maxY < media.maxY - tolerance { edges.append("上") }
        guard !edges.isEmpty else { return [] }
        return [.init(kind: .shortBleed, severity: .error, boardIndex: boardIndex, elementID: f.id,
                      detail: "\(name) — \(edges.joined(separator: "・"))が塗り足しに届いていません")]
    }

    /// 種類ごとの件数
    static func summary(_ issues: [PreflightIssue]) -> [(kind: PreflightIssue.Kind, count: Int, severity: PreflightIssue.Severity)] {
        var counts: [String: (PreflightIssue.Kind, Int, PreflightIssue.Severity)] = [:]
        for issue in issues {
            let key = issue.kind.rawValue
            let previous = counts[key]
            counts[key] = (issue.kind, (previous?.1 ?? 0) + 1, max(previous?.2 ?? .warning, issue.severity))
        }
        return counts.values
            .map { (kind: $0.0, count: $0.1, severity: $0.2) }
            .sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.count > $1.count }
    }
}
