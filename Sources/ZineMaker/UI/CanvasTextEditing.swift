import AppKit
import CoreGraphics

/// キャンバスの上で直接文字を打つための仕掛け。
/// 見た目（書体・級数・行送り・色・揃え・縦組み・回転）を合わせた NSTextView を
/// 枠の位置に重ねる。確定したら TextFrame に書き戻す。
extension CanvasView {

    /// 差し込みの枠は文面がテンプレートで決まるので、直接は打たせない
    func canEditDirectly(_ element: Element) -> Bool {
        guard let text = element.textFrame else { return false }
        return !element.locked && !element.hidden && !text.isDynamic
    }

    func beginEditing(_ id: UUID) {
        guard let state,
              let element = state.currentBoard.elements.first(where: { $0.id == id }),
              let frame = element.textFrame, canEditDirectly(element) else { return }

        commitEditing()

        let host = NSView(frame: .zero)
        host.wantsLayer = true

        let textView = NSTextView(frame: .zero)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        // 地はシステム色ではなく紙の色にする。
        // でないと、紙の上で読める濃さの文字が編集中だけ読めなくなる。
        let paper = NSColor(cgColor: state.settings.background.cgColor) ?? .textBackgroundColor
        textView.backgroundColor = paper.withAlphaComponent(0.97)
        textView.insertionPointColor = NSColor(cgColor: frame.color.cgColor) ?? .textColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.delegate = self

        // 見た目を合わせる
        let size = max(frame.fontSize * zoom, 2)
        textView.font = NSFont(name: frame.fontName, size: size) ?? .systemFont(ofSize: size)
        textView.textColor = NSColor(cgColor: frame.color.cgColor) ?? .textColor
        textView.alignment = frame.alignment.nsAlignment
        if frame.vertical { textView.setLayoutOrientation(.vertical) }

        let style = NSMutableParagraphStyle()
        style.alignment = frame.alignment.nsAlignment
        style.minimumLineHeight = size * frame.lineHeightScale
        style.maximumLineHeight = size * frame.lineHeightScale
        textView.defaultParagraphStyle = style
        var typing: [NSAttributedString.Key: Any] = [
            .font: textView.font as Any,
            .foregroundColor: textView.textColor as Any,
            .paragraphStyle: style,
        ]
        if frame.tracking != 0 { typing[.kern] = frame.tracking * zoom }
        textView.typingAttributes = typing
        textView.string = frame.text

        // 編集中だと分かる枠
        host.layer?.borderWidth = 1
        host.layer?.borderColor = NSColor.controlAccentColor.cgColor
        host.layer?.cornerRadius = 2

        host.addSubview(textView)
        addSubview(host)
        editorHost = host
        editor = textView
        editingID = id

        layoutEditor()
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: (frame.text as NSString).length))
        needsDisplay = true
    }

    /// ズームやスクロールに追従させる
    func layoutEditor() {
        guard let host = editorHost, let textView = editor, let state, let id = editingID,
              let element = state.currentBoard.elements.first(where: { $0.id == id }) else { return }
        let rect = element.rect.applying(docToView)
        host.frameCenterRotation = 0
        host.frame = rect
        textView.frame = host.bounds
        if element.rotation != 0 { host.frameCenterRotation = element.rotation }
    }

    /// 打ち込んだ内容を枠へ戻す
    func commitEditing() {
        guard let state, let id = editingID, let textView = editor else { return }
        let typed = textView.string
        editor = nil
        editorHost?.removeFromSuperview()
        editorHost = nil
        editingID = nil

        if let current = state.currentBoard.elements.first(where: { $0.id == id })?.textFrame,
           current.text != typed {
            state.beginUndoGroup()
            state.update(id: id) {
                if case .text(var f) = $0 { f.text = typed; $0 = .text(f) }
            }
        }
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    /// 打った内容を捨てて閉じる
    func cancelEditing() {
        editor = nil
        editorHost?.removeFromSuperview()
        editorHost = nil
        editingID = nil
        needsDisplay = true
        window?.makeFirstResponder(self)
    }
}

extension CanvasView: NSTextViewDelegate {
    public func textDidEndEditing(_ notification: Notification) {
        commitEditing()
    }

    public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            cancelEditing()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // ⌘Return で確定、素の Return は改行
            if NSEvent.modifierFlags.contains(.command) { commitEditing(); return true }
            return false
        default:
            return false
        }
    }
}

extension TextAlign {
    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: .left; case .center: .center; case .right: .right; case .justified: .justified
        }
    }
}
