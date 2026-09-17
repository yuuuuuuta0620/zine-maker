import AppKit
import SwiftUI

struct ExportSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case image, pdf
        var id: String { rawValue }
        var label: String { self == .image ? "画像" : "PDF" }
    }

    @State private var kind: Kind = .image

    // 画像
    @State private var format: ImageExporter.Format = .jpeg
    @State private var sizingMode: SizingMode = .longEdge
    @State private var longEdge: Double = 2048
    @State private var exactW: Double = 1080
    @State private var exactH: Double = 1350
    @State private var quality: Double = 0.92
    @State private var transparent = false
    @State private var allBoards = false

    // PDF
    @State private var pdfMode: PDFExporter.PageMode = .singlePage
    @State private var dpi: Double = 350
    @State private var printBoxes = true
    @State private var lossless = false

    enum SizingMode: String, CaseIterable, Identifiable {
        case longEdge, exact
        var id: String { rawValue }
        var label: String { self == .longEdge ? "長辺で指定" : "ピクセル数で指定" }
    }

    private var sizing: ImageExporter.Sizing {
        sizingMode == .longEdge ? .longEdge(longEdge) : .exact(CGSize(width: exactW, height: exactH))
    }

    private var imageOptions: ImageExporter.Options {
        .init(format: format, sizing: sizing, quality: quality,
              includeBleed: false, transparent: transparent)
    }

    private var outputSize: CGSize {
        ImageExporter.outputSize(for: state.settings.trimBox, sizing: sizing)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.sectionGap) {
                        if kind == .image { imageSettings } else { pdfSettings }
                    }
                    .padding(16)
                }
                .frame(width: 320)

                Divider()
                previewPane.frame(width: 260)
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 520)
    }

    private var header: some View {
        HStack {
            Text("書き出し").font(.system(size: 13, weight: .semibold))
            Spacer()
            Picker("", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
        }
        .padding(14)
    }

    // MARK: - 画像

    private var imageSettings: some View {
        VStack(alignment: .leading, spacing: DS.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("形式", icon: "doc")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], spacing: 6) {
                    ForEach(ImageExporter.Format.allCases) { f in
                        let available = f.isAvailable
                        Button {
                            format = f
                            if !f.supportsTransparency { transparent = false }
                        } label: {
                            Text(f.label)
                                .font(.system(size: 11, weight: format == f ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(format == f ? Color.accentColor : Color.secondary.opacity(0.15)))
                                .foregroundStyle(format == f ? Color.white : (available ? Color.primary : Color.secondary))
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                        .help(available ? f.note : "\(f.note)（未インストール）")
                    }
                }
                Text(format.note).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if format == .jxl, !ImageExporter.Format.jxl.isAvailable {
                    Label("cjxl が見つかりません。`\(ImageExporter.JXL.installHint)` でインストールしてください。",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("サイズ", icon: "arrow.up.left.and.arrow.down.right")
                Picker("", selection: $sizingMode) {
                    ForEach(SizingMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()

                if sizingMode == .longEdge {
                    NumberField(label: "長辺", value: $longEdge, unit: "px", range: 64...16384, fraction: 0)
                    HStack(spacing: 4) {
                        ForEach([1080.0, 1440, 2048, 2560, 4096], id: \.self) { v in
                            Button("\(Int(v))") { longEdge = v }
                                .buttonStyle(.borderless).controlSize(.small)
                                .font(.system(size: 10).monospacedDigit())
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        NumberField(label: "幅", value: $exactW, unit: "px", range: 16...16384, fraction: 0)
                        NumberField(label: "高", value: $exactH, unit: "px", range: 16...16384, fraction: 0)
                    }
                    Text("誌面の比率と違う場合は、地色を背景に中央へ収めます。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if format.isLossy {
                SliderRow(label: "画質", value: $quality, range: 0.3...1.0, step: 0.01, format: "%.2f")
            }
            if format.supportsTransparency {
                Toggle("背景を透過にする", isOn: $transparent).font(.system(size: 11))
            }
            Toggle("すべての\(state.settings.kind.unitLabel)を連番で書き出す", isOn: $allBoards)
                .font(.system(size: 11))
        }
    }

    // MARK: - PDF

    private var pdfSettings: some View {
        VStack(alignment: .leading, spacing: DS.sectionGap) {
            if state.settings.kind == .zine {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("ページ構成", icon: "doc.on.doc")
                    Picker("", selection: $pdfMode) {
                        ForEach(PDFExporter.PageMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(pdfMode == .singlePage
                         ? "1ページずつ、四辺に塗り足し \(Int(state.settings.bleedMM))mm を付けて出力します（多くの印刷所の標準）。"
                         : "見開きのまま出力します。PDF写真集として配る場合や、面付けを印刷所に任せる場合。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("トンボ情報（TrimBox / BleedBox）を入れる", isOn: $printBoxes)
                        .font(.system(size: 11))
                    Text("印刷所へ入稿するならオンのまま。画面で見せるだけならオフでもかまいません。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("組写真モードでは、各ボードが1ページの PDF になります。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("写真の埋め込み", icon: "photo")

                if state.settings.kind == .zine {
                    SliderRow(label: "目標 DPI", value: $dpi, range: 72...600, step: 1, format: "%.0f", unit: " dpi")
                    HStack(spacing: 4) {
                        ForEach([150.0, 300, 350, 400], id: \.self) { v in
                            Button("\(Int(v))") { dpi = v }
                                .buttonStyle(.borderless).controlSize(.small)
                                .font(.system(size: 10).monospacedDigit())
                        }
                    }
                    Text("配置サイズに対して必要な画素数だけ埋め込みます。元画像より上げても水増しはしません。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("ボードのピクセル数のまま等倍で埋め込みます（\(Int(state.settings.boardSize.width))×\(Int(state.settings.boardSize.height)) px）",
                          systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("可逆圧縮で埋め込む（ファイルが非常に大きくなります）", isOn: $lossless)
                    .font(.system(size: 11))
                Text(lossless
                     ? "画質の劣化はありませんが、写真1枚あたり数十MBになります。特別な理由がなければオフのままで十分です。"
                     : "写真は JPEG ストリームとして埋め込みます。入稿にも通る品質で、ファイルは10分の1以下になります。")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("\(PDFExporter.pageCount(boards: state.boards.count, settings: state.settings, mode: pdfMode)) ページ",
                  systemImage: "number")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: - プレビュー

    private var previewPane: some View {
        VStack(spacing: 10) {
            SectionHeader("プレビュー", icon: "eye")
                .padding(.horizontal, 14).padding(.top, 14)

            let preview = ImageExporter.preview(board: state.currentBoard, settings: state.settings,
                                                scene: state.currentScene, options: imageOptions)
            CGImageView(image: preview)
                .frame(maxWidth: .infinity, maxHeight: 260)
                .padding(.horizontal, 14)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                if kind == .image {
                    row("出力サイズ", "\(Int(outputSize.width)) × \(Int(outputSize.height)) px")
                    row("形式", format.label)
                    row("枚数", allBoards ? "\(state.boards.count) 枚" : "1 枚")
                } else {
                    row("仕上がり", state.settings.displaySize)
                    row("ページ数", "\(PDFExporter.pageCount(boards: state.boards.count, settings: state.settings, mode: pdfMode))")
                    row("解像度", state.settings.kind == .zine ? "\(Int(dpi)) dpi" : "等倍")
                    row("埋め込み", lossless ? "可逆" : "JPEG")
                }
            }
            .padding(.horizontal, 14)
            Spacer()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Text(value).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if !state.status.isEmpty {
                Text(state.status).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("書き出す") {
                dismiss()
                if kind == .image {
                    state.exportImage(options: imageOptions, allBoards: allBoards)
                } else {
                    state.exportPDF(options: .init(mode: pdfMode, dpi: dpi,
                                                   compression: lossless ? .lossless : .jpeg(quality: 0.92),
                                                   printBoxes: printBoxes,
                                                   title: state.fileURL?.deletingPathExtension().lastPathComponent ?? "ZineMaker"))
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(kind == .image && !format.isAvailable)
        }
        .padding(14)
    }
}
