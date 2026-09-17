import AppKit
import SwiftUI

/// 重なり順の一覧。手前が上。
/// ロック・非表示・名前の変更と、ドラッグでの並び替えができる。
struct LayersPanel: View {
    @ObservedObject var state: AppState
    @State private var renaming: UUID?
    @State private var draftName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d").font(.system(size: 10, weight: .semibold))
                Text("重なり順").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(state.currentBoard.elements.count)")
                    .font(.system(size: 10).monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Divider()

            if state.currentBoard.elements.isEmpty {
                VStack {
                    Spacer()
                    Text("要素がありません")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(Array(state.layerOrder.enumerated()), id: \.element.id) { index, element in
                        row(element, index: index)
                    }
                    .onMove { source, destination in
                        if let from = source.first { state.moveLayer(fromDisplay: from, toDisplay: destination) }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 24)
            }
        }
    }

    private func label(_ element: Element) -> String {
        if let name = element.customName, !name.isEmpty { return name }
        if let frame = element.imageFrame {
            if let id = frame.assetID, let asset = state.assetIndex[id] { return asset.name }
            return "空の写真枠"
        }
        if let text = element.textFrame {
            // 差し込みは記号のままでは何か分からないので、実際に出る文面を見せる
            let resolved = CanvasRenderer.resolvedText(for: text, scene: state.currentScene)
            let firstLine = resolved.split(separator: "\n").first.map(String.init) ?? ""
            return firstLine.isEmpty ? "テキスト" : String(firstLine.prefix(18))
        }
        return element.typeLabel
    }

    @ViewBuilder
    private func row(_ element: Element, index: Int) -> some View {
        let selected = state.selection.contains(element.id)
        HStack(spacing: 5) {
            Image(systemName: element.icon)
                .font(.system(size: 10))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(width: 14)

            if renaming == element.id {
                TextField("", text: $draftName, onCommit: {
                    state.rename(element.id, to: draftName)
                    renaming = nil
                })
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            } else {
                Text(label(element))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(element.hidden ? .tertiary : (selected ? Color.white : Color.primary))
            }

            Spacer(minLength: 2)

            if element.textFrame?.isDynamic == true {
                Image(systemName: "link")
                    .font(.system(size: 8))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                    .help("写真に紐づいた差し込み")
            }
            if element.rotation != 0 {
                Text("\(Int(element.rotation))°")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.tertiary)
            }
            Button { state.toggleHidden(element.id) } label: {
                Image(systemName: element.hidden ? "eye.slash" : "eye")
                    .font(.system(size: 9))
                    .foregroundStyle(element.hidden ? Color.orange : (selected ? Color.white.opacity(0.75) : Color.secondary))
            }
            .buttonStyle(.plain)
            .help(element.hidden ? "表示する" : "隠す")

            Button { state.toggleLock(element.id) } label: {
                Image(systemName: element.locked ? "lock.fill" : "lock.open")
                    .font(.system(size: 9))
                    .foregroundStyle(element.locked ? Color.orange : (selected ? Color.white.opacity(0.75) : Color.secondary))
            }
            .buttonStyle(.plain)
            .help(element.locked ? "ロックを外す" : "ロックする")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !element.locked else { return }
            state.select(element.id, additive: NSEvent.modifierFlags.contains(.shift))
        }
        .onTapGesture(count: 2) {
            draftName = element.customName ?? label(element)
            renaming = element.id
        }
        .contextMenu {
            Button("名前を変更") { draftName = element.customName ?? ""; renaming = element.id }
            Divider()
            Button(element.locked ? "ロックを外す" : "ロックする") { state.toggleLock(element.id) }
            Button(element.hidden ? "表示する" : "隠す") { state.toggleHidden(element.id) }
            Divider()
            Button("最前面へ") { state.selection = [element.id]; state.bringToFront() }
            Button("最背面へ") { state.selection = [element.id]; state.sendToBack() }
            Divider()
            Button("削除", role: .destructive) { state.selection = [element.id]; state.deleteSelected() }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))
        .listRowSeparator(.hidden)
    }
}

private extension Color {
    static var tertiary: Color { Color.primary.opacity(0.45) }
}
