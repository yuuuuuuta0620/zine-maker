import CoreGraphics
import Foundation

/// 黒地に写真を浮かせる写真集の型。
/// 罫線・縦組みの大見出し・撮影データ2行・ノンブルといった、
/// 実際の写真集で繰り返し出てくる組み方をそのまま雛形にしてある。
enum BookLayouts {

    /// 判型に対する基準文字サイズ。ZINE は pt、ボードは px なので基準が違う。
    private static func unit(_ s: DocSettings) -> CGFloat {
        s.kind == .zine ? s.trimBox.height / 210 : s.trimBox.height / 600
    }

    private static func ink(_ s: DocSettings) -> RGBA { s.background.contrastingInk }

    private static func text(_ rect: CGRect, _ body: String, size: CGFloat, s: DocSettings,
                             font: String = "HiraMinProN-W3", align: TextAlign = .left,
                             vertical: Bool = false, leading: CGFloat = 1.6,
                             tracking: CGFloat = 0, template: Bool = false,
                             scene: CanvasRenderer.Scene = .init()) -> Element {
        var f = TextFrame(rect: rect)
        if template { f.template = body }
        f.text = body
        f.fontName = font
        f.fontSize = size * unit(s)
        f.alignment = align
        f.vertical = vertical
        f.lineHeightScale = leading
        f.tracking = tracking * unit(s)
        f.color = ink(s)
        // 枠に入らない大きさだと Core Text は1行も描かないので、入る大きさまで詰める。
        // 差し込み文は実データを入れないと長さが分からないので scene を渡す。
        f.fontSize = CanvasRenderer.fittedFontSize(for: f, scene: scene)
        return .text(f)
    }

    private static func rule(_ rect: CGRect, s: DocSettings, weight: CGFloat = 0.4,
                             vertical: Bool? = nil) -> Element {
        var line = ShapeFrame(rect: rect, kind: .line)
        line.lineVertical = vertical
        line.fill = nil
        line.stroke = ink(s)
        line.strokeWidth = weight * unit(s)
        return .shape(line)
    }

    private static func band(_ rect: CGRect, s: DocSettings, color: RGBA? = nil, opacity: CGFloat = 1) -> Element {
        var box = ShapeFrame(rect: rect, kind: .rectangle)
        box.fill = color ?? s.background
        box.opacity = opacity
        return .shape(box)
    }

    private static func photo(_ rect: CGRect, _ assetID: UUID?, fit: FitMode = .fit) -> Element {
        var f = ImageFrame(rect: rect)
        f.assetID = assetID
        f.fitMode = fit
        return .image(f)
    }

    /// 撮影データ2行のキャプション
    private static func plateCaption(_ rect: CGRect, assetID: UUID?, s: DocSettings,
                                     align: TextAlign = .center,
                                     scene: CanvasRenderer.Scene = .init()) -> Element {
        var f = TextFrame(rect: rect)
        f.linkedAssetID = assetID
        f.template = "Day : {date.dot} / Location : {location}\nGear : {camera} / Lens : {lens} / Setting : {aperture} / {shutter} / {iso}"
        f.text = f.template!
        f.fontName = "HiraMinProN-W3"
        f.fontSize = 3.4 * unit(s)
        f.alignment = align
        f.lineHeightScale = 1.8
        f.color = ink(s)
        f.fontSize = CanvasRenderer.fittedFontSize(for: f, scene: scene)
        return .text(f)
    }

    // MARK: - 型

    struct Style: Identifiable, Hashable {
        var id: String { key }
        let key: String
        let name: String
        let detail: String
        let photoCount: Int
    }

    static let styles: [Style] = [
        .init(key: "plate",    name: "1枚＋撮影データ", detail: "黒地の中央に写真、下に撮影データ2行", photoCount: 1),
        .init(key: "sidebar",  name: "縦組み見出し＋写真", detail: "片側に縦組みの大見出し、残りに写真", photoCount: 1),
        .init(key: "stacked",  name: "縦2枚", detail: "上下に2枚とそれぞれの撮影データ", photoCount: 2),
        .init(key: "duo",      name: "見出し＋横2枚", detail: "上に見出しと罫線、下に2枚並べる", photoCount: 2),
        .init(key: "label",    name: "1枚＋地名", detail: "写真の角に小さな地名ラベル", photoCount: 1),
        .init(key: "chapter",  name: "章扉", detail: "第N章・大見出し・ページ範囲・項目一覧", photoCount: 0),
        .init(key: "afterword", name: "あとがき", detail: "中央に本文だけ", photoCount: 0),
    ]

