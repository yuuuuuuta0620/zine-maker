import AppKit
import SwiftUI

/// 作品集全体の情報とシリーズの管理
struct PortfolioMetaSection: View {
    @ObservedObject var state: AppState
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                field("タイトル", $state.meta.title)
                field("サブタイトル", $state.meta.subtitle)
                field("著者名", $state.meta.author)
                field("制作年", $state.meta.year)
                Divider().padding(.vertical, 2)
                field("メール", $state.meta.email)
                field("サイト", $state.meta.website)
                field("電話", $state.meta.phone)
                Divider().padding(.vertical, 2)
                Text("ステートメント").font(.system(size: 10)).foregroundStyle(.secondary)
                TextEditor(text: $state.meta.statement)
                    .font(.system(size: 11))
                    .frame(height: 76)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.3)))
                Text("ここに入れた内容は、表紙やプロフィールのページに自動で差し込まれます。")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            SectionHeader("作品集の情報", icon: "info.circle")
        }
    }

    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }
}

struct SeriesSection: View {
    @ObservedObject var state: AppState
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if state.series.isEmpty {
                    Text("シリーズを作ると、中扉・通し番号・作品一覧がまとまります。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(state.series) { s in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            TextField("シリーズ名", text: Binding(
                                get: { s.title },
                                set: { state.renameSeries(s.id, title: $0, subtitle: s.subtitle) }))
                                .textFieldStyle(.roundedBorder).font(.system(size: 11))
                            Button { state.removeSeries(s.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).controlSize(.small)
                        }
                        TextField("副題", text: Binding(
                            get: { s.subtitle },
                            set: { state.renameSeries(s.id, title: s.title, subtitle: $0) }))
                            .textFieldStyle(.roundedBorder).font(.system(size: 10))
                        HStack(spacing: 4) {
                            let count = state.boards.filter { $0.seriesID == s.id }.count
                            Text("\(count) ページ").font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button("中扉を作る") {
                                state.addPortfolioPage(.divider, series: s)
                            }
                            .buttonStyle(.link).font(.system(size: 9))
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.4)))
                }
                Button("シリーズを追加") { state.addSeries() }
                    .controlSize(.small)
            }
            .padding(.top, 6)
        } label: {
            SectionHeader("シリーズ", icon: "square.stack")
        }
    }
}

/// いま開いているページの種別とシリーズ
struct PagePanel: View {
    @ObservedObject var state: AppState
    @State private var captionTemplate = CaptionTemplate.presets[1].template

    private var board: Artboard { state.currentBoard }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("このページの種別", icon: board.role.icon)
                Picker("", selection: Binding(
                    get: { board.role },
                    set: { state.setRole($0) })) {
                        ForEach(BoardRole.allCases) { role in
                            Label(role.label, systemImage: role.icon).tag(role)
                        }
                    }
                    .labelsHidden()
                Text(board.role == .content
                     ? "作品ページだけに通し番号が振られます。"
                     : "「\(board.role.label)」は通し番号の対象外です。")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if board.role == .divider {
                    TextField("見出し", text: Binding(
                        get: { board.title },
                        set: { state.beginUndoGroup(); state.currentBoard.title = $0 }))
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("所属シリーズ", icon: "square.stack")
                Picker("", selection: Binding(
                    get: { board.seriesID },
                    set: { state.assignCurrentBoard(to: $0) })) {
                        Text("なし").tag(UUID?.none)
                        ForEach(state.series) { Text($0.title.isEmpty ? "（無題）" : $0.title).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .disabled(state.series.isEmpty)
                Button("ここから次の中扉までをまとめる") {
                    state.assignFollowingBoards(to: board.seriesID)
                }
                .controlSize(.small)
                .disabled(board.seriesID == nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("キャプション", icon: "text.below.photo")
                CaptionTemplateField(template: $captionTemplate)
                Button("このページの写真に付ける") { state.addCaptions(template: captionTemplate) }
                    .controlSize(.small)
                Text("写真に紐づくので、あとで写真を差し替えても文面が追従します。")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("ページを追加", icon: "plus.rectangle.on.rectangle")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                    ForEach(BoardRole.allCases.filter { $0 != .content }) { role in
                        Button { state.addPortfolioPage(role) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: role.icon).font(.system(size: 13))
                                Text(role.label).font(.system(size: 9))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.45)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("表紙・ステートメント・一覧・プロフィールを一式作る") { state.scaffoldPortfolio() }
                    .controlSize(.small)
            }
        }
    }
}

/// テンプレート入力欄。プリセットと記号の挿入メニューが付く。
struct CaptionTemplateField: View {
    @Binding var template: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $template)
                .font(.system(size: 11).monospaced())
                .frame(height: 46)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 5).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.3)))

            HStack(spacing: 6) {
                Menu("ひな形") {
                    ForEach(CaptionTemplate.presets) { preset in
                        Button(preset.name) { template = preset.template }
                    }
                }
                Menu("記号を入れる") {
                    Section("写真から") {
                        ForEach(CaptionTemplate.photoTokens) { token in
                            Button("\(token.label)  \(token.text)") { template += token.text }
                        }
                    }
                    Section("作品集から") {
                        ForEach(CaptionTemplate.documentTokens) { token in
                            Button("\(token.label)  \(token.text)") { template += token.text }
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .font(.system(size: 10))
        }
    }
}
