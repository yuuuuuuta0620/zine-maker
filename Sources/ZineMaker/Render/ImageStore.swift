import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO 経由の画像読み込み。AVIF / JPEG XL / TIFF / JPEG / PNG などを
/// システムのデコーダでそのまま扱う（追加ライブラリなし）。
///
/// 33MP を何十枚も並べるので、次の3点を守っている。
///   1. キャッシュは NSCache で容量を区切る（放っておくと数GBまで伸びる）
///   2. 同時デコード数を性能コア数までに抑える（無制限だとメモリが跳ねる）
///   3. 画面用は非同期。終わったら `didLoad` を1回だけ投げて再描画させる
final class ImageStore {
    static let shared = ImageStore()
    static let didLoad = Notification.Name("ImageStore.didLoad")

    /// NSOpenPanel に渡す対応形式。ImageIO が実際に読めるものだけ。
    static var readableTypes: [UTType] {
        let ids = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return ids.compactMap { UTType($0) }
    }

    // MARK: - この Mac に合わせた上限

    /// 同時にデコードする本数。
    /// 33MP×21枚での実測（M5 Pro / 48GB）:
    ///   1本 3514ms/+912MB  3本 1232ms/+819MB  5本 896ms/+581MB
    ///   8本  667ms/+1082MB 12本 561ms/+1482MB 21本 552ms/+1597MB
    /// 8本あたりが時間とメモリの折り返し点。搭載メモリが少ない機械では絞る。
    static let decodeConcurrency: Int = {
        let perf = sysctlInt("hw.perflevel0.logicalcpu") ?? (ProcessInfo.processInfo.activeProcessorCount / 2)
        let memGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let cap = memGB >= 32 ? 8 : (memGB >= 16 ? 6 : 4)
        return max(2, min(max(perf, 2) * 2, cap))
    }()

    /// キャッシュの上限。物理メモリの12%、1〜6GBの範囲に収める。
    static let cacheLimitBytes: Int = {
        let physical = Double(ProcessInfo.processInfo.physicalMemory)
        return Int(min(max(physical * 0.12, 1_073_741_824), 6_442_450_944))
    }()

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    // MARK: -

    private final class Key: NSObject {
        let path: String, bucket: Int
        init(_ path: String, _ bucket: Int) { self.path = path; self.bucket = bucket }
        override var hash: Int { path.hashValue ^ bucket }
        override func isEqual(_ object: Any?) -> Bool {
            guard let o = object as? Key else { return false }
            return o.path == path && o.bucket == bucket
        }
    }
    private final class Entry: NSObject { let image: CGImage; init(_ i: CGImage) { image = i } }

    private let cache: NSCache<Key, Entry> = {
        let c = NSCache<Key, Entry>()
        c.totalCostLimit = ImageStore.cacheLimitBytes
        return c
    }()

    private var sizes: [String: CGSize] = [:]
    private var metadataCache: [String: PhotoMetadata] = [:]
    private var inFlight: Set<String> = []
    private let lock = NSLock()

    private let queue = DispatchQueue(label: "ZineMaker.decode", qos: .userInitiated, attributes: .concurrent)
    private let prefetchQueue = DispatchQueue(label: "ZineMaker.prefetch", qos: .utility, attributes: .concurrent)
    private let gate = DispatchSemaphore(value: ImageStore.decodeConcurrency)

    /// 読み込み完了の通知は1フレームにまとめる。21枚読むたびに21回再描画しない。
    private var notifyScheduled = false