    static func make(_ key: String, settings s: DocSettings, photos: [UUID] = [],
                     assets: [UUID: PhotoAsset] = [:],
                     title: String = "", subtitle: String = "") -> Artboard {
        var queue = photos
        func next() -> UUID? { queue.isEmpty ? nil : queue.removeFirst() }
        let scene = CanvasRenderer.Scene(assets: assets)

        switch key {
        case "sidebar":  return sidebar(s, next(), title: title, subtitle: subtitle)
        case "stacked":  return stacked(s, next(), next(), scene: scene)
        case "duo":      return duo(s, next(), next(), title: title, subtitle: subtitle, scene: scene)
        case "label":    return labelled(s, next(), title: title)
        case "chapter":  return chapter(s, title: title, subtitle: subtitle)
        case "afterword": return afterword(s, title: title)
        default:         return plate(s, next(), scene: scene)
        }
    }

    // 1枚＋撮影データ
    static func plate(_ s: DocSettings, _ assetID: UUID?, scene: CanvasRenderer.Scene = .init()) -> Artboard {
        var b = Artboard(role: .content)
        let box = s.contentBox
        let capH = box.height * 0.12
        b.elements.append(photo(CGRect(x: box.minX + box.width * 0.07, y: box.minY + capH,
                                       width: box.width * 0.86, height: box.height - capH), assetID))
        b.elements.append(plateCaption(CGRect(x: box.minX, y: box.minY, width: box.width, height: capH * 0.8),
                                       assetID: assetID, s: s, scene: scene))
        return b
    }

    // 縦組み見出し＋写真
    static func sidebar(_ s: DocSettings, _ assetID: UUID?, title: String, subtitle: String) -> Artboard {
        var b = Artboard(role: .content)
        let trim = s.trimBox
        let barW = trim.width * 0.23
        // 写真は見出し以外を占める
        b.elements.append(photo(CGRect(x: trim.minX + barW, y: trim.minY,
                                       width: trim.width - barW, height: trim.height), assetID, fit: .fill))
        // 見出し側の地色帯
        b.elements.append(band(CGRect(x: trim.minX, y: trim.minY, width: barW, height: trim.height), s: s))
        // 縦の区切り罫
        b.elements.append(rule(CGRect(x: trim.minX + barW - unit(s) * 2, y: trim.minY + trim.height * 0.05,
                                      width: 1, height: trim.height * 0.9), s: s, weight: 0.5, vertical: true))
        // 大見出し（縦組み）
        // 縦組みは「枠の幅」が行方向。1行ぶんの幅がないと1文字も描かれない
        b.elements.append(text(CGRect(x: trim.minX + barW * 0.26, y: trim.minY + trim.height * 0.16,
                                      width: barW * 0.50, height: trim.height * 0.66),
                               title.isEmpty ? "見出し" : title,
                               size: 22, s: s, font: "HiraMinProN-W6", vertical: true, leading: 1.3))
        // 添える欧文（縦組み）
        b.elements.append(text(CGRect(x: trim.minX + barW * 0.08, y: trim.minY + trim.height * 0.22,
                                      width: barW * 0.16, height: trim.height * 0.5),
                               subtitle.isEmpty ? "Subtitle" : subtitle,
                               size: 6, s: s, vertical: true, tracking: 2))
        return b
    }

    // 縦2枚
    static func stacked(_ s: DocSettings, _ a: UUID?, _ b2: UUID?, scene: CanvasRenderer.Scene = .init()) -> Artboard {
        var b = Artboard(role: .content)
        let box = s.contentBox
        let half = box.height / 2
        let capH = half * 0.16
        for (i, id) in [a, b2].enumerated() {
            let y = box.minY + half * CGFloat(1 - i)
            b.elements.append(photo(CGRect(x: box.minX + box.width * 0.25, y: y + capH,
                                           width: box.width * 0.5, height: half - capH * 1.3), id))
            // キャプションは折り返しやすいので、幅いっぱいに取る
            b.elements.append(plateCaption(CGRect(x: box.minX, y: y + capH * 0.08,
                                                  width: box.width, height: capH * 0.88),
                                           assetID: id, s: s, scene: scene))
        }
        return b
    }

    // 見出し＋横2枚
    static func duo(_ s: DocSettings, _ a: UUID?, _ b2: UUID?, title: String, subtitle: String,
                    scene: CanvasRenderer.Scene = .init()) -> Artboard {
        var b = Artboard(role: .content)
        let box = s.contentBox
        let headH = box.height * 0.13
        b.elements.append(text(CGRect(x: box.minX, y: box.maxY - headH * 0.8, width: box.width * 0.5, height: headH * 0.7),
                               title.isEmpty ? "見出し" : title, size: 13, s: s, font: "HiraMinProN-W6"))
        b.elements.append(text(CGRect(x: box.minX + box.width * 0.5, y: box.maxY - headH * 0.72, width: box.width * 0.5, height: headH * 0.5),
                               subtitle, size: 5, s: s))
        b.elements.append(rule(CGRect(x: box.minX, y: box.maxY - headH, width: box.width, height: 1), s: s))

        let gap = box.width * 0.03
        let w = (box.width - gap) / 2
        let photoH = box.height - headH - box.height * 0.14
        for (i, id) in [a, b2].enumerated() {
            let x = box.minX + (w + gap) * CGFloat(i)
            b.elements.append(photo(CGRect(x: x, y: box.minY + box.height * 0.13, width: w, height: photoH), id))
            b.elements.append(plateCaption(CGRect(x: x, y: box.minY, width: w, height: box.height * 0.11),
                                           assetID: id, s: s, scene: scene))
        }
        return b
    }

