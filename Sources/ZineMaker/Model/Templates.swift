import CoreGraphics
import Foundation

/// 組写真のレイアウト。スロットは正規化座標 (0...1, y-up) で持ち、
/// 適用時に内容領域へ展開して間隔を差し引く。
struct LayoutTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let slots: [CGRect]

    var count: Int { slots.count }

    /// 指定の領域に展開する。`gutter` は隣り合う写真の間に入る隙間。
    ///
    /// 隙間を先に全体から差し引き、残りを比率どおりに分ける。
    /// 各枠から半分ずつ削るやり方だと、両側に隣がある真ん中の枠だけが小さくなる。
    func frames(in box: CGRect, gutter: CGFloat) -> [CGRect] {
        let xs = LayoutTemplate.cuts(slots.flatMap { [$0.minX, $0.maxX] })
        let ys = LayoutTemplate.cuts(slots.flatMap { [$0.minY, $0.maxY] })
        let usableW = box.width - gutter * CGFloat(xs.count)
        let usableH = box.height - gutter * CGFloat(ys.count)

        // 正規化した座標を実寸へ。切れ目の手前側（max）と向こう側（min）で隙間の数が1つ違う。
        func place(_ u: CGFloat, _ cuts: [CGFloat], usable: CGFloat, isMin: Bool) -> CGFloat {
            guard let i = cuts.firstIndex(where: { abs($0 - u) < 0.0005 }) else {
                // 端（0 か 1）。それより手前にある切れ目の数だけ隙間を足す。
                return u * usable + gutter * CGFloat(cuts.filter { $0 < u }.count)
            }
            return u * usable + gutter * CGFloat(isMin ? i + 1 : i)
        }
        return slots.map { slot in
            let x0 = place(slot.minX, xs, usable: usableW, isMin: true)
            let x1 = place(slot.maxX, xs, usable: usableW, isMin: false)
            let y0 = place(slot.minY, ys, usable: usableH, isMin: true)
            let y1 = place(slot.maxY, ys, usable: usableH, isMin: false)
            return CGRect(x: box.minX + x0, y: box.minY + y0, width: x1 - x0, height: y1 - y0)
        }
    }

    /// 内側の切れ目（0 と 1 を除く）を小さい順に、重複なしで
    private static func cuts(_ values: [CGFloat]) -> [CGFloat] {
        var out: [CGFloat] = []
        for v in values.sorted() where v > 0.0005 && v < 0.9995 {
            if let last = out.last, abs(last - v) < 0.0005 { continue }
            out.append(v)
        }
        return out
    }

    // MARK: - 組み立て補助

    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    /// cols × rows の等分グリッド（左上から右下の順に並べる）
    static func grid(cols: Int, rows: Int, id: String, name: String) -> LayoutTemplate {
        var slots: [CGRect] = []
        let w = 1.0 / Double(cols), h = 1.0 / Double(rows)
        for row in 0..<rows {
            for col in 0..<cols {
                slots.append(rect(Double(col) * w, 1.0 - Double(row + 1) * h, w, h))
            }
        }
        return LayoutTemplate(id: id, name: name, slots: slots)
    }

    // MARK: - 一覧

    /// 帯を上から下へ積む
    private static func bands(_ heights: [Double], id: String, name: String) -> LayoutTemplate {
        var slots: [CGRect] = []
        var top = 1.0
        for h in heights {
            slots.append(rect(0, top - h, 1, h))
            top -= h
        }
        return LayoutTemplate(id: id, name: name, slots: slots)
    }

    static let all: [LayoutTemplate] = [
        LayoutTemplate(id: "single", name: "1枚", slots: [rect(0, 0, 1, 1)]),

        LayoutTemplate(id: "v2", name: "上下2分割", slots: [
            rect(0, 0.5, 1, 0.5), rect(0, 0, 1, 0.5),
        ]),
        LayoutTemplate(id: "h2", name: "左右2分割", slots: [
            rect(0, 0, 0.5, 1), rect(0.5, 0, 0.5, 1),
        ]),
        bands([0.62, 0.38], id: "v2-top", name: "上大・下小"),
        bands([0.38, 0.62], id: "v2-bottom", name: "上小・下大"),

        LayoutTemplate(id: "v3", name: "縦3段", slots: [
            rect(0, 2.0/3, 1, 1.0/3), rect(0, 1.0/3, 1, 1.0/3), rect(0, 0, 1, 1.0/3),
        ]),
        bands([0.3, 0.4, 0.3], id: "v3-mid", name: "3段・中央大"),
        LayoutTemplate(id: "h3", name: "横3列", slots: [
            rect(0, 0, 1.0/3, 1), rect(1.0/3, 0, 1.0/3, 1), rect(2.0/3, 0, 1.0/3, 1),
        ]),
        LayoutTemplate(id: "big-top-2", name: "大＋小2", slots: [
            rect(0, 0.42, 1, 0.58), rect(0, 0, 0.5, 0.42), rect(0.5, 0, 0.5, 0.42),
        ]),
        LayoutTemplate(id: "1-2", name: "上1・下2", slots: [
            rect(0, 0.5, 1, 0.5), rect(0, 0, 0.5, 0.5), rect(0.5, 0, 0.5, 0.5),
        ]),
        LayoutTemplate(id: "2-1", name: "上2・下1", slots: [
            rect(0, 0.5, 0.5, 0.5), rect(0.5, 0.5, 0.5, 0.5), rect(0, 0, 1, 0.5),
        ]),
        LayoutTemplate(id: "big-left-2", name: "左大＋右2", slots: [
            rect(0, 0, 0.6, 1), rect(0.6, 0.5, 0.4, 0.5), rect(0.6, 0, 0.4, 0.5),
        ]),

        grid(cols: 2, rows: 2, id: "g2x2", name: "2×2"),
        LayoutTemplate(id: "big-top-3", name: "大＋小3", slots: [
            rect(0, 0.36, 1, 0.64),
            rect(0, 0, 1.0/3, 0.36), rect(1.0/3, 0, 1.0/3, 0.36), rect(2.0/3, 0, 1.0/3, 0.36),
        ]),
        LayoutTemplate(id: "v4", name: "縦4段", slots: (0..<4).map { rect(0, 1 - Double($0 + 1) * 0.25, 1, 0.25) }),

        LayoutTemplate(id: "g3x2", name: "3×2", slots: LayoutTemplate.grid(cols: 3, rows: 2, id: "", name: "").slots),
        LayoutTemplate(id: "g2x3", name: "2×3", slots: LayoutTemplate.grid(cols: 2, rows: 3, id: "", name: "").slots),
        LayoutTemplate(id: "big-left-4", name: "左大＋右4", slots: [
            rect(0, 0, 0.58, 1),
            rect(0.58, 0.5, 0.21, 0.5), rect(0.79, 0.5, 0.21, 0.5),
            rect(0.58, 0, 0.21, 0.5), rect(0.79, 0, 0.21, 0.5),
        ]),
        grid(cols: 3, rows: 3, id: "g3x3", name: "3×3"),
    ]

    /// 枚数に合うものを優先して並べ替える
    static func suggestions(for photoCount: Int) -> [LayoutTemplate] {
        all.sorted { a, b in
            let da = abs(a.count - photoCount), db = abs(b.count - photoCount)
            return da == db ? a.count < b.count : da < db
        }
    }
}

/// 型を当てるときの余白の取り方。型の形とは別に選べる。
struct LayoutSpacing: Equatable {
    /// 紙の外周に余白を取る。取らなければ紙の端まで（誌面なら塗り足しまで）写真が届く。
    var outerMargin = true
    /// 写真どうしの間に隙間を入れる
    var gaps = true

    static let edgeToEdge = LayoutSpacing(outerMargin: false, gaps: false)
}
