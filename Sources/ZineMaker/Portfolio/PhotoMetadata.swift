import CoreGraphics
import Foundation
import ImageIO

/// 写真から読み取る撮影情報。ImageIO が EXIF / TIFF / IPTC をまとめて返すので、
/// 必要なものだけ取り出して整形する。
struct PhotoMetadata: Equatable {
    var captureDate: Date?
    var cameraMake: String?
    var cameraModel: String?
    var lens: String?
    /// mm
    var focalLength: Double?
    var focalLength35: Double?
    /// F値
    var aperture: Double?
    /// 秒
    var shutter: Double?
    var iso: Int?
    var title: String?
    var caption: String?
    var location: String?
    var pixelSize: CGSize?

    /// 撮影地の座標（EXIF GPS）
    var latitude: Double?
    var longitude: Double?
    /// レンズが向いていた方角（真北から時計回り）
    var direction: Double?
    var altitude: Double?

    var hasGPS: Bool { latitude != nil && longitude != nil }

    // MARK: 表示用の整形

    var cameraLabel: String? {
        guard let model = cameraModel else { return cameraMake }
        // 「SONY ILCE-7RM5」のように機種名がメーカー名で始まるなら重ねない
        if let make = cameraMake, !model.lowercased().hasPrefix(make.lowercased().split(separator: " ").first.map(String.init) ?? "") {
            return "\(make) \(model)"
        }
        return model
    }

    var focalLabel: String? {
        focalLength.map { "\(Int($0.rounded()))mm" }
    }

    var apertureLabel: String? {
        guard let a = aperture else { return nil }
        return a == a.rounded() ? "f/\(Int(a))" : String(format: "f/%.1f", a)
    }

    /// 1/250 のような分数表記に戻す
    var shutterLabel: String? {
        guard let s = shutter else { return nil }
        if s >= 1 { return s == s.rounded() ? "\(Int(s))s" : String(format: "%.1fs", s) }
        return "1/\(Int((1 / s).rounded()))s"
    }

    var isoLabel: String? { iso.map { "ISO \($0)" } }

    /// 35.65023, 139.69627
    var coordinateLabel: String? {
        guard let latitude, let longitude else { return nil }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    /// N35°39'01" E139°41'47"
    var coordinateDMS: String? {
        guard let latitude, let longitude else { return nil }
        func dms(_ v: Double, _ pos: String, _ neg: String) -> String {
            let a = abs(v)
            let d = Int(a), m = Int((a - Double(d)) * 60)
            let sec = ((a - Double(d)) * 60 - Double(m)) * 60
            return String(format: "%@%d°%02d'%02d\"", v >= 0 ? pos : neg, d, m, Int(sec.rounded()))
        }
        return "\(dms(latitude, "N", "S")) \(dms(longitude, "E", "W"))"
    }

    /// 北北東 のような16方位
    var directionLabel: String? {
        guard let direction else { return nil }
        let names = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                     "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]
        let i = Int((direction.truncatingRemainder(dividingBy: 360) / 22.5).rounded()) % 16
        return names[i]
    }

    func dateLabel(_ format: String = "yyyy年M月d日") -> String? {
        guard let d = captureDate else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = format
        return f.string(from: d)
    }

    /// 撮影データを1行にまとめたもの
    var exposureLine: String {
        [focalLabel, apertureLabel, shutterLabel, isoLabel].compactMap { $0 }.joined(separator: "　")
    }
}

// MARK: - 読み取り

extension ImageStore {
    private static var metadataCache: [String: PhotoMetadata] = [:]
    private static let metadataLock = NSLock()

    func metadata(of url: URL) -> PhotoMetadata {
        ImageStore.metadataLock.lock()
        if let cached = ImageStore.metadataCache[url.path] {
            ImageStore.metadataLock.unlock()
            return cached
        }
        ImageStore.metadataLock.unlock()

        var m = PhotoMetadata()
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {

            if let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
               let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
                let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
                let swapped = (5...8).contains(Int(orientation))
                m.pixelSize = swapped ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
            }

            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            m.cameraMake = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmed
            m.cameraModel = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmed

            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            m.lens = ((exif[kCGImagePropertyExifLensModel] as? String)
                      ?? (props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any])?[kCGImagePropertyExifAuxLensModel] as? String)?.trimmed
            m.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
            m.focalLength35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double
            m.aperture = exif[kCGImagePropertyExifFNumber] as? Double
            m.shutter = exif[kCGImagePropertyExifExposureTime] as? Double
            m.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first

            if let raw = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
                ?? (tiff[kCGImagePropertyTIFFDateTime] as? String) {
                let f = DateFormatter()
                f.dateFormat = "yyyy:MM:dd HH:mm:ss"
                f.locale = Locale(identifier: "en_US_POSIX")
                m.captureDate = f.date(from: raw)
            }

            // GPS。撮影地を出すのに使う
            if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
                if let lat = gps[kCGImagePropertyGPSLatitude] as? Double {
                    let ref = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
                    m.latitude = ref == "S" ? -lat : lat
                }
                if let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
                    let ref = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
                    m.longitude = ref == "W" ? -lon : lon
                }
                m.direction = gps[kCGImagePropertyGPSImgDirection] as? Double
                if let alt = gps[kCGImagePropertyGPSAltitude] as? Double {
                    let ref = (gps[kCGImagePropertyGPSAltitudeRef] as? Int) ?? 0
                    m.altitude = ref == 1 ? -alt : alt
                }
            }

            let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
            m.title = (iptc[kCGImagePropertyIPTCObjectName] as? String)?.trimmed
            m.caption = (iptc[kCGImagePropertyIPTCCaptionAbstract] as? String)?.trimmed
            // 市区町村と都道府県が同じ値のことがある（「東京都 東京都」を避ける）
            let city = (iptc[kCGImagePropertyIPTCCity] as? String)?.trimmed
            let province = (iptc[kCGImagePropertyIPTCProvinceState] as? String)?.trimmed
            let country = (iptc[kCGImagePropertyIPTCCountryPrimaryLocationName] as? String)?.trimmed
            var parts: [String] = []
            for part in [province, city, country] where part != nil {
                if !parts.contains(part!) { parts.append(part!) }
            }
            m.location = parts.joined(separator: " ").nilIfEmpty
        }

        ImageStore.metadataLock.lock()
        ImageStore.metadataCache[url.path] = m
        ImageStore.metadataLock.unlock()
        return m
    }
}

private extension String {
    var trimmed: String? { trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
