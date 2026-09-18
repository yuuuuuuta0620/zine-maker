import AppKit
import Combine
import SwiftUI

/// アプリ全体の設定。UserDefaults に保存され、新規ドキュメントの初期値などに使う。
final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum Launch: String, CaseIterable, Identifiable {
        case newDocument, lastDocument, nothing
        var id: String { rawValue }
        var label: String {
            switch self {
            case .newDocument: "新しいドキュメントを開く"
            case .lastDocument: "前回のファイルを開く"
            case .nothing: "何もしない"
            }
        }
    }

    // 一般
    @AppStorage("launch") var launch: Launch = .newDocument
    @AppStorage("defaultKind") var defaultKind: DocKind = .zine
    @AppStorage("defaultPagePreset") var defaultPagePreset = "A5"
    @AppStorage("defaultFacing") var defaultFacing = true
    @AppStorage("defaultBleedMM") var defaultBleedMM = 3.0
    @AppStorage("defaultMarginMM") var defaultMarginMM = 18.0
    @AppStorage("defaultBackgroundHex") var defaultBackgroundHex = "F4F2ED"
    @AppStorage("defaultAspect") var defaultAspect = "4:5"
    @AppStorage("defaultBoardLongEdge") var defaultBoardLongEdge = 2048.0

    // 表示
    @AppStorage("showRulers") var showRulers = true
    @AppStorage("showColumns") var showColumns = true
    @AppStorage("showGuides") var showGuides = true
    @AppStorage("snapEnabled") var snapEnabled = true
    @AppStorage("canvasBrightness") var canvasBrightness = 0.18
    @AppStorage("wideGamutCanvas") var wideGamutCanvas = true
    @AppStorage("useLiquidGlass") var useLiquidGlass = true
    @AppStorage("screenQuality") var screenQuality = 1.0     // 0.5〜2.0 の倍率

    // 書き出し
    @AppStorage("exportDPI") var exportDPI = 350.0
    @AppStorage("exportFormat") var exportFormat = "jpeg"
    @AppStorage("exportQuality") var exportQuality = 0.92
    @AppStorage("exportLossless") var exportLossless = false
    @AppStorage("exportLongEdge") var exportLongEdge = 2048.0
    @AppStorage("rememberExportFolder") var rememberExportFolder = true
    @AppStorage("lastExportFolder") var lastExportFolder = ""

    // 写真
    @AppStorage("autoResolvePlaces") var autoResolvePlaces = false
    @AppStorage("prefetchNeighbors") var prefetchNeighbors = true

    // 文字
    @AppStorage("headingFont") var headingFont = "HiraMinProN-W6"
    @AppStorage("bodyFont") var bodyFont = "HiraginoSans-W3"

    // MARK: - 派生

    var defaultBackground: RGBA {
        get { RGBA(hex: defaultBackgroundHex) ?? .white }
        set { defaultBackgroundHex = newValue.hex }
    }

    /// 設定を反映した新規ドキュメントの初期値
    func makeSettings(kind: DocKind? = nil) -> DocSettings {
        var s = DocSettings()
        s.kind = kind ?? defaultKind
        if let preset = PagePreset.all.first(where: { $0.name == defaultPagePreset }) {
            s.pageWidthMM = preset.widthMM
            s.pageHeightMM = preset.heightMM
        }
        s.facing = defaultFacing
        s.bleedMM = defaultBleedMM
        s.marginMM = defaultMarginMM
        s.background = defaultBackground
        if let preset = AspectRatio.presets.first(where: { $0.name == defaultAspect }) {
            s.aspect = preset.ratio
        }
        s.boardLongEdge = defaultBoardLongEdge
        return s
    }

    func resetAll() {
        let domain = Bundle.main.bundleIdentifier ?? "com.zinemaker.app"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        objectWillChange.send()
    }
}

// MARK: - 色の16進表記

extension RGBA {
    var hex: String {
        String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(r: CGFloat((v >> 16) & 0xFF) / 255,
                  g: CGFloat((v >> 8) & 0xFF) / 255,
                  b: CGFloat(v & 0xFF) / 255, a: 1)
    }
}

