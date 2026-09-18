import AppKit
import SwiftUI

/// ⌘, で開く設定画面
struct SettingsView: View {
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        TabView {
            GeneralSettings(prefs: prefs)
                .tabItem { Label("一般", systemImage: "gearshape") }
            DisplaySettings(prefs: prefs)
                .tabItem { Label("表示", systemImage: "ruler") }
            ExportSettings(prefs: prefs)
                .tabItem { Label("書き出し", systemImage: "square.and.arrow.up") }
            PhotoSettings(prefs: prefs)
                .tabItem { Label("写真", systemImage: "photo") }
            TypeSettings(prefs: prefs)
                .tabItem { Label("文字", systemImage: "textformat") }
        }
        .frame(width: 480, height: 400)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Picker("起動したら", selection: $prefs.launch) {
                ForEach(Preferences.Launch.allCases) { Text($0.label).tag($0) }
            }

            Section("新しいドキュメントの初期値") {
                Picker("種類", selection: $prefs.defaultKind) {
                    ForEach(DocKind.allCases) { Text($0.label).tag($0) }
                }
                if prefs.defaultKind == .zine {
                    Picker("判型", selection: $prefs.defaultPagePreset) {
                        ForEach(PagePreset.all) { Text($0.label).tag($0.name) }
                    }
                    Toggle("見開きで編集", isOn: $prefs.defaultFacing)
                    HStack {
                        TextField("塗り足し", value: $prefs.defaultBleedMM, format: .number.precision(.fractionLength(1)))
                            .frame(width: 60)
                        Text("mm").foregroundStyle(.secondary)
                        Spacer()
                        TextField("余白", value: $prefs.defaultMarginMM, format: .number.precision(.fractionLength(1)))
                            .frame(width: 60)
                        Text("mm").foregroundStyle(.secondary)
                    }
                } else {
                    Picker("アスペクト比", selection: $prefs.defaultAspect) {
                        ForEach(AspectRatio.presets) { Text("\($0.name)　\($0.note)").tag($0.name) }
                    }
                    HStack {
                        TextField("長辺", value: $prefs.defaultBoardLongEdge, format: .number.precision(.fractionLength(0)))
                            .frame(width: 70)
                        Text("px").foregroundStyle(.secondary)
                    }
                }
                ColorPicker("地色", selection: Binding(
                    get: { Color(nsColor: NSColor(cgColor: prefs.defaultBackground.cgColor) ?? .white) },
                    set: { if let c = NSColor($0).usingColorSpace(.sRGB) {
                        prefs.defaultBackground = RGBA(r: c.redComponent, g: c.greenComponent,
                                                       b: c.blueComponent, a: 1) } }))
            }

            Section {
                HStack {
                    Spacer()
                    Button("すべての設定を初期化") { prefs.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaySettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("キャンバスに出すもの") {
                Toggle("定規", isOn: $prefs.showRulers)
                Toggle("ガイド", isOn: $prefs.showGuides)
                Toggle("段組み", isOn: $prefs.showColumns)
                Toggle("吸着", isOn: $prefs.snapEnabled)
            }
            Section("見た目") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("キャンバスの明るさ")
                        Spacer()
                        Text(String(format: "%.0f%%", prefs.canvasBrightness * 100))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $prefs.canvasBrightness, in: 0...1)
                }
                Toggle("広色域で表示する（Display P3）", isOn: $prefs.wideGamutCanvas)
                Text("このMacのディスプレイは P3 に対応しています。切るとsRGBに丸めて表示します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("画質") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("画面表示の解像度")
                        Spacer()
                        Text(String(format: "%.1f×", prefs.screenQuality))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $prefs.screenQuality, in: 0.5...2.0, step: 0.25)
                }
                Text("大きくすると精細になりますが、写真の読み込みとメモリが増えます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExportSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("PDF") {
                HStack {
                    Text("目標DPI")
                    Spacer()
                    TextField("", value: $prefs.exportDPI, format: .number.precision(.fractionLength(0)))
                        .frame(width: 70).multilineTextAlignment(.trailing)
                }
                Toggle("可逆圧縮で埋め込む", isOn: $prefs.exportLossless)
                Text("切っておくと写真は JPEG ストリームで埋め込まれ、ファイルは10分の1以下になります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("画像") {
                Picker("既定の形式", selection: $prefs.exportFormat) {
                    ForEach(ImageExporter.Format.allCases.filter(\.isAvailable)) {
                        Text($0.label).tag($0.rawValue)
                    }
                }
                HStack {
                    Text("既定の長辺")
                    Spacer()
                    TextField("", value: $prefs.exportLongEdge, format: .number.precision(.fractionLength(0)))
                        .frame(width: 70).multilineTextAlignment(.trailing)
                    Text("px").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("画質")
                        Spacer()
                        Text(String(format: "%.2f", prefs.exportQuality))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $prefs.exportQuality, in: 0.3...1.0)
                }
            }
            Section {
                Toggle("前回の書き出し先を覚える", isOn: $prefs.rememberExportFolder)
                if prefs.rememberExportFolder, !prefs.lastExportFolder.isEmpty {
                    HStack {
                        Text(URL(fileURLWithPath: prefs.lastExportFolder).lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("忘れる") { prefs.lastExportFolder = "" }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PhotoSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("撮影地") {
                Toggle("写真を取り込んだらGPSから撮影地を調べる", isOn: $prefs.autoResolvePlaces)
                Text("結果はドキュメントに保存されるので、次からはオフラインでも出ます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("読み込み") {
                Toggle("次のページの写真を先読みする", isOn: $prefs.prefetchNeighbors)
            }
            Section("このMacに合わせた設定") {
                LabeledContent("同時に読み込む本数", value: "\(ImageStore.decodeConcurrency) 本")
                LabeledContent("画像キャッシュの上限", value: ImageStore.shared.cacheLimitDescription)
                LabeledContent("コア数", value: "\(ProcessInfo.processInfo.activeProcessorCount)")
                LabeledContent("メモリ", value: "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB")
                Text("搭載メモリとコア数から自動で決めています。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("キャッシュを空にする") { ImageStore.shared.purgeAll() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TypeSettings: View {
    @ObservedObject var prefs: Preferences
    private var families: [String] { NSFontManager.shared.availableFontFamilies }

    var body: some View {
        Form {
            Section("既定の書体") {
                Picker("見出し", selection: $prefs.headingFont) {
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Picker("本文・キャプション", selection: $prefs.bodyFont) {
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("見本") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("光の記録")
                        .font(.custom(prefs.headingFont, size: 24))
                    Text("Day : 2026.09.12 / Location : 目黒区 青葉台")
                        .font(.custom(prefs.bodyFont, size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
    }
}
