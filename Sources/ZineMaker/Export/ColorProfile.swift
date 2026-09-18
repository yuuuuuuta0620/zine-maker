import CoreGraphics
import Foundation

/// 書き出し時の色の扱い。
/// 画面は Display P3 で見ていても、配る先に合わせて変換して出す。
enum ColorProfile: String, CaseIterable, Identifiable, Codable {
    case sRGB, displayP3, adobeRGB, proPhoto, gray, cmyk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .adobeRGB: "Adobe RGB"
        case .proPhoto: "ProPhoto RGB"
        case .gray: "グレースケール"
        case .cmyk: "CMYK"
        }
    }

    var note: String {
        switch self {
        case .sRGB: "web・SNS・どこでも安全。迷ったらこれ"
        case .displayP3: "広色域の画面向け。対応していない環境では色が転ぶ"
        case .adobeRGB: "印刷前提のRGB。画面で見ると浅く見える"
        case .proPhoto: "編集用の広い空間。配布には向かない"
        case .gray: "モノクロ"
        case .cmyk: "印刷所入稿向け。黒はK版だけに置き換える"
        }
    }

    var colorSpace: CGColorSpace? {
        switch self {
        case .sRGB:      CGColorSpace(name: CGColorSpace.sRGB)
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)
        case .adobeRGB:  CGColorSpace(name: CGColorSpace.adobeRGB1998)
        case .proPhoto:  CGColorSpace(name: CGColorSpace.rommrgb)
        case .gray:      CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        case .cmyk:      CGColorSpace(name: CGColorSpace.genericCMYK)
        }
    }

    var componentCount: Int {
        switch self {
        case .gray: 1
        case .cmyk: 4
        default: 3
        }
    }

    /// その形式で書き出せるか（PNG は CMYK を持てない、など）
    func isSupported(by format: ImageExporter.Format) -> Bool {
        switch self {
        case .cmyk: return format == .jpeg || format == .tiff
        case .gray: return format != .avif && format != .heic
        default:    return true
        }
    }

    /// ビットマップを作るときの中身の並べ方
    var bitmapInfo: UInt32 {
        switch self {
        case .gray: CGImageAlphaInfo.none.rawValue
        case .cmyk: CGImageAlphaInfo.none.rawValue
        default:    CGImageAlphaInfo.noneSkipLast.rawValue
        }
    }
}

// MARK: - 色の変換

enum ColorConvert {

    /// RGBA をその空間の CGColor にする。
    /// CMYK で無彩色のときは K 版だけに落とす（文字が4色に散らないように）。
    static func cgColor(_ c: RGBA, in space: CGColorSpace?) -> CGColor {
        guard let space else { return c.cgColor }
        switch space.model {
        case .cmyk:
            // r≈g≈b なら墨1色。入稿したときに文字が4色刷りにならない。
            let spread = max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
            if spread < 0.02 {
                let k = 1 - c.r
                return CGColor(colorSpace: space, components: [0, 0, 0, k, c.a]) ?? c.cgColor
            }
            return c.cgColor.converted(to: space, intent: .relativeColorimetric, options: nil) ?? c.cgColor
        case .monochrome:
            let y = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
            return CGColor(colorSpace: space, components: [y, c.a]) ?? c.cgColor
        default:
            return c.cgColor.converted(to: space, intent: .perceptual, options: nil) ?? c.cgColor
        }
    }

    /// 画像を指定の空間に変換する
    static func convert(_ image: CGImage, to space: CGColorSpace, profile: ColorProfile) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: profile.bitmapInfo) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// ガンマを掛け直す。1.0 でそのまま。
    /// 「刷ると沈む」ときに少し持ち上げる、といった最後の微調整に使う。
    static func applyGamma(_ image: CGImage, _ gamma: Double) -> CGImage? {
        guard abs(gamma - 1.0) > 0.001 else { return image }
        guard let space = image.colorSpace,
              let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: image.bitmapInfo.rawValue),
              let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // 256段の対応表を作って全画素に当てる
        var lut = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            lut[i] = UInt8(min(max(pow(Double(i) / 255.0, 1.0 / gamma) * 255.0, 0), 255))
        }
        let count = ctx.bytesPerRow * ctx.height
        let bytes = data.bindMemory(to: UInt8.self, capacity: count)
        let components = space.numberOfComponents
        let perPixel = ctx.bitsPerPixel / 8
        for row in 0..<ctx.height {
            let base = row * ctx.bytesPerRow
            for x in stride(from: 0, to: ctx.width * perPixel, by: perPixel) {
                for c in 0..<min(components, perPixel) {
                    bytes[base + x + c] = lut[Int(bytes[base + x + c])]
                }
            }
        }
        return ctx.makeImage()
    }
}
