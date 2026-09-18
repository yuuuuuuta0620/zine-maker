import AppKit
import SwiftUI

/// 書き出す前の点検結果。クリックでその場所へ飛べる。
struct PreflightSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var targetDPI: Double = 300
    @State private var forPrint = true
    @State private var issues: [PreflightIssue] = []
    @State private var ran = false

    private var errors: Int { issues.filter { $0.severity == .error }.count }
    private var warnings: Int { issues.filter { $0.severity == .warning }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !ran {
                placeholder
            } else if issues.isEmpty {
                clean
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 520)
        .onAppear {
            forPrint = state.settings.kind == .zine
            run()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
            Text("書き出し前の点検").font(.system(size: 13, weight: .semibold))
            Spacer()
            if ran {
                if errors > 0 {
                    Label("\(errors)", systemImage: "exclamationmark.octagon.fill")
                        .font(.system(size: 11)).foregroundStyle(.red)
                }
                if warnings > 0 {
                    Label("\(warnings)", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
        }
        .padding(14)
    }

    private var placeholder: some View {
        VStack { Spacer(); ProgressView(); Spacer() }
    }

    private var clean: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34, weight: .light)).foregroundStyle(.green)
            Text("問題は見つかりませんでした").font(.system(size: 13, weight: .medium))
            Text("\(state.boards.count) ページを点検しました。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 種類ごとのまとめ
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Preflight.summary(issues), id: \.kind) { entry in
                        HStack(spacing: 7) {
                            Image(systemName: entry.severity.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(entry.severity == .error ? .red : .orange)
                            Text(entry.kind.title).font(.system(size: 11, weight: .medium))
                            Text("\(entry.count) 件")
                                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(entry.kind.advice)
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .padding(.leading, 24)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))

                // 場所ごと
                ForEach(groupedByBoard, id: \.0) { index, items in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pageLabel(index))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(items) { issue in
                            Button { jump(to: issue) } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: issue.severity.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                                    Text(issue.kind.title).font(.system(size: 11))
                                    Text(issue.detail)
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle")
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.2)))
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("印刷向けの項目も見る", isOn: $forPrint)
                .font(.system(size: 11))
                .onChange(of: forPrint) { _, _ in run() }
            if forPrint {
                Text("目標").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("", value: $targetDPI, format: .number.precision(.fractionLength(0)))
                    .frame(width: 46).multilineTextAlignment(.trailing)
                    .font(.system(size: 11).monospacedDigit())
                    .onSubmit { run() }
                Text("dpi").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("もう一度点検") { run() }
            Button("閉じる") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private var groupedByBoard: [(Int, [PreflightIssue])] {
        Dictionary(grouping: issues, by: \.boardIndex)
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private func pageLabel(_ index: Int) -> String {
        let per = state.settings.pagesPerSpread
        guard state.settings.kind == .zine, per == 2 else {
            return "\(state.settings.kind.unitLabel) \(index + 1)"
        }
        let first = index * per + 1
        return "\(first)–\(first + 1) ページ"
    }

    private func run() {
        ran = false
        let context = state.documentContext
        let options = Preflight.Options(targetDPI: targetDPI, forPrint: forPrint)
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Preflight.run(context, options: options)
            DispatchQueue.main.async { issues = found; ran = true }
        }
    }

    private func jump(to issue: PreflightIssue) {
        state.currentIndex = min(issue.boardIndex, state.boards.count - 1)
        if let id = issue.elementID,
           state.currentBoard.elements.contains(where: { $0.id == id }) {
            state.selection = [id]
        } else {
            state.selection.removeAll()
        }
        dismiss()
    }
}
