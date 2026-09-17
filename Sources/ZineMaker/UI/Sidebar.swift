import AppKit
import SwiftUI

/// 左サイドバー。見開き／ボードの一覧。
struct Sidebar: View {
    @ObservedObject var state: AppState
    @State private var tick = 0

    var body: some View {
        VSplitView {
            boardList
            LayersPanel(state: state)
                .frame(minHeight: 120, idealHeight: 200)
        }
        .onReceive(NotificationCenter.default.publisher(for: ImageStore.didLoad)) { _ in tick &+= 1 }
    }

    private var boardList: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(selection: Binding(
                    get: { state.boards.indices.contains(state.currentIndex) ? state.boards[state.currentIndex].id : nil },
                    set: { id in
                        if let idx = state.boards.firstIndex(where: { $0.id == id }) {
                            state.currentIndex = idx
                            state.selection.removeAll()
                        }
                    })) {
                    ForEach(Array(state.boards.enumerated()), id: \.element.id) { index, board in
                        BoardRow(state: state, board: board, index: index, tick: tick)
                            .tag(board.id)
                            .id(board.id)
                    }
                    .onMove { source, destination in
                        if let from = source.first { state.moveBoard(from: from, to: destination) }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: state.currentIndex) { _, new in
                    guard state.boards.indices.contains(new) else { return }
                    withAnimation { proxy.scrollTo(state.boards[new].id) }
                }
            }

            Divider()
            HStack(spacing: 4) {
                Button { state.addBoard() } label: { Image(systemName: "plus") }
                    .help("\(state.settings.kind.unitLabel)を追加")
                Button { state.duplicateBoard() } label: { Image(systemName: "plus.square.on.square") }
                    .help("複製")
                Button { state.deleteCurrentBoard() } label: { Image(systemName: "minus") }
                    .help("削除")
                    .disabled(state.boards.count <= 1)
                Spacer()
                Text("\(state.boards.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(minHeight: 180)
    }
}

private struct BoardRow: View {
    @ObservedObject var state: AppState
    let board: Artboard
    let index: Int
    let tick: Int

    private var label: String {
        if board.role != .content { return board.role.label }
        if state.settings.kind == .zine {
            let per = state.settings.pagesPerSpread
            let first = index * per + 1
            return per == 2 ? "\(first)–\(first + 1)" : "\(first)"
        }
        return "\(index + 1)"
    }

    private var seriesTitle: String? {
        guard let id = board.seriesID else { return nil }
        return state.series.first { $0.id == id }?.title.nilWhenEmpty
    }

    var body: some View {
        let thumb = CanvasRenderer.rasterize(board, settings: state.settings,
                                             scene: state.scene(forBoardAt: index), longEdge: 180,
                                             quality: .screen(maxPixel: 320))
        VStack(spacing: 4) {
            CGImageView(image: thumb)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            HStack(spacing: 3) {
                if board.role != .content {
                    Image(systemName: board.role.icon).font(.system(size: 8))
                        .foregroundStyle(.tint)
                }
                Text(label).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                let empties = board.imageFrames.filter { $0.assetID == nil }.count
                if empties > 0 {
                    Image(systemName: "\(min(empties, 50)).circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .help("空の枠が \(empties) 個")
                }
            }
            if let seriesTitle {
                Text(seriesTitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Menu("ページの種別") {
                ForEach(BoardRole.allCases) { role in
                    Button(role.label) { state.currentIndex = index; state.setRole(role) }
                }
            }
            if !state.series.isEmpty {
                Menu("シリーズ") {
                    Button("なし") { state.currentIndex = index; state.assignCurrentBoard(to: nil) }
                    ForEach(state.series) { s in
                        Button(s.title.isEmpty ? "（無題）" : s.title) {
                            state.currentIndex = index; state.assignCurrentBoard(to: s.id)
                        }
                    }
                }
            }
            Divider()
            Button("複製") { state.currentIndex = index; state.duplicateBoard() }
            Button("削除", role: .destructive) { state.currentIndex = index; state.deleteCurrentBoard() }
        }
    }
}

// MARK: - レイアウト選択

/// テンプレートを図で選ばせるギャラリー
struct TemplatePicker: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .thisBoard

    enum Mode: String, CaseIterable, Identifiable {
        case thisBoard, flowAll
        var id: String { rawValue }
        var label: String { self == .thisBoard ? "このページに適用" : "全部を流し込む" }
    }

    private var photoCount: Int {
        state.traySelection.isEmpty ? state.unplacedAssets.count : state.traySelection.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("レイアウト").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).controlSize(.small)
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            Text(mode == .thisBoard
                 ? "選んだ形に枠を作り、\(state.traySelection.isEmpty ? "未配置の写真" : "選択中の写真")を順に入れます。"
                 : "\(photoCount) 枚を、このレイアウトを繰り返しながら必要な数の\(state.settings.kind.unitLabel)へ分けて配置します。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    ForEach(LayoutTemplate.suggestions(for: max(photoCount, 1))) { template in
                        Button {
                            if mode == .thisBoard { state.applyTemplate(template) }
                            else { state.autoFlow(template: template) }
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                TemplateGlyph(template: template, aspect: state.settings.trimBox.size.aspect)
                                    .frame(height: 58)
                                Text(template.name).font(.system(size: 10))
                                Text("\(template.count)枚")
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 400, height: 460)
    }
}

/// テンプレートの形を小さく描く
struct TemplateGlyph: View {
    let template: LayoutTemplate
    var aspect: CGFloat = 0.8

    var body: some View {
        GeometryReader { geo in
            let boxW = min(geo.size.width, geo.size.height * aspect)
            let boxH = boxW / aspect
            let ox = (geo.size.width - boxW) / 2
            let oy = (geo.size.height - boxH) / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: boxW, height: boxH)
                    .offset(x: ox, y: oy)
                ForEach(Array(template.slots.enumerated()), id: \.offset) { _, slot in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: max(slot.width * boxW - 1.5, 1),
                               height: max(slot.height * boxH - 1.5, 1))
                        // slots は y-up、SwiftUI は y-down なので上下を入れ替える
                        .offset(x: ox + slot.minX * boxW + 0.75,
                                y: oy + (1 - slot.maxY) * boxH + 0.75)
                }
            }
        }
    }
}
