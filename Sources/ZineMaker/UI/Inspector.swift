import AppKit
import SwiftUI

struct Inspector: View {
    @ObservedObject var state: AppState
    @State private var tab: Tab = .document

    enum Tab: String, CaseIterable, Identifiable {
        case document, page, selection
        var id: String { rawValue }
        var label: String {
            switch self {
            case .document: "作品集"; case .page: "ページ"; case .selection: "選択中"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 9)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.sectionGap) {
                    switch tab {
                    case .document:  DocumentPanel(state: state)
                    case .page:      PagePanel(state: state)
                    case .selection: SelectionPanel(state: state)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: DS.inspectorWidth)
        .background(DS.panel)
        .onChange(of: state.selection) { _, new in
            if !new.isEmpty { tab = .selection }
        }
    }
}

// MARK: - ドキュメント

private struct DocumentPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("種類", icon: "square.stack.3d.up")
                Picker("", selection: Binding(
                    get: { state.settings.kind },
                    set: { state.switchKind(to: $0) })) {
                        ForEach(DocKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                Text(state.settings.displaySize)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if state.settings.kind == .zine { zineSection } else { boardSection }

            gridSection

            PortfolioMetaSection(state: state)
            SeriesSection(state: state)
            MasterSection(state: state)

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("地色", icon: "paintpalette")
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: NSColor(cgColor: state.settings.background.cgColor) ?? .white) },
                    set: { newValue in
                        state.beginUndoGroup()
                        if let c = NSColor(newValue).usingColorSpace(.sRGB) {
                            state.settings.background = RGBA(r: c.redComponent, g: c.greenComponent,
                                                             b: c.blueComponent, a: c.alphaComponent)
                        }
                    }))
                    .labelsHidden()
                HStack(spacing: 6) {
                    ForEach([RGBA.white, .paper, RGBA(r: 0.92, g: 0.92, b: 0.92, a: 1), .ink], id: \.self) { swatch in
                        Button {
                            state.beginUndoGroup()
                            state.settings.background = swatch
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: NSColor(cgColor: swatch.cgColor) ?? .white))
                                .frame(width: 26, height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // グリッドとガイド
    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("グリッドとガイド", icon: "grid")

            HStack(spacing: 8) {
                NumberField(label: "段", value: Binding(
                    get: { Double(state.settings.columns) },
                    set: { state.beginUndoGroup(); state.settings.columns = Int(max(0, $0)) }),
                    range: 0...24, fraction: 0)
                NumberField(label: "行", value: Binding(
                    get: { Double(state.settings.rows) },
                    set: { state.beginUndoGroup(); state.settings.rows = Int(max(0, $0)) }),
                    range: 0...24, fraction: 0)
            }
            NumberField(label: "段間", value: Binding(
                get: { state.settings.columnGutter },
                set: { state.beginUndoGroup(); state.settings.columnGutter = max(0, $0) }),
                unit: state.settings.kind == .zine ? "mm" : "%", range: 0...100, fraction: 2)
            Text("0 段で段組みを使いません。ドラッグ中はセルの端にも吸着します。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("定規を表示", isOn: $state.showRulers).font(.system(size: 11))
            Toggle("段組みを表示", isOn: $state.showColumns).font(.system(size: 11))
            Toggle("ガイドを表示", isOn: $state.showCustomGuides).font(.system(size: 11))
            Toggle("吸着する", isOn: $state.snapEnabled).font(.system(size: 11))

            NumberField(label: "刻み", value: Binding(
                get: { Double(state.gridStep) },
                set: { state.gridStep = CGFloat(max(0, $0)) }),
                unit: "pt", range: 0...200, fraction: 1)

            HStack(spacing: 6) {
                Button("選択からガイド") { state.guidesFromSelection() }
                    .disabled(state.selection.isEmpty)
                Button("ガイドを消す") { state.clearGuides() }
                    .disabled(state.settings.verticalGuides.isEmpty && state.settings.horizontalGuides.isEmpty)
            }
            .controlSize(.small)

            Text("定規の上端から下へドラッグで横ガイド、左端から右へドラッグで縦ガイド。定規へ戻すと消えます。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ZINE
    private var zineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("判型", icon: "book.closed")
            Picker("", selection: presetBinding) {
                Text("カスタム").tag(String?.none)
                ForEach(PagePreset.all) { Text($0.label).tag(String?.some($0.id)) }
            }
            .labelsHidden()

            HStack(spacing: 8) {
                NumberField(label: "幅", value: $state.settings.pageWidthMM, unit: "mm", range: 10...2000)
                NumberField(label: "高", value: $state.settings.pageHeightMM, unit: "mm", range: 10...2000)
            }
            HStack(spacing: 8) {
                NumberField(label: "裁ち", value: $state.settings.bleedMM, unit: "mm", range: 0...20)
                NumberField(label: "余白", value: $state.settings.marginMM, unit: "mm", range: 0...100)
            }
            Toggle("見開きで編集", isOn: $state.settings.facing)
                .font(.system(size: 11))
                .onChange(of: state.settings.facing) { _, _ in state.requestFit() }
        }
    }

    private var presetBinding: Binding<String?> {
        Binding(
            get: {
                PagePreset.all.first {
                    $0.widthMM == state.settings.pageWidthMM && $0.heightMM == state.settings.pageHeightMM
                }?.id
            },
            set: { id in
                guard let preset = PagePreset.all.first(where: { $0.id == id }) else { return }
                state.beginUndoGroup()
                state.settings.pageWidthMM = preset.widthMM
                state.settings.pageHeightMM = preset.heightMM
                state.requestFit()
            }
        )
    }

    // 組写真ボード
    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("アスペクト比", icon: "aspectratio")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], spacing: 6) {
                ForEach(AspectRatio.presets) { preset in
                    let active = state.settings.aspect == preset.ratio
                    Button { state.setAspect(preset.ratio) } label: {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(active ? Color.accentColor : Color.secondary.opacity(0.45))
                                .aspectRatio(preset.ratio.value, contentMode: .fit)
                                .frame(height: 22)
                            Text(preset.name).font(.system(size: 9).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(active ? Color.accentColor.opacity(0.16) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .help(preset.note)
                }
            }

            HStack(spacing: 8) {
                NumberField(label: "横", value: Binding(
                    get: { state.settings.aspect.w },
                    set: { state.setAspect(AspectRatio(w: max($0, 0.01), h: state.settings.aspect.h)) }),
                    range: 0.01...100, fraction: 2)
                Text(":").foregroundStyle(.tertiary)
                NumberField(label: "縦", value: Binding(
                    get: { state.settings.aspect.h },
                    set: { state.setAspect(AspectRatio(w: state.settings.aspect.w, h: max($0, 0.01))) }),
                    range: 0.01...100, fraction: 2)
            }
            Text("任意の比率を直接入力できます")
                .font(.system(size: 10)).foregroundStyle(.tertiary)

            Divider()

            SectionHeader("サイズと間隔", icon: "ruler")
            NumberField(label: "長辺", value: Binding(
                get: { state.settings.boardLongEdge },
                set: { state.settings.boardLongEdge = min(max($0, 64), 16384); state.requestFit() }),
                unit: "px", range: 64...16384, fraction: 0)
            SliderRow(label: "外周の余白", value: $state.settings.boardPaddingPct,
                      range: 0...20, step: 0.5, format: "%.1f", unit: "%")
            SliderRow(label: "写真の間隔", value: $state.settings.boardGutterPct,
                      range: 0...10, step: 0.25, format: "%.2f", unit: "%")
        }
    }
}

