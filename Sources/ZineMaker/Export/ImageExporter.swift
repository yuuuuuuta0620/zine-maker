import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 画像書き出し。PDF と同じ描画コードを CGBitmapContext に流す。
enum ImageExporter {

    // MARK: - 形式

    enum Format: String, CaseIterable, Identifiable, Codable {
        case png, jpeg, avif, heic, tiff, jxl

        var id: String { rawValue }
        var ext: String {
            switch self {
            case .png: "png"; case .jpeg: "jpg"; case .avif: "avif"
            case .heic: "heic"; case .tiff: "tif"; case .jxl: "jxl"
            }
        }
        var label: String {
            switch self {
            case .png: "PNG"; case .jpeg: "JPEG"; case .avif: "AVIF"
            case .heic: "HEIC"; case .tiff: "TIFF"; case .jxl: "JPEG XL"
            }
        }
        var note: String {
            switch self {
            case .png:  "可逆・透過対応。web やスクリーンショット向け"
            case .jpeg: "どこでも開ける。SNS投稿はまずこれ"
            case .avif: "同画質で JPEG よりかなり小さい。主要ブラウザ対応"
            case .heic: "Apple 系で扱いやすい高効率形式"
            case .tiff: "可逆。他のアプリへ渡す中間ファイル向け"
            case .jxl:  "高効率。書き出しには cjxl が必要"
            }
        }
        var utType: UTType? {
            switch self {
            case .png: .png; case .jpeg: .jpeg; case .avif: UTType("public.avif")
            case .heic: UTType("public.heic"); case .tiff: .tiff; case .jxl: nil
            }
        }
        /// 品質スライダを持つか
        var isLossy: Bool { self == .jpeg || self == .avif || self == .heic || self == .jxl }
        var supportsTransparency: Bool { self == .png || self == .tiff || self == .avif }

        /// この Mac で実際に書き出せるか
        var isAvailable: Bool {
            if self == .jxl { return JXL.encoderPath != nil }
            guard let ut = utType else { return false }
            let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
            return writable.contains(ut.identifier)
        }
    }

    /// JPEG XL は ImageIO が読めても書けない（macOS 27 時点）。外部エンコーダを使う。
    enum JXL {
        static let encoderPath: String? = {
            let candidates = ["/opt/homebrew/bin/cjxl", "/usr/local/bin/cjxl", "/opt/local/bin/cjxl"]
            return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        }()
        static let installHint = "brew install jpeg-xl"
    }

    // MARK: - 出力サイズ

    enum Sizing: Equatable {
        /// ドキュメントのアスペクト比のまま、長辺を指定
        case longEdge(Double)
        /// ピクセル数を直接指定（比率が違えば背景色に収める）
        case exact(CGSize)
        /// ZINE の実寸を指定 DPI でラスタ化
        case dpi(Double)
    }

    struct Options {
        var format: Format = .jpeg
        var sizing: Sizing = .longEdge(2048)
        var quality: Double = 0.92
        var includeBleed = false
        /// PNG / TIFF / AVIF のみ。背景を塗らずに透過で出す
        var transparent = false
        /// 書き出す色空間
        var profile: ColorProfile = .sRGB
        /// 1.0 でそのまま。刷ると沈む場合などに最後の微調整として使う
        var gamma: Double = 1.0
        /// ICC プロファイルを埋め込む
        var embedProfile = true
    }

