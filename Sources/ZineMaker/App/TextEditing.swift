import AppKit

/// 文字を打っている間、⌘C などをふつうの文字編集にゆずるための橋渡し。
///
/// メニューのキー割り当ては第一応答者より先に働く。放っておくと、
/// キャンバスの文字編集や右の入力欄で、要素の選択があるときだけ
/// コピーも取り消しもできなくなる（要素の方が持っていってしまう）。
enum TextEditing {

    /// いま文字を打っているか。キャンバスのエディタでも、入力欄でも。
    @MainActor static var isActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let view = responder as? NSTextView { return view.isEditable }
        return responder is NSText
    }

    /// 打っている最中なら標準の動作に流して true を返す。
    /// 呼び出し側は true のとき自分の処理をやめる。
    @MainActor static func yield(_ action: Selector) -> Bool {
        guard isActive else { return false }
        _ = NSApp.sendAction(action, to: nil, from: nil)
        return true
    }

    static let cut = #selector(NSText.cut(_:))
    static let copy = #selector(NSText.copy(_:))
    static let paste = #selector(NSText.paste(_:))
    static let selectAll = #selector(NSText.selectAll(_:))
    static let deleteBackward = #selector(NSTextView.deleteBackward(_:))
    static let undo = NSSelectorFromString("undo:")
    static let redo = NSSelectorFromString("redo:")
}
