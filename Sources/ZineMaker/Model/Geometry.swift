import CoreGraphics
import Foundation

/// 内部座標はすべて pt (1/72 inch)、y-up（Core Graphics / PDF と同じ向き）。
/// 原点は塗り足しを含むメディアボックスの左下。
/// ボードモードでは 1pt = 1px として扱い、書き出し時に目標ピクセル数へスケールする。
enum Pt {
    static func fromMM(_ mm: Double) -> CGFloat { CGFloat(mm) * 72.0 / 25.4 }
    static func toMM(_ pt: CGFloat) -> Double { Double(pt) * 25.4 / 72.0 }
}

struct RGBA: Codable, Equatable, Hashable {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat

    static let black = RGBA(r: 0, g: 0, b: 0, a: 1)
    static let white = RGBA(r: 1, g: 1, b: 1, a: 1)
    static let paper = RGBA(r: 0.97, g: 0.96, b: 0.94, a: 1)
    static let ink   = RGBA(r: 0.11, g: 0.11, b: 0.12, a: 1)

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    /// 背景に対して読みやすい前景色
    var contrastingInk: RGBA {
        (0.299 * r + 0.587 * g + 0.114 * b) > 0.55 ? .ink : .white
    }
}

// MARK: - アスペクト比

struct AspectRatio: Codable, Hashable, Identifiable {
    var w: Double
    var h: Double

    var id: String { "\(w):\(h)" }
    var value: Double { h == 0 ? 1 : w / h }
    var isPortrait: Bool { value < 1 }

    /// 長辺を `longEdge` px としたときのピクセル寸法
    func size(longEdge: Double) -> CGSize {
        value >= 1
            ? CGSize(width: longEdge, height: (longEdge / value).rounded())
            : CGSize(width: (longEdge * value).rounded(), height: longEdge)
    }

    var label: String {
        let wi = w.rounded(), hi = h.rounded()
        if abs(w - wi) < 0.01 && abs(h - hi) < 0.01 { return "\(Int(wi)):\(Int(hi))" }
        return String(format: "%.2f:%.2f", w, h)
    }

    static let square   = AspectRatio(w: 1, h: 1)
    static let portrait45 = AspectRatio(w: 4, h: 5)
    static let portrait23 = AspectRatio(w: 2, h: 3)
    static let portrait916 = AspectRatio(w: 9, h: 16)
    static let landscape32 = AspectRatio(w: 3, h: 2)
    static let landscape169 = AspectRatio(w: 16, h: 9)

    struct Preset: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let note: String
        let ratio: AspectRatio
    }

    static let presets: [Preset] = [
        .init(name: "1:1",    note: "正方形",            ratio: .init(w: 1, h: 1)),
        .init(name: "4:5",    note: "Instagram 縦",      ratio: .init(w: 4, h: 5)),
        .init(name: "3:4",    note: "やや縦",            ratio: .init(w: 3, h: 4)),
        .init(name: "2:3",    note: "35mm 縦",           ratio: .init(w: 2, h: 3)),
        .init(name: "9:16",   note: "ストーリーズ",       ratio: .init(w: 9, h: 16)),
        .init(name: "3:2",    note: "35mm 横",           ratio: .init(w: 3, h: 2)),
        .init(name: "4:3",    note: "やや横",            ratio: .init(w: 4, h: 3)),
        .init(name: "16:9",   note: "ワイド",            ratio: .init(w: 16, h: 9)),
        .init(name: "1.91:1", note: "X / OGP",          ratio: .init(w: 1.91, h: 1)),
    ]
}

extension CGRect {
    var normalizedRect: CGRect { standardized }

    /// 正規化矩形 (0...1, y-up) をこの矩形の中に展開する
    func unitRect(_ unit: CGRect) -> CGRect {
        CGRect(x: minX + unit.minX * width, y: minY + unit.minY * height,
               width: unit.width * width, height: unit.height * height)
    }

    func inset(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) -> CGRect {
        CGRect(x: minX + left, y: minY + bottom,
               width: max(width - left - right, 0), height: max(height - top - bottom, 0))
    }
}

extension CGSize {
    var aspect: CGFloat { height == 0 ? 1 : width / height }
}