    enum ExportError: LocalizedError {
        case cannotCreateContext
        case cannotWrite(String)
        case encoderMissing(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateContext: "描画コンテキストを作れませんでした"
            case .cannotWrite(let s): "書き出しに失敗しました: \(s)"
            case .encoderMissing(let s): "この形式のエンコーダが見つかりません。\(s) でインストールしてください"
            }
        }
    }

    // MARK: - 本体

    @discardableResult
    static func export(board: Artboard, settings: DocSettings, scene: CanvasRenderer.Scene,
                       to url: URL, options: Options = .init()) throws -> CGSize {
        let image = try render(board: board, settings: settings, scene: scene, options: options)
        try write(image, to: url, options: options)
        ImageStore.shared.purgeFullResolution()
        return CGSize(width: image.width, height: image.height)
    }

    /// 書き出しと同じ経路でプレビュー用の小さな画像を作る
    static func preview(board: Artboard, settings: DocSettings, scene: CanvasRenderer.Scene,
                        options: Options, longEdge: CGFloat = 480) -> CGImage? {
        var o = options
        o.sizing = .longEdge(Double(longEdge))
        return try? render(board: board, settings: settings, scene: scene,
                           options: o, quality: .screen(maxPixel: 1024))
    }

    private static func render(board: Artboard, settings: DocSettings, scene: CanvasRenderer.Scene,
                               options: Options,
                               quality: CanvasRenderer.ImageQuality? = nil) throws -> CGImage {
        let source = options.includeBleed ? settings.mediaBox : settings.trimBox
        let pixelSize = outputSize(for: source, sizing: options.sizing)

        // CMYK / グレーはその空間では組めないので、いったん RGB で描いてから変換する
        let renderProfile: ColorProfile = options.profile.componentCount == 3 ? options.profile : .sRGB
        let renderSpace = renderProfile.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo =
            options.transparent && options.format.supportsTransparency
                ? .premultipliedLast : .noneSkipLast

        guard pixelSize.width >= 1, pixelSize.height >= 1,
              let ctx = CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: renderSpace,
                                  bitmapInfo: alphaInfo.rawValue)
        else { throw ExportError.cannotCreateContext }

        let opaque = !(options.transparent && options.format.supportsTransparency)
        if opaque {
            ctx.setFillColor(settings.background.cgColor)
            ctx.fill(CGRect(origin: .zero, size: pixelSize))
        }

        // 誌面をピクセル枠の中央に収める
        let scale = min(pixelSize.width / source.width, pixelSize.height / source.height)
        ctx.translateBy(x: (pixelSize.width - source.width * scale) / 2,
                        y: (pixelSize.height - source.height * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -source.minX, y: -source.minY)
        ctx.clip(to: source)

        // 出力ピクセル数から実効 DPI を逆算して、必要な分だけデコードする
        let renderQuality = quality ?? .output(dpi: Double(scale * 72), jpegQuality: nil)
        CanvasRenderer.draw(board, settings: settings, scene: scene, in: ctx,
                            options: .init(guides: false, quality: renderQuality,
                                           drawBackground: opaque))

        guard var image = ctx.makeImage() else { throw ExportError.cannotCreateContext }

        // ガンマ → 最終的な色空間、の順で通す
        if let adjusted = ColorConvert.applyGamma(image, options.gamma) { image = adjusted }
        if options.profile.componentCount != 3, let space = options.profile.colorSpace,
           let converted = ColorConvert.convert(image, to: space, profile: options.profile) {
            image = converted
        }
        return image
    }

    static func outputSize(for source: CGRect, sizing: Sizing) -> CGSize {
        switch sizing {
        case .longEdge(let edge):
            let scale = CGFloat(edge) / max(source.width, source.height)
            return CGSize(width: (source.width * scale).rounded(),
                          height: (source.height * scale).rounded())
        case .exact(let size):
            return CGSize(width: size.width.rounded(), height: size.height.rounded())
        case .dpi(let dpi):
            let scale = CGFloat(dpi) / 72
            return CGSize(width: (source.width * scale).rounded(),
                          height: (source.height * scale).rounded())
        }
    }

    // MARK: - 書き込み

    private static func write(_ image: CGImage, to url: URL, options: Options) throws {
        if options.format == .jxl {
            try writeJXL(image, to: url, quality: options.quality)
            return
        }
        guard let ut = options.format.utType,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, ut.identifier as CFString, 1, nil)
        else { throw ExportError.cannotWrite(url.lastPathComponent) }

        var props: [CFString: Any] = [:]
        if options.format.isLossy { props[kCGImageDestinationLossyCompressionQuality] = options.quality }
        props[kCGImageDestinationEmbedThumbnail] = false
        if options.embedProfile {
            // CGImage が色空間を持っているので ImageIO が ICC を埋める。
            // 名前だけ添えて、受け取り側が判別しやすいようにする。
            props[kCGImagePropertyProfileName] = options.profile.label
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.cannotWrite(url.lastPathComponent) }
    }

    /// cjxl に渡すため、いったん可逆の PNG を経由する
    private static func writeJXL(_ image: CGImage, to url: URL, quality: Double) throws {
        guard let encoder = JXL.encoderPath else { throw ExportError.encoderMissing(JXL.installHint) }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ExportError.cannotWrite(tmp.lastPathComponent) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.cannotWrite(tmp.lastPathComponent) }

        // cjxl の -q は 0-100（100 = 可逆）
        let process = Process()
        process.executableURL = URL(fileURLWithPath: encoder)
        process.arguments = [tmp.path, url.path, "-q", String(Int((quality * 100).rounded())), "--quiet"]
        process.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ExportError.cannotWrite("cjxl: \(msg.prefix(200))")
        }
    }
}