    private func scheduleNotify() {
        lock.lock()
        guard !notifyScheduled else { lock.unlock(); return }
        notifyScheduled = true
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
            self?.lock.lock(); self?.notifyScheduled = false; self?.lock.unlock()
            NotificationCenter.default.post(name: ImageStore.didLoad, object: nil)
        }
    }

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

        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let swapped = (5...8).contains(Int(orientation))
        let size = swapped ? CGSize(width: h, height: w) : CGSize(width: w, height: h)

        lock.lock(); sizes[url.path] = size; lock.unlock()
        return size
    }

    func cachedMetadata(_ path: String) -> PhotoMetadata? {
        lock.lock(); defer { lock.unlock() }
        return metadataCache[path]
    }

    func storeMetadata(_ m: PhotoMetadata, for path: String) {
        lock.lock(); metadataCache[path] = m; lock.unlock()
    }

    // MARK: - デコード

    private func bucket(for maxPixel: Int) -> Int {
        maxPixel >= 100_000 ? Int.max : max(256, ((maxPixel + 511) / 512) * 512)
    }

    private func cost(_ image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }

    /// 同期デコード。書き出しなど、その場で必ず必要なとき。
    func image(at url: URL, maxPixel: Int) -> CGImage? {
        let b = bucket(for: maxPixel)
        let key = Key(url.path, b)
        if let hit = cache.object(forKey: key) { return hit.image }

        gate.wait()
        defer { gate.signal() }
        // 待っている間に他が入れているかもしれない
        if let hit = cache.object(forKey: key) { return hit.image }

        guard let img = decode(url: url, bucket: b) else { return nil }
        // 原寸はひとつで数百MBになるのでキャッシュに載せない
        if b != Int.max { cache.setObject(Entry(img), forKey: key, cost: cost(img)) }
        return img
    }

    /// 非同期デコード。画面描画用。
    /// まだなければ、持っている粗い版を返しつつ裏で読み込み、完了を1フレームにまとめて通知する。
    func imageAsync(at url: URL, maxPixel: Int) -> CGImage? {
        let b = bucket(for: maxPixel)
        if let hit = cache.object(forKey: Key(url.path, b)) { return hit.image }

        // 粗い版があれば先に見せる
        var fallback: CGImage?
        var probe = b / 2
        while probe >= 256, fallback == nil {
            fallback = cache.object(forKey: Key(url.path, probe))?.image
            probe /= 2
        }

        let token = "\(url.path)#\(b)"
        lock.lock()
        let already = inFlight.contains(token)
        if !already { inFlight.insert(token) }
        lock.unlock()

        if !already {
            queue.async { [weak self] in
                guard let self else { return }
                self.gate.wait()
                let img = self.decode(url: url, bucket: b)
                self.gate.signal()
                if let img { self.cache.setObject(Entry(img), forKey: Key(url.path, b), cost: self.cost(img)) }
                self.lock.lock(); self.inFlight.remove(token); self.lock.unlock()
                self.scheduleNotify()
            }
        }
        return fallback
    }

    /// 次に見るページの写真を、優先度を下げて先読みしておく
    func prefetch(_ urls: [URL], maxPixel: Int) {
        let b = bucket(for: maxPixel)
        for url in urls {
            if cache.object(forKey: Key(url.path, b)) != nil { continue }
            let token = "\(url.path)#\(b)"
            lock.lock()
            if inFlight.contains(token) { lock.unlock(); continue }
            inFlight.insert(token)
            lock.unlock()

            prefetchQueue.async { [weak self] in
                guard let self else { return }
                self.gate.wait()
                let img = self.decode(url: url, bucket: b)
                self.gate.signal()
                if let img { self.cache.setObject(Entry(img), forKey: Key(url.path, b), cost: self.cost(img)) }
                self.lock.lock(); self.inFlight.remove(token); self.lock.unlock()
            }
        }
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

    /// トレイ用の小さなサムネイル
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

    // MARK: - 後始末

    func purgeFullResolution() {
        // 原寸は元々キャッシュしていないので、ここでは重い中間サイズだけ落とす
        cache.removeAllObjects()
    }

    func purgeAll() {
        cache.removeAllObjects()
        lock.lock(); sizes.removeAll(); metadataCache.removeAll(); lock.unlock()
    }

    var cacheLimitDescription: String {
        String(format: "%.1f GB", Double(ImageStore.cacheLimitBytes) / 1_073_741_824)
    }
}
