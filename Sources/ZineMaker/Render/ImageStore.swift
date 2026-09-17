import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO 経由の画像読み込み。AVIF / JPEG XL / TIFF / JPEG / PNG などを
/// システムのデコーダでそのまま扱う（追加ライブラリなし）。
///
/// 33MP の写真を何十枚も並べるので、画面用のデコードは非同期にして
/// 描画スレッドを止めない。終わったら `didLoad` を投げて再描画させる。
final class ImageStore {
    static let shared = ImageStore()
    static let didLoad = Notification.Name("ImageStore.didLoad")

    /// NSOpenPanel に渡す対応形式。ImageIO が実際に読めるものだけ。
    static var readableTypes: [UTType] {
        let ids = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return ids.compactMap { UTType($0) }
    }

    private struct Key: Hashable { let path: String; let bucket: Int }

    private var cache: [Key: CGImage] = [:]
    private var sizes: [String: CGSize] = [:]
    private var inFlight: Set<Key> = []
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ZineMaker.decode", qos: .userInitiated, attributes: .concurrent)

    // MARK: - メタデータ

    /// ピクセル寸法（デコードせずにメタデータだけ読む）
    func pixelSize(of url: URL) -> CGSize? {
        lock.lock()
        if let s = sizes[url.path] { lock.unlock(); return s }
        lock.unlock()

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }

        // EXIF の回転を反映した見た目上のサイズ
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let swapped = (5...8).contains(Int(orientation))
        let size = swapped ? CGSize(width: h, height: w) : CGSize(width: w, height: h)

        lock.lock(); sizes[url.path] = size; lock.unlock()
        return size
    }

    // MARK: - デコード

    private func bucket(for maxPixel: Int) -> Int {
        maxPixel >= 100_000 ? Int.max : max(256, ((maxPixel + 511) / 512) * 512)
    }

    /// 同期デコード。書き出し用（原寸まで読む）。
    func image(at url: URL, maxPixel: Int) -> CGImage? {
        let b = bucket(for: maxPixel)
        let key = Key(path: url.path, bucket: b)
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        lock.unlock()

        guard let img = decode(url: url, bucket: b) else { return nil }
        lock.lock()
        if b != Int.max { cache[key] = img }   // 原寸はメモリを食うので残さない
        lock.unlock()
        return img
    }

    /// 非同期デコード。画面描画用。
    /// まだなければ、すでに持っている粗い版を返しつつ裏で読み込み、完了時に `didLoad` を投げる。
    func imageAsync(at url: URL, maxPixel: Int) -> CGImage? {
        let b = bucket(for: maxPixel)
        let key = Key(path: url.path, bucket: b)

        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        // 解像度が落ちても、あるものを先に見せる
        let fallback = cache.filter { $0.key.path == url.path && $0.key.bucket != Int.max }
            .max { $0.key.bucket < $1.key.bucket }?.value
        let alreadyLoading = inFlight.contains(key)
        if !alreadyLoading { inFlight.insert(key) }
        lock.unlock()

        if !alreadyLoading {
            queue.async { [weak self] in
                guard let self else { return }
                let img = self.decode(url: url, bucket: b)
                self.lock.lock()
                if let img { self.cache[key] = img }
                self.inFlight.remove(key)
                self.lock.unlock()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: ImageStore.didLoad, object: nil)
                }
            }
        }
        return fallback
    }

    private func decode(url: URL, bucket b: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let limit: Int
        if b == Int.max {
            let size = pixelSize(of: url) ?? CGSize(width: 4096, height: 4096)
            limit = Int(max(size.width, size.height))
        } else {
            limit = b
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // EXIF の回転を適用
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(limit, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// トレイ用の小さなサムネイル（同期・軽量）
    func thumbnail(at url: URL, maxPixel: Int = 256) -> CGImage? {
        imageAsync(at: url, maxPixel: maxPixel)
    }

    /// PDF 用に、JPEG データで裏打ちした CGImage を作る。
    /// これを CGPDFContext に描くと Quartz が DCTDecode ストリームとしてそのまま埋め込むので、
    /// ビットマップを可逆圧縮で持つより桁違いに小さくなる。
    static func jpegBacked(_ image: CGImage, quality: Double) -> CGImage? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest),
              let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    func purgeFullResolution() {
        lock.lock(); defer { lock.unlock() }
        cache = cache.filter { $0.key.bucket != Int.max }
    }
}
