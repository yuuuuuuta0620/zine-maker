import CoreLocation
import Foundation

/// EXIF の GPS 座標を地名に直す。
/// 結果は PhotoAsset に持たせて .zine に保存するので、一度引けば以後はオフラインでも出る。
enum PlaceResolver {

    struct Place: Codable, Equatable {
        /// 「渋谷区 恵比寿」のように短くまとめたもの
        var short: String
        /// 「東京都渋谷区恵比寿 1丁目」まで入れたもの
        var full: String
    }

    /// 座標をこの桁で丸めて同じ場所とみなす（約11m）。同じ地点を何度も引かないため。
    private static func key(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.4f,%.4f", lat, lon)
    }

    /// 地名を引いて assetID → Place を返す。
    /// CLGeocoder は連続で叩くと弾かれるので、地点ごとに間隔を空ける。
    static func resolve(_ assets: [PhotoAsset],
                        progress: @escaping (Int, Int) -> Void = { _, _ in },
                        completion: @escaping ([UUID: Place]) -> Void) {
        // 同じ座標の写真をまとめる
        var groups: [String: (coord: CLLocation, ids: [UUID])] = [:]
        for asset in assets {
            let m = ImageStore.shared.metadata(of: asset.url)
            guard let lat = m.latitude, let lon = m.longitude else { continue }
            let k = key(lat, lon)
            groups[k, default: (CLLocation(latitude: lat, longitude: lon), [])].ids.append(asset.id)
        }
        guard !groups.isEmpty else { completion([:]); return }

        let geocoder = CLGeocoder()
        let locale = Locale(identifier: "ja_JP")
        var result: [UUID: Place] = [:]
        let entries = Array(groups.values)

        func step(_ i: Int) {
            guard i < entries.count else {
                DispatchQueue.main.async { completion(result) }
                return
            }
            progress(i, entries.count)
            let entry = entries[i]
            geocoder.reverseGeocodeLocation(entry.coord, preferredLocale: locale) { marks, _ in
                if let mark = marks?.first, let place = format(mark) {
                    for id in entry.ids { result[id] = place }
                }
                // 叩きすぎると throttle されるので少し置く
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) { step(i + 1) }
            }
        }
        step(0)
    }

    private static func format(_ mark: CLPlacemark) -> Place? {
        let admin = mark.administrativeArea          // 東京都
        let locality = mark.locality                 // 渋谷区
        let sub = mark.subLocality                   // 恵比寿
        let thoroughfare = mark.thoroughfare         // 1丁目 など

        let shortParts = [locality, sub].compactMap { $0 }.filter { !$0.isEmpty }
        guard !shortParts.isEmpty || admin != nil else { return nil }
        let short = shortParts.isEmpty ? (admin ?? "") : shortParts.joined(separator: " ")

        // 「青葉台」と「青葉台2丁目」のように、後ろが前を含むことがあるので畳む
        var full = ""
        for part in [admin, locality, sub, thoroughfare].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if full.contains(part) { continue }
            if let last = full.range(of: part.prefix(max(part.count - 4, 1)), options: .backwards),
               last.upperBound == full.endIndex, part.hasPrefix(full[last]) {
                full.replaceSubrange(last, with: part)   // 「青葉台」→「青葉台2丁目」に伸ばす
                continue
            }
            full += part
        }
        return Place(short: short, full: full)
    }
}
