import AppKit
import SwiftUI

/// アプリ全体で使う余白・色・共通パーツ。
enum DS {
    static let gutter: CGFloat = 12
    static let sectionGap: CGFloat = 20
    static let inspectorWidth: CGFloat = 300
    static let trayHeight: CGFloat = 108
    static let corner: CGFloat = 8

    static let canvasBackground = Color(nsColor: .underPageBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
}

extension NSPasteboard.PasteboardType {
    /// 写真トレイからキャンバスへドラッグするときに運ぶ PhotoAsset の UUID
    static let zineAsset = NSPasteboard.PasteboardType("com.zinemaker.asset")
}

// MARK: - 共通パーツ

/// インスペクタの見出し
struct SectionHeader: View {
    let title: String
    var icon: String?
    var trailing: AnyView?

    init(_ title: String, icon: String? = nil) {
        self.title = title; self.icon = icon; self.trailing = nil
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            Text(title).font(.system(size: 11, weight: .semibold))
            Spacer()
            if let trailing { trailing }
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

/// ラベル＋数値入力＋単位
struct NumberField: View {
    let label: String
    @Binding var value: Double
    var unit: String = ""
    var range: ClosedRange<Double> = -100_000...100_000
    var fraction: Int = 1

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            TextField("", value: Binding(
                get: { value },
                set: { value = min(max($0, range.lowerBound), range.upperBound) }
            ), format: .number.precision(.fractionLength(fraction)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11).monospacedDigit())
            if !unit.isEmpty {
                Text(unit).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 18, alignment: .leading)
            }
        }
    }
}

/// ラベル＋スライダ＋数値表示
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var format: String = "%.0f"
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value) + unit)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step).controlSize(.small)
        }
    }
}

/// アイコンだけの小さなトグル群
struct IconPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, icon: String, help: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 11))
                        .frame(width: 26, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selection == option.value ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(selection == option.value ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help(option.help)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
    }
}

/// 何も選ばれていないときなどの案内
struct EmptyHint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// CGImage をそのまま表示する
struct CGImageView: View {
    let image: CGImage?
    var contentMode: ContentMode = .fit

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}

extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