    // 1枚＋地名ラベル
    static func labelled(_ s: DocSettings, _ assetID: UUID?, title: String) -> Artboard {
        var b = Artboard(role: .content)
        let box = s.contentBox
        b.elements.append(photo(CGRect(x: box.minX, y: box.minY + box.height * 0.1,
                                       width: box.width, height: box.height * 0.9), assetID, fit: .fill))
        b.elements.append(text(CGRect(x: box.minX, y: box.minY + box.height * 0.015,
                                      width: box.width * 0.6, height: box.height * 0.07),
                               title.isEmpty ? "地名" : title, size: 7, s: s, tracking: 1))
        return b
    }

    // 章扉
    static func chapter(_ s: DocSettings, title: String, subtitle: String) -> Artboard {
        var b = Artboard(role: .divider)
        b.title = title
        let box = s.contentBox
        let top = box.maxY
        b.elements.append(text(CGRect(x: box.minX, y: top - box.height * 0.08, width: box.width, height: box.height * 0.06),
                               subtitle.isEmpty ? "第1章" : subtitle, size: 6, s: s, align: .center))
        b.elements.append(text(CGRect(x: box.minX, y: top - box.height * 0.16, width: box.width, height: box.height * 0.06),
                               "{series.subtitle}", size: 7, s: s, align: .center, template: true))
        b.elements.append(text(CGRect(x: box.minX, y: top - box.height * 0.36, width: box.width, height: box.height * 0.18),
                               title.isEmpty ? "{series}" : title, size: 24, s: s,
                               font: "HiraMinProN-W6", align: .center, leading: 1.25, tracking: 3,
                               template: title.isEmpty))
        b.elements.append(rule(CGRect(x: box.minX + box.width * 0.2, y: top - box.height * 0.40,
                                      width: box.width * 0.6, height: 1), s: s, weight: 0.4))
        b.elements.append(text(CGRect(x: box.minX + box.width * 0.22, y: box.minY,
                                      width: box.width * 0.6, height: box.height * 0.6),
                               "・項目\n　　小見出し　P0-P0\n\n・項目\n　　小見出し　P0-P0",
                               size: 8, s: s, leading: 2.4))
        return b
    }

    // あとがき
    static func afterword(_ s: DocSettings, title: String) -> Artboard {
        var b = Artboard(role: .statement)
        let box = s.contentBox
        b.elements.append(text(CGRect(x: box.minX, y: box.maxY - box.height * 0.12, width: box.width, height: box.height * 0.08),
                               title.isEmpty ? "最後に" : title, size: 9, s: s, align: .center))
        b.elements.append(text(CGRect(x: box.minX + box.width * 0.15, y: box.minY + box.height * 0.15,
                                      width: box.width * 0.7, height: box.height * 0.6),
                               "ここに本文を入れます。", size: 5.5, s: s, align: .center, leading: 2.6))
        b.elements.append(text(CGRect(x: box.minX, y: box.minY + box.height * 0.06, width: box.width, height: box.height * 0.06),
                               "{doc.author}", size: 5.5, s: s, align: .center, template: true))
        return b
    }

    // MARK: - 全ページ共通の要素

    /// ノンブルを1桁ずつ縦に積む（写真集でよく見る形）
    static func pageNumberMaster(_ s: DocSettings, corner: Corner = .bottomLeft, stacked: Bool = true) -> [Element] {
        let trim = s.trimBox
        let m = min(trim.width, trim.height) * 0.035
        let w = m * 1.6, h = m * 3.4
        let x = corner.isLeft ? trim.minX + m : trim.maxX - m - w
        let y = corner.isBottom ? trim.minY + m : trim.maxY - m - h

        var f = TextFrame(rect: CGRect(x: x, y: y, width: w, height: h))
        f.template = stacked ? "{page.digits}" : "{page.pad}"
        f.text = f.template!
        f.fontName = "HiraginoSans-W6"
        f.fontSize = m * 0.8
        f.alignment = corner.isLeft ? .left : .right
        f.lineHeightScale = 1.35
        var color = s.background.contrastingInk
        color.a = 0.55
        f.color = color
        return [.text(f)]
    }

    enum Corner: String, CaseIterable, Identifiable {
        case bottomLeft, bottomRight, topLeft, topRight
        var id: String { rawValue }
        var label: String {
            switch self {
            case .bottomLeft: "左下"; case .bottomRight: "右下"
            case .topLeft: "左上"; case .topRight: "右上"
            }
        }
        var isLeft: Bool { self == .bottomLeft || self == .topLeft }
        var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
    }
}
