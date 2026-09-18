import SwiftUI

/// Liquid Glass（macOS 26 以降）の当て方をここにまとめる。
///
/// 写真を扱うアプリなので、**ガラスはコンテンツの上に浮く操作層にだけ使う**。
/// キャンバスや写真そのものに掛けると、わずかに色が転んでぼけるため、
/// 色や粒子を判断する面としては成立しなくなる。
/// 対応していない環境では従来の material に落ちる。
enum GlassStyle {
    /// この環境で Liquid Glass を使えるか
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// 設定で切れるようにしてある
    static var enabled: Bool { isAvailable && Preferences.shared.useLiquidGlass }
}

extension View {

    /// 浮いているパネル（ズーム操作、案内の帯など）
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 10, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *), GlassStyle.enabled {
            if let tint {
                glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            } else {
                glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    /// 押せるもの。触れると反応するガラスになる。
    @ViewBuilder
    func glassControl(cornerRadius: CGFloat = 8, tint: Color? = nil, prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *), GlassStyle.enabled {
            if prominent {
                glassEffect(.regular.tint(tint ?? .accentColor).interactive(),
                            in: .rect(cornerRadius: cornerRadius))
            } else if let tint {
                glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(prominent ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(Color.primary.opacity(0.08)))
            )
        }
    }

    /// 背景に溶け込ませたいだけの薄いガラス（帯や見出し）
    @ViewBuilder
    func glassBar() -> some View {
        if #available(macOS 26.0, *), GlassStyle.enabled {
            glassEffect(.clear, in: .rect(cornerRadius: 0))
        } else {
            background(.bar)
        }
    }

    /// 近くのガラス同士を馴染ませる入れ物。対応していなければそのまま。
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 8) -> some View {
        if #available(macOS 26.0, *), GlassStyle.enabled {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

// MARK: - タブの面

extension View {
    /// タブ1枚の面。選択中はガラスで浮かせ、それ以外は地に沈める。
    @ViewBuilder
    func tabSurface(isActive: Bool, isHover: Bool, id: UUID, namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *), GlassStyle.enabled {
            glassEffect(isActive ? .regular.interactive() : .clear,
                        in: .rect(cornerRadius: 7))
                .glassEffectID(id, in: namespace)
                .opacity(isActive ? 1 : (isHover ? 0.9 : 0.68))
        } else {
            background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color(nsColor: .controlBackgroundColor)
                                   : Color.primary.opacity(isHover ? 0.10 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isActive ? 0.10 : 0), lineWidth: 0.5)
            )
        }
    }
}
