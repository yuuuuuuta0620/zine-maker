import CoreGraphics
import Foundation

/// 組写真のレイアウト。スロットは正規化座標 (0...1, y-up) で持ち、
/// 適用時に内容領域へ展開して間隔を差し引く。
struct LayoutTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let slots: [CGRect]
    /// 紙の端まで使い、写真同士の隙間も取らない。SNS の組写真でよく使う帯組み。
    var bleed = false

    var count: Int { slots.count }

    /// 指定の領域に展開する。`gutter` は隣り合う写真の間に入る合計の隙間。
    func frames(in box: CGRect, gutter: CGFloat) -> [CGRect] {
        slots.map { slot in
            var r = box.unitRect(slot)
            // 外周に接している辺は詰めず、内側の辺だけ半分ずつ削る
            let left   = slot.minX > 0.001 ? gutter / 2 : 0
            let right  = slot.maxX < 0.999 ? gutter / 2 : 0
            let bottom = slot.minY > 0.001 ? gutter / 2 : 0
            let top    = slot.maxY < 0.999 ? gutter / 2 : 0
            r = r.inset(top: top, left: left, bottom: bottom, right: right)
            return r
        }
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

    /// 端まで使う帯組み。上から下へ並べる。
    private static func bands(_ heights: [Double], id: String, name: String) -> LayoutTemplate {
        var slots: [CGRect] = []
        var top = 1.0
        for h in heights {
            slots.append(rect(0, top - h, 1, h))
            top -= h
        }
        return LayoutTemplate(id: id, name: name, slots: slots, bleed: true)
    }

    /// 端まで使う縦割り。左から右へ並べる。
    private static func columns(_ widths: [Double], id: String, name: String) -> LayoutTemplate {
        var slots: [CGRect] = []
        var left = 0.0
        for w in widths {
            slots.append(rect(left, 0, w, 1))
            left += w
        }
        return LayoutTemplate(id: id, name: name, slots: slots, bleed: true)
    }

    /// 端まで使う型。組写真はこちらが主役。
    static let bleedTemplates: [LayoutTemplate] = [
        LayoutTemplate(id: "bleed-1", name: "全面1枚", slots: [rect(0, 0, 1, 1)], bleed: true),
        bands([0.5, 0.5], id: "bleed-v2", name: "全面 上下2段"),
        bands([0.62, 0.38], id: "bleed-v2-top", name: "全面 上大・下小"),
        bands([0.38, 0.62], id: "bleed-v2-bottom", name: "全面 上小・下大"),
        bands([1.0/3, 1.0/3, 1.0/3], id: "bleed-v3", name: "全面 3段"),
        bands([0.3, 0.4, 0.3], id: "bleed-v3-mid", name: "全面 3段・中央大"),
        bands([0.25, 0.25, 0.25, 0.25], id: "bleed-v4", name: "全面 4段"),
        columns([0.5, 0.5], id: "bleed-h2", name: "全面 左右2分割"),
        columns([1.0/3, 1.0/3, 1.0/3], id: "bleed-h3", name: "全面 横3列"),
        LayoutTemplate(id: "bleed-1-2", name: "全面 上1・下2", slots: [
            rect(0, 0.5, 1, 0.5), rect(0, 0, 0.5, 0.5), rect(0.5, 0, 0.5, 0.5),
        ], bleed: true),
        LayoutTemplate(id: "bleed-2-1", name: "全面 上2・下1", slots: [
            rect(0, 0.5, 0.5, 0.5), rect(0.5, 0.5, 0.5, 0.5), rect(0, 0, 1, 0.5),
        ], bleed: true),
        LayoutTemplate(id: "bleed-g2x2", name: "全面 2×2", slots: grid(cols: 2, rows: 2, id: "", name: "").slots,
                       bleed: true),
    ]

    static let all: [LayoutTemplate] = bleedTemplates + [
        LayoutTemplate(id: "single", name: "1枚", slots: [rect(0, 0, 1, 1)]),

        LayoutTemplate(id: "v2", name: "上下2分割", slots: [
            rect(0, 0.5, 1, 0.5), rect(0, 0, 1, 0.5),
        ]),
        LayoutTemplate(id: "h2", name: "左右2分割", slots: [
            rect(0, 0, 0.5, 1), rect(0.5, 0, 0.5, 1),
        ]),

        LayoutTemplate(id: "v3", name: "縦3段", slots: [
            rect(0, 2.0/3, 1, 1.0/3), rect(0, 1.0/3, 1, 1.0/3), rect(0, 0, 1, 1.0/3),
        ]),
        LayoutTemplate(id: "h3", name: "横3列", slots: [
            rect(0, 0, 1.0/3, 1), rect(1.0/3, 0, 1.0/3, 1), rect(2.0/3, 0, 1.0/3, 1),
        ]),
        LayoutTemplate(id: "big-top-2", name: "大＋小2", slots: [
            rect(0, 0.42, 1, 0.58), rect(0, 0, 0.5, 0.42), rect(0.5, 0, 0.5, 0.42),
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

    /// 枚数に合うものを優先して並べ替える。
    /// `bleedFirst` のときは、同じくらい合う型なら端まで使うほうを先に出す。
    static func suggestions(for photoCount: Int, bleedFirst: Bool = false) -> [LayoutTemplate] {
        all.sorted { a, b in
            let da = abs(a.count - photoCount), db = abs(b.count - photoCount)
            if da != db { return da < db }
            if bleedFirst, a.bleed != b.bleed { return a.bleed }
            return a.count < b.count
        }
    }
}