// MARK: - 選択中

private struct SelectionPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.selection.isEmpty {
            EmptyHint(icon: "hand.tap",
                      title: "何も選択されていません",
                      detail: "キャンバスの写真やテキストをクリックすると、ここで細かく調整できます。")
        } else if state.selection.count > 1 {
            multiSelection
        } else if let element = state.singleSelection {
            VStack(alignment: .leading, spacing: DS.sectionGap) {
                geometrySection(element)
                repeatSection
                switch element {
                case .image(let f): ImagePanel(state: state, frame: f)
                case .text(let f):  TextPanel(state: state, frame: f)
                case .shape(let f): ShapePanel(state: state, frame: f)
                }
            }
        }
    }

    private var multiSelection: some View {
        VStack(alignment: .leading, spacing: DS.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("\(state.selection.count) 個を選択中", icon: "square.on.square")
                alignButtons
            }
            spacingSection
            repeatSection

            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("まとめて", icon: "wand.and.stars")
                HStack(spacing: 6) {
                    Button("複製") { state.duplicateSelected() }
                    Button("ロック") { state.lockSelected(true) }
                    Button("削除", role: .destructive) { state.deleteSelected() }
                }
                .controlSize(.small)
            }
        }
    }

    @State private var gap: Double = 4
    @State private var repeatCount: Double = 3
    @State private var repeatDX: Double = 0
    @State private var repeatDY: Double = -20

    private var unitLabel: String { state.settings.kind == .zine ? "mm" : "px" }
    private func toPt(_ v: Double) -> CGFloat {
        state.settings.kind == .zine ? Pt.fromMM(v) : CGFloat(v)
    }

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("間隔をそろえる", icon: "arrow.left.and.right")
            NumberField(label: "間隔", value: $gap, unit: unitLabel, range: 0...1000, fraction: 2)
            HStack(spacing: 6) {
                Button("横に並べる") { state.setSpacing(toPt(gap), horizontally: true) }
                Button("縦に並べる") { state.setSpacing(toPt(gap), horizontally: false) }
            }
            .controlSize(.small)
            Text("選択範囲の左上を起点に、指定した隙間で並べ直します。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("繰り返し配置", icon: "square.on.square.dashed")
            NumberField(label: "回数", value: $repeatCount, range: 1...50, fraction: 0)
            HStack(spacing: 8) {
                NumberField(label: "→", value: $repeatDX, unit: unitLabel, range: -2000...2000)
                NumberField(label: "↓", value: $repeatDY, unit: unitLabel, range: -2000...2000)
            }
            Button("複製する") {
                state.stepAndRepeat(count: Int(repeatCount), dx: toPt(repeatDX), dy: -toPt(repeatDY))
            }
            .controlSize(.small)
        }
    }

    private var alignButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                alignButton("align.horizontal.left",   "左揃え",   .left)
                alignButton("align.horizontal.center", "左右中央", .hCenter)
                alignButton("align.horizontal.right",  "右揃え",   .right)
                Spacer().frame(width: 8)
                alignButton("align.vertical.top",      "上揃え",   .top)
                alignButton("align.vertical.center",   "上下中央", .vCenter)
                alignButton("align.vertical.bottom",   "下揃え",   .bottom)
            }
            HStack(spacing: 6) {
                Button("横に等間隔") { state.distribute(horizontally: true) }
                Button("縦に等間隔") { state.distribute(horizontally: false) }
            }
            .controlSize(.small)
            .disabled(state.selection.count < 3)
        }
    }

    private func alignButton(_ icon: String, _ help: String, _ mode: AppState.Align) -> some View {
        Button { state.align(mode) } label: {
            Image(systemName: icon).font(.system(size: 11)).frame(width: 24, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    // 位置とサイズ
    private func geometrySection(_ element: Element) -> some View {
        let isZine = state.settings.kind == .zine
        let unit = isZine ? "mm" : "px"
        let media = state.settings.mediaBox

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("\(element.typeLabel)の位置とサイズ", icon: element.icon)
            HStack(spacing: 8) {
                NumberField(label: "X", value: coordBinding(\.origin.x, offset: -media.minX), unit: unit)
                NumberField(label: "Y", value: topBinding(media: media), unit: unit)
            }
            HStack(spacing: 8) {
                NumberField(label: "幅", value: coordBinding(\.size.width), unit: unit, range: 0.1...100_000)
                NumberField(label: "高", value: coordBinding(\.size.height), unit: unit, range: 0.1...100_000)
            }
            HStack(spacing: 8) {
                NumberField(label: "回転", value: Binding(
                    get: { Double(state.singleSelection?.rotation ?? 0) },
                    set: { state.rotateSelected(to: CGFloat($0)) }), unit: "°", range: -360...360)
                HStack(spacing: 2) {
                    Button { state.rotateSelected(by: -90) } label: { Image(systemName: "rotate.left") }
                    Button { state.rotateSelected(by: 90) } label: { Image(systemName: "rotate.right") }
                    Button { state.rotateSelected(to: 0) } label: { Image(systemName: "arrow.counterclockwise") }
                        .help("回転をリセット")
                }
                .buttonStyle(.borderless).controlSize(.small)
            }

            HStack(spacing: 6) {
                Button("用紙いっぱい") { state.fillBoard() }
                Button("余白に合わせる") { state.fitToMargins() }
            }
            .controlSize(.small)
            HStack(spacing: 6) {
                Button("段組みに合わせる") { state.snapSelectionToColumns() }
                    .disabled(state.settings.columnRects.isEmpty)
                Toggle("ロック", isOn: Binding(
                    get: { element.locked },
                    set: { state.lockSelected($0) })).toggleStyle(.checkbox).font(.system(size: 11))
            }
            .controlSize(.small)
            HStack(spacing: 6) {
                Button { state.bringToFront() } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                    .help("最前面へ")
                Button { state.sendToBack() } label: { Image(systemName: "square.3.layers.3d.bottom.filled") }
                    .help("最背面へ")
                Button { state.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                    .help("複製")
                Spacer()
                Button(role: .destructive) { state.deleteSelected() } label: { Image(systemName: "trash") }
                    .help("削除")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    /// 内部 pt ↔ 表示単位（ZINE は mm、ボードは px）
    private func toDisplay(_ pt: CGFloat) -> Double {
        state.settings.kind == .zine ? Pt.toMM(pt) : Double(pt)
    }
    private func fromDisplay(_ v: Double) -> CGFloat {
        state.settings.kind == .zine ? Pt.fromMM(v) : CGFloat(v)
    }

    private func coordBinding(_ keyPath: WritableKeyPath<CGRect, CGFloat>, offset: CGFloat = 0) -> Binding<Double> {
        Binding(
            get: { toDisplay((state.singleSelection?.rect[keyPath: keyPath] ?? 0) + offset) },
            set: { newValue in
                state.beginUndoGroup()
                state.updateSelected { $0.rect[keyPath: keyPath] = fromDisplay(newValue) - offset }
            }
        )
    }

    /// Y は「紙の上端からの距離」で見せる（内部は y-up）
    private func topBinding(media: CGRect) -> Binding<Double> {
        Binding(
            get: {
                guard let rect = state.singleSelection?.rect else { return 0 }
                return toDisplay(media.maxY - rect.maxY)
            },
            set: { newValue in
                state.beginUndoGroup()
                state.updateSelected { element in
                    element.rect.origin.y = media.maxY - fromDisplay(newValue) - element.rect.height
                }
            }
        )
    }
}

// MARK: - 写真

private struct ImagePanel: View {
    @ObservedObject var state: AppState
    let frame: ImageFrame

    private var asset: PhotoAsset? { frame.assetID.flatMap { state.assetIndex[$0] } }

    private var dpi: Int? {
        guard let asset, let size = ImageStore.shared.pixelSize(of: asset.url) else { return nil }
        let target = CanvasRenderer.contentRect(for: frame, imageSize: size)
        guard target.width > 0 else { return nil }
        return Int((size.width / (target.width / 72)).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("写真", icon: "photo")

            if let asset {
                HStack(spacing: 8) {
                    CGImageView(image: ImageStore.shared.thumbnail(at: asset.url, maxPixel: 128), contentMode: .fill)
                        .frame(width: 44, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                        if let size = ImageStore.shared.pixelSize(of: asset.url) {
                            Text("\(Int(size.width))×\(Int(size.height)) px")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                if let dpi {
                    let low = state.settings.kind == .zine && dpi < 300
                    Label("配置時 \(dpi) dpi" + (low ? " — 印刷には粗いかもしれません" : ""),
                          systemImage: low ? "exclamationmark.triangle.fill" : "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(low ? .orange : .secondary)
                }
            } else {
                Label("写真が入っていません", systemImage: "photo.badge.plus")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("トレイからこの枠へドラッグするか、トレイの写真をダブルクリックします。")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text("収め方").font(.system(size: 11)).foregroundStyle(.secondary)
                IconPicker(selection: Binding(
                    get: { frame.fitMode },
                    set: { newValue in
                        state.beginUndoGroup()
                        state.updateSelected { if case .image(var f) = $0 { f.fitMode = newValue; $0 = .image(f) } }
                    }),
                    options: FitMode.allCases.map { ($0, $0.icon, $0.label) })
                Spacer()
            }

            Toggle("写真の比率を保つ", isOn: Binding(
                get: { frame.keepsPhotoAspect },
                set: { newValue in
                    state.beginUndoGroup()
                    state.updateSelected {
                        if case .image(var f) = $0 { f.keepsPhotoAspect = newValue; $0 = .image(f) }
                    }
                    if newValue { state.fitSelectedToPhotoAspect() }
                }))
                .font(.system(size: 11))
            Text("入れると、大きさを変えても写真の形のまま。切り取られません。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            SliderRow(label: "拡大率", value: Binding(
                get: { Double(frame.contentScale) * 100 },
                set: { newValue in
                    state.updateSelected { if case .image(var f) = $0 { f.contentScale = CGFloat(newValue / 100); $0 = .image(f) } }
                }), range: 25...400, step: 1, format: "%.0f", unit: "%")

            Button("トリミングをリセット") {
                state.beginUndoGroup()
                state.updateSelected {
                    if case .image(var f) = $0 { f.contentScale = 1; f.contentOffset = .zero; $0 = .image(f) }
                }
            }
            .controlSize(.small)

            Text("⌘ドラッグで枠内の写真を移動　⌥スクロールで拡大縮小")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            SectionHeader("見た目", icon: "square.on.circle")
            SliderRow(label: "角丸", value: Binding(
                get: { Double(frame.cornerRadius) },
                set: { newValue in
                    state.updateSelected { if case .image(var f) = $0 { f.cornerRadius = CGFloat(newValue); $0 = .image(f) } }
                }), range: 0...120, step: 1, format: "%.0f")
            SliderRow(label: "枠線", value: Binding(
                get: { Double(frame.strokeWidth) },
                set: { newValue in
                    state.updateSelected { if case .image(var f) = $0 { f.strokeWidth = CGFloat(newValue); $0 = .image(f) } }
                }), range: 0...20, step: 0.5, format: "%.1f")
        }
    }
}

// MARK: - テキスト

private struct TextPanel: View {
    @ObservedObject var state: AppState
    let frame: TextFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("テキスト", icon: "textformat")

            TextEditor(text: Binding(
                get: { frame.text },
                set: { newValue in
                    state.updateSelected { if case .text(var f) = $0 { f.text = newValue; $0 = .text(f) } }
                }))
                .font(.system(size: 12))
                .frame(height: 96)
                .disabled(frame.isDynamic)
                .opacity(frame.isDynamic ? 0.5 : 1)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 5).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.3)))

            if CanvasRenderer.textOverflows(frame, scene: state.currentScene) {
                Label("枠に収まっていません", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }

            Picker("書体", selection: bind(\.fontName)) {
                ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { Text($0).tag($0) }
            }
            .font(.system(size: 11))

            HStack(spacing: 8) {
                NumberField(label: "級", value: Binding(
                    get: { Double(frame.fontSize) },
                    set: { bind(\.fontSize).wrappedValue = CGFloat($0) }), unit: "pt", range: 1...400)
                NumberField(label: "行送", value: Binding(
                    get: { Double(frame.lineHeightScale) },
                    set: { bind(\.lineHeightScale).wrappedValue = CGFloat($0) }), unit: "×", range: 0.5...5, fraction: 2)
            }
            NumberField(label: "字間", value: Binding(
                get: { Double(frame.tracking) },
                set: { bind(\.tracking).wrappedValue = CGFloat($0) }), unit: "pt", range: -20...50, fraction: 2)

            HStack(spacing: 8) {
                IconPicker(selection: bind(\.alignment),
                           options: TextAlign.allCases.map { ($0, $0.icon, $0.label) })
                Spacer()
                Toggle("縦組み", isOn: bind(\.vertical)).font(.system(size: 11)).toggleStyle(.checkbox)
            }

            Divider()
            SectionHeader("下に敷く地", icon: "bookmark")
            IconPicker(selection: bind(\.plate),
                       options: TextPlate.allCases.map { ($0, $0.icon, $0.label) })
            if frame.plate != .none {
                HStack(spacing: 8) {
                    ColorPicker("地の色", selection: Binding(
                        get: { Color(nsColor: NSColor(cgColor: (frame.plateColor ?? RGBA(r: 0, g: 0, b: 0, a: 0.55)).cgColor) ?? .black) },
                        set: { newValue in
                            if let c = NSColor(newValue).usingColorSpace(.sRGB) {
                                bind(\.plateColor).wrappedValue = RGBA(r: c.redComponent, g: c.greenComponent,
                                                                       b: c.blueComponent, a: c.alphaComponent)
                            }
                        }))
                        .font(.system(size: 11))
                }
                SliderRow(label: "余白", value: Binding(
                    get: { Double(frame.platePadding) },
                    set: { bind(\.platePadding).wrappedValue = CGFloat($0) }),
                    range: 0...60, step: 0.5, format: "%.1f")
            }

            Divider()
            captionSection

            ColorPicker("文字色", selection: Binding(
                get: { Color(nsColor: NSColor(cgColor: frame.color.cgColor) ?? .black) },
                set: { newValue in
                    if let c = NSColor(newValue).usingColorSpace(.sRGB) {
                        bind(\.color).wrappedValue = RGBA(r: c.redComponent, g: c.greenComponent,
                                                          b: c.blueComponent, a: c.alphaComponent)
                    }
                }))
                .font(.system(size: 11))
        }
    }

    /// 写真へ紐づけて差し込みにする
    @ViewBuilder
    private var captionSection: some View {
        SectionHeader("写真から差し込む", icon: "text.below.photo")

        Toggle("写真に紐づける", isOn: Binding(
            get: { frame.isDynamic },
            set: { on in
                if on {
                    let nearest = nearestImageAsset()
                    state.linkCaption(textID: frame.id, to: nearest,
                                      template: frame.template ?? CaptionTemplate.presets[1].template)
                } else {
                    state.freezeCaption(textID: frame.id)
                }
            }))
            .font(.system(size: 11))

        if frame.isDynamic {
            Picker("元にする写真", selection: Binding(
                get: { frame.linkedAssetID },
                set: { state.linkCaption(textID: frame.id, to: $0, template: frame.template) })) {
                    Text("写真なし（作品集の情報だけ）").tag(UUID?.none)
                    ForEach(state.assets) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .font(.system(size: 11))

            CaptionTemplateField(template: Binding(
                get: { frame.template ?? "" },
                set: { state.linkCaption(textID: frame.id, to: frame.linkedAssetID, template: $0) }))

            VStack(alignment: .leading, spacing: 3) {
                Text("いまの表示").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(CanvasRenderer.resolvedText(for: frame, scene: state.currentScene))
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.4)))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("この文面で固定する") { state.freezeCaption(textID: frame.id) }
                .controlSize(.small)
        }
    }

    /// この枠のすぐ上にある写真を、キャプションの相手として選ぶ
    private func nearestImageAsset() -> UUID? {
        let mine = frame.rect
        let candidates = state.currentBoard.imageFrames.filter { $0.assetID != nil }
        let above = candidates
            .filter { $0.rect.minY >= mine.midY && abs($0.rect.midX - mine.midX) < max(mine.width, $0.rect.width) }
            .min { $0.rect.minY < $1.rect.minY }
        return (above ?? candidates.min { abs($0.rect.midY - mine.midY) < abs($1.rect.midY - mine.midY) })?.assetID
    }

    private func bind<T>(_ keyPath: WritableKeyPath<TextFrame, T>) -> Binding<T> {
        Binding(
            get: { frame[keyPath: keyPath] },
            set: { newValue in
                state.beginUndoGroup()
                state.updateSelected { if case .text(var f) = $0 { f[keyPath: keyPath] = newValue; $0 = .text(f) } }
            }
        )
    }
}


// MARK: - 図形

private struct ShapePanel: View {
    @ObservedObject var state: AppState
    let frame: ShapeFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("図形", icon: frame.kind.icon)

            Picker("", selection: bind(\.kind)) {
                ForEach(ShapeKind.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
            }
            .labelsHidden()

            if frame.kind == .line {
                Picker("向き", selection: Binding(
                    get: { frame.isVerticalLine },
                    set: { bind(\.lineVertical).wrappedValue = $0 })) {
                        Text("横").tag(false)
                        Text("縦").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .font(.system(size: 11))
            }

            if frame.kind != .line {
                colorRow("塗り", bind(\.fill))
                if frame.kind == .rectangle {
                    SliderRow(label: "角丸", value: Binding(
                        get: { Double(frame.cornerRadius) },
                        set: { bind(\.cornerRadius).wrappedValue = CGFloat($0) }),
                        range: 0...200, step: 1, format: "%.0f")
                }
            }

            colorRow(frame.kind == .line ? "線の色" : "枠線", bind(\.stroke))
            SliderRow(label: frame.kind == .line ? "太さ" : "枠線の太さ", value: Binding(
                get: { Double(frame.strokeWidth) },
                set: { bind(\.strokeWidth).wrappedValue = CGFloat($0) }),
                range: 0...40, step: 0.25, format: "%.2f")

            SliderRow(label: "不透明度", value: Binding(
                get: { Double(frame.opacity) * 100 },
                set: { bind(\.opacity).wrappedValue = CGFloat($0 / 100) }),
                range: 0...100, step: 1, format: "%.0f", unit: "%")
        }
    }

    private func colorRow(_ label: String, _ binding: Binding<RGBA?>) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { binding.wrappedValue != nil },
                set: { on in binding.wrappedValue = on ? (binding.wrappedValue ?? state.settings.background.contrastingInk) : nil }
            )) { Text(label).font(.system(size: 11)) }
                .toggleStyle(.checkbox)
            if let current = binding.wrappedValue {
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: NSColor(cgColor: current.cgColor) ?? .black) },
                    set: { newValue in
                        if let c = NSColor(newValue).usingColorSpace(.sRGB) {
                            binding.wrappedValue = RGBA(r: c.redComponent, g: c.greenComponent,
                                                        b: c.blueComponent, a: c.alphaComponent)
                        }
                    }))
                    .labelsHidden()
            }
            Spacer()
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<ShapeFrame, T>) -> Binding<T> {
        Binding(
            get: { frame[keyPath: keyPath] },
            set: { newValue in
                state.beginUndoGroup()
                state.updateSelected { if case .shape(var f) = $0 { f[keyPath: keyPath] = newValue; $0 = .shape(f) } }
            }
        )
    }
}
