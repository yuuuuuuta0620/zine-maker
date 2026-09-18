import AppKit
import UniformTypeIdentifiers
import Combine
import CoreGraphics

/// 誌面キャンバス。描画は CanvasRenderer に委ね、ここは座標変換と操作だけを持つ。
///
/// 修飾キーの取り決め（一般的なデザインツールに合わせている）
///   ⇧  比率を保つ／軸を固定する
///   ⌥  中心から広げる（リサイズ時）／画面をパンする（何もない所から）
///   ⌃  吸着を一時的に切る
///   ⌘  枠内の写真を動かす
final class CanvasView: NSView {

    var state: AppState? { didSet { observe() } }
    private var cancellables: Set<AnyCancellable> = []

    private(set) var zoom: CGFloat = 1
    private var pan: CGPoint = .zero
    private var userAdjusted = false
    private var lastFitToken = -1

    private var snapLinesX: [CGFloat] = []
    private var snapLinesY: [CGFloat] = []
    private var dropTargetID: UUID?
    private var marquee: CGRect?
    private var cursorDocPoint: CGPoint?

    private let rulerThickness: CGFloat = 18

    enum Handle: CaseIterable { case nw, n, ne, e, se, s, sw, w }

    private enum Drag {
        case none
        case move(origin: [UUID: CGRect], start: CGPoint)
        case resize(handle: Handle, origin: CGRect, rotation: CGFloat, start: CGPoint, id: UUID)
        case rotate(id: UUID, center: CGPoint, startAngle: CGFloat, original: CGFloat)
        case content(origin: CGPoint, start: CGPoint)
        case pan(start: CGPoint, origin: CGPoint)
        case marquee(start: CGPoint, additive: Bool)
        case guideLine(vertical: Bool, index: Int)
    }
    private var drag: Drag = .none

    override var isFlipped: Bool { false }          // y-up。CG / PDF と揃える
    override var acceptsFirstResponder: Bool { true }

    /// 非アクティブなウィンドウへの1クリック目も、ただの前面化で終わらせずに操作として扱う。
    /// 他のアプリから戻ってきて写真を掴むまでに2回クリックさせない。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .zineAsset])
        NotificationCenter.default.addObserver(
            self, selector: #selector(imagesLoaded), name: ImageStore.didLoad, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func imagesLoaded() { needsDisplay = true }

    private func observe() {
        cancellables.removeAll()
        guard let state else { return }
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &cancellables)
        state.$fitToken
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                guard let self, token != self.lastFitToken else { return }
                self.lastFitToken = token
                self.userAdjusted = false
                self.fitToView()
            }
            .store(in: &cancellables)
    }

    // MARK: - 座標系

    private var rulerSize: CGFloat { (state?.showRulers ?? true) ? rulerThickness : 0 }

    /// 定規を除いた実際の作図領域
    private var contentArea: CGRect {
        CGRect(x: rulerSize, y: 0, width: max(bounds.width - rulerSize, 1), height: max(bounds.height - rulerSize, 1))
    }

    private var docToView: CGAffineTransform {
        CGAffineTransform(translationX: pan.x, y: pan.y).scaledBy(x: zoom, y: zoom)
    }

    private func docPoint(_ viewPoint: CGPoint) -> CGPoint { viewPoint.applying(docToView.inverted()) }
    private func viewPoint(_ docPoint: CGPoint) -> CGPoint { docPoint.applying(docToView) }

    func fitToView() {
        guard let settings = state?.settings else { return }
        let media = settings.mediaBox
        let area = contentArea
        guard media.width > 0, area.width > 40 else { return }
        let padding: CGFloat = 56
        zoom = min((area.width - padding) / media.width, (area.height - padding) / media.height)
        pan = CGPoint(x: area.minX + (area.width - media.width * zoom) / 2 - media.minX * zoom,
                      y: area.minY + (area.height - media.height * zoom) / 2 - media.minY * zoom)
        needsDisplay = true
    }

    func setZoom(_ newZoom: CGFloat, around point: CGPoint) {
        userAdjusted = true
        let clamped = max(0.02, min(newZoom, 32))
        let before = docPoint(point)
        zoom = clamped
        let after = docPoint(point)
        pan.x += (after.x - before.x) * zoom
        pan.y += (after.y - before.y) * zoom
        needsDisplay = true
    }

    func zoomIn()  { setZoom(zoom * 1.25, around: CGPoint(x: contentArea.midX, y: contentArea.midY)) }
    func zoomOut() { setZoom(zoom / 1.25, around: CGPoint(x: contentArea.midX, y: contentArea.midY)) }
    func zoomActual() { setZoom(1, around: CGPoint(x: contentArea.midX, y: contentArea.midY)) }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !userAdjusted, newSize.width > 100 { fitToView() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let state, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let settings = state.settings

        // キャンバスの地の明るさは設定から
        let level = CGFloat(Preferences.shared.canvasBrightness)
        ctx.setFillColor(CGColor(gray: level * 0.35, alpha: 1))
        ctx.fill(bounds)

        ctx.saveGState()
        ctx.clip(to: contentArea)
        ctx.saveGState()
        ctx.concatenate(docToView)

        ctx.setShadow(offset: CGSize(width: 0, height: -3 / zoom), blur: 18 / zoom,
                      color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(settings.background.cgColor)
        ctx.fill(settings.mediaBox)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        CanvasRenderer.draw(state.currentBoard, settings: settings, scene: state.currentScene, in: ctx,
                            options: .init(guides: true,
                                           showColumns: state.showColumns,
                                           showCustomGuides: state.showCustomGuides,
                                           quality: .screen(maxPixel: screenMaxPixel),
                                           hairline: 1 / zoom))
        ctx.restoreGState()

        drawSnapLines(in: ctx)
        drawSelection(in: ctx)
        drawDropTarget(in: ctx)
        drawMarquee(in: ctx)
        ctx.restoreGState()

        if rulerSize > 0 { drawRulers(in: ctx) }
    }

    private var screenMaxPixel: Int {
        let backing = window?.backingScaleFactor ?? 2
        let onScreenLongEdge = max(bounds.width, bounds.height) * backing
        let quality = CGFloat(Preferences.shared.screenQuality)
        return min(8192, max(512, Int(onScreenLongEdge * quality * min(max(zoom, 0.2), 4) / max(zoom, 0.02) * zoom)))
    }

    // MARK: 定規

    /// 目盛りが 6px 以上離れるように刻みを選ぶ
    private func rulerStep() -> (step: CGFloat, labelEvery: Int) {
        guard let settings = state?.settings else { return (72, 1) }
        let isMM = settings.kind == .zine
        let candidates: [CGFloat] = isMM
            ? [1, 2, 5, 10, 20, 50, 100, 200].map(Pt.fromMM)
            : [10, 25, 50, 100, 250, 500, 1000, 2500]
        for c in candidates where c * zoom >= 7 { return (c, c * zoom >= 48 ? 1 : 5) }
        return (candidates.last ?? 72, 1)
    }

    private func rulerLabel(_ value: CGFloat) -> String {
        guard let settings = state?.settings else { return "" }
        return settings.kind == .zine ? "\(Int(Pt.toMM(value).rounded()))" : "\(Int(value.rounded()))"
    }

    private func drawRulers(in ctx: CGContext) {
        guard let settings = state?.settings else { return }
        let origin = settings.trimBox.origin          // 仕上がり左下を 0 とする
        let (step, labelEvery) = rulerStep()
        let top = bounds.height - rulerSize

        ctx.saveGState()
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(CGRect(x: 0, y: top, width: bounds.width, height: rulerSize))
        ctx.fill(CGRect(x: 0, y: 0, width: rulerSize, height: bounds.height))
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 0, y: top)); ctx.addLine(to: CGPoint(x: bounds.width, y: top))
        ctx.move(to: CGPoint(x: rulerSize, y: 0)); ctx.addLine(to: CGPoint(x: rulerSize, y: bounds.height))
        ctx.strokePath()

        let tickColor = NSColor.secondaryLabelColor.cgColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        // 上の定規（X）
        ctx.setStrokeColor(tickColor)
        ctx.setLineWidth(1)
        var i = Int(floor((docPoint(CGPoint(x: rulerSize, y: 0)).x - origin.x) / step))
        let maxI = Int(ceil((docPoint(CGPoint(x: bounds.width, y: 0)).x - origin.x) / step))
        while i <= maxI {
            let docX = origin.x + CGFloat(i) * step
            let x = viewPoint(CGPoint(x: docX, y: 0)).x
            if x >= rulerSize {
                let major = i % labelEvery == 0
                ctx.move(to: CGPoint(x: x, y: top))
                ctx.addLine(to: CGPoint(x: x, y: top + (major ? rulerSize * 0.5 : rulerSize * 0.28)))
                if major {
                    NSAttributedString(string: rulerLabel(CGFloat(i) * step), attributes: attrs)
                        .draw(at: CGPoint(x: x + 2, y: top + 3))
                }
            }
            i += 1
        }
        ctx.strokePath()

        // 左の定規（Y）— 上端を 0 として下向きに増やす（インスペクタの Y と揃える）
        ctx.setStrokeColor(tickColor)
        let trimTop = settings.trimBox.maxY
        var j = Int(floor((trimTop - docPoint(CGPoint(x: 0, y: bounds.height)).y) / step))
        let maxJ = Int(ceil((trimTop - docPoint(CGPoint(x: 0, y: 0)).y) / step))
        while j <= maxJ {
            let docY = trimTop - CGFloat(j) * step
            let y = viewPoint(CGPoint(x: 0, y: docY)).y
            if y <= top {
                let major = j % labelEvery == 0
                ctx.move(to: CGPoint(x: rulerSize, y: y))
                ctx.addLine(to: CGPoint(x: rulerSize - (major ? rulerSize * 0.5 : rulerSize * 0.28), y: y))
                if major {
                    let text = NSAttributedString(string: rulerLabel(CGFloat(j) * step), attributes: attrs)
                    ctx.saveGState()
                    ctx.translateBy(x: 8, y: y - 2)
                    ctx.rotate(by: -.pi / 2)
                    text.draw(at: CGPoint(x: -text.size().width - 2, y: 0))
                    ctx.restoreGState()
                }
            }
            j += 1
        }
        ctx.strokePath()

        // カーソル位置
        if let p = cursorDocPoint {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1)
            let v = viewPoint(p)
            ctx.move(to: CGPoint(x: v.x, y: top)); ctx.addLine(to: CGPoint(x: v.x, y: bounds.height))
            ctx.move(to: CGPoint(x: 0, y: v.y)); ctx.addLine(to: CGPoint(x: rulerSize, y: v.y))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: 選択表示

    private func drawSelection(in ctx: CGContext) {
        guard let state, !state.selection.isEmpty else { return }
        let accent = NSColor.controlAccentColor.cgColor

        ctx.saveGState()
        for element in state.selectedElements {
            ctx.saveGState()
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(state.selection.count > 1 ? 1 : 1.5)
            let path = CGMutablePath()
            path.addRect(element.rect, transform: element.transform.concatenating(docToView))
            ctx.addPath(path)
            ctx.strokePath()

            if let text = element.textFrame, CanvasRenderer.textOverflows(text, scene: state.currentScene) {
                ctx.setStrokeColor(CGColor(srgbRed: 0.95, green: 0.3, blue: 0.25, alpha: 1))
                ctx.setLineWidth(2.5)
                ctx.addPath(path)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }

        if let single = state.singleSelection {
            for (_, box) in handleRects(for: single) {
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(box)
                ctx.setStrokeColor(accent)
                ctx.setLineWidth(1.5)
                ctx.stroke(box)
            }
            // 回転ハンドル
            let r = rotationHandle(for: single)
            let anchor = viewFor(single, local: CGPoint(x: single.rect.midX, y: single.rect.maxY))
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1)
            ctx.move(to: anchor); ctx.addLine(to: CGPoint(x: r.midX, y: r.midY))
            ctx.strokePath()
            ctx.setFillColor(accent)
            ctx.fillEllipse(in: r)
        } else if let bounds = state.selectionBounds {
            let rect = bounds.applying(docToView)
            ctx.setStrokeColor(accent.copy(alpha: 0.5) ?? accent)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(rect)
            ctx.setLineDash(phase: 0, lengths: [])
        }
        ctx.restoreGState()
    }

    /// 要素のローカル座標をビュー座標へ（回転込み）
    private func viewFor(_ element: Element, local: CGPoint) -> CGPoint {
        local.applying(element.transform).applying(docToView)
    }

    private func handleRects(for element: Element) -> [(Handle, CGRect)] {
        let r = element.rect
        let s: CGFloat = 9
        func box(_ local: CGPoint) -> CGRect {
            let v = viewFor(element, local: local)
            return CGRect(x: v.x - s / 2, y: v.y - s / 2, width: s, height: s)
        }
        return [
            (.sw, box(CGPoint(x: r.minX, y: r.minY))), (.s, box(CGPoint(x: r.midX, y: r.minY))),
            (.se, box(CGPoint(x: r.maxX, y: r.minY))), (.w, box(CGPoint(x: r.minX, y: r.midY))),
            (.e,  box(CGPoint(x: r.maxX, y: r.midY))), (.nw, box(CGPoint(x: r.minX, y: r.maxY))),
            (.n,  box(CGPoint(x: r.midX, y: r.maxY))), (.ne, box(CGPoint(x: r.maxX, y: r.maxY))),
        ]
    }

    private func rotationHandle(for element: Element) -> CGRect {
        let top = viewFor(element, local: CGPoint(x: element.rect.midX, y: element.rect.maxY))
        let center = viewFor(element, local: CGPoint(x: element.rect.midX, y: element.rect.midY))
        var dir = CGPoint(x: top.x - center.x, y: top.y - center.y)
        let len = max(sqrt(dir.x * dir.x + dir.y * dir.y), 0.001)
        dir = CGPoint(x: dir.x / len, y: dir.y / len)
        let p = CGPoint(x: top.x + dir.x * 20, y: top.y + dir.y * 20)
        return CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
    }

    private func drawSnapLines(in ctx: CGContext) {
        guard !snapLinesX.isEmpty || !snapLinesY.isEmpty else { return }
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 0.25, blue: 0.5, alpha: 0.9))
        ctx.setLineWidth(1)
        for x in snapLinesX {
            let vx = viewPoint(CGPoint(x: x, y: 0)).x
            ctx.move(to: CGPoint(x: vx, y: 0)); ctx.addLine(to: CGPoint(x: vx, y: bounds.height))
        }
        for y in snapLinesY {
            let vy = viewPoint(CGPoint(x: 0, y: y)).y
            ctx.move(to: CGPoint(x: 0, y: vy)); ctx.addLine(to: CGPoint(x: bounds.width, y: vy))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawDropTarget(in ctx: CGContext) {
        guard let id = dropTargetID, let state,
              let element = state.currentBoard.elements.first(where: { $0.id == id }) else { return }
        let path = CGMutablePath()
        path.addRect(element.rect, transform: element.transform.concatenating(docToView))
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(3)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawMarquee(in ctx: CGContext) {
        guard let marquee else { return }
        ctx.saveGState()
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
        ctx.fill(marquee)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(marquee)
        ctx.restoreGState()
    }

    // MARK: - ガイドの当たり判定

    /// ビュー座標の近くにあるガイドを探す
    private func guideHit(_ p: CGPoint) -> (vertical: Bool, index: Int)? {
        guard let state, state.showCustomGuides else { return nil }
        let tolerance: CGFloat = 4
        for (i, x) in state.settings.verticalGuideXs.enumerated()
        where abs(viewPoint(CGPoint(x: x, y: 0)).x - p.x) <= tolerance { return (true, i) }
        for (i, y) in state.settings.horizontalGuideYs.enumerated()
        where abs(viewPoint(CGPoint(x: 0, y: y)).y - p.y) <= tolerance { return (false, i) }
        return nil
    }

    private func guidePosition(_ doc: CGPoint, vertical: Bool) -> Double {
        guard let trim = state?.settings.trimBox, trim.width > 0, trim.height > 0 else { return 0 }
        return vertical ? Double((doc.x - trim.minX) / trim.width)
                        : Double((doc.y - trim.minY) / trim.height)
    }

    // MARK: - マウス

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        cursorDocPoint = docPoint(p)
        if rulerSize > 0 { needsDisplay = true }
        updateCursor(at: p)
    }

    private func updateCursor(at p: CGPoint) {
        if p.x < rulerSize || p.y > bounds.height - rulerSize {
            NSCursor.arrow.set(); return
        }
        if guideHit(p) != nil {
            (guideHit(p)!.vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set(); return
        }
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let state else { return }
        let vp = convert(event.locationInWindow, from: nil)
        let point = docPoint(vp)
        let additive = event.modifierFlags.contains(.shift)

        // 定規からドラッグしてガイドを作る（上＝横ガイド／左＝縦ガイド）
        if rulerSize > 0, vp.y > bounds.height - rulerSize {
            state.addGuide(vertical: false, at: guidePosition(point, vertical: false))
            drag = .guideLine(vertical: false, index: state.settings.horizontalGuides.count - 1)
            return
        }
        if rulerSize > 0, vp.x < rulerSize {
            state.addGuide(vertical: true, at: guidePosition(point, vertical: true))
            drag = .guideLine(vertical: true, index: state.settings.verticalGuides.count - 1)
            return
        }

        // 既にあるガイドをつかむ
        if let hit = guideHit(vp) {
            state.beginUndoGroup()
            drag = .guideLine(vertical: hit.vertical, index: hit.index)
            return
        }

        if event.modifierFlags.contains(.option), !event.modifierFlags.contains(.command),
           state.singleSelection == nil || !handleHit(vp) {
            drag = .pan(start: vp, origin: pan)
            return
        }

        if let single = state.singleSelection, !single.locked {
            if rotationHandle(for: single).contains(vp) {
                state.beginUndoGroup()
                let center = viewFor(single, local: CGPoint(x: single.rect.midX, y: single.rect.midY))
                drag = .rotate(id: single.id, center: center,
                               startAngle: atan2(vp.y - center.y, vp.x - center.x),
                               original: single.rotation)
                return
            }
            for (handle, box) in handleRects(for: single) where box.contains(vp) {
                state.beginUndoGroup()
                drag = .resize(handle: handle, origin: single.rect, rotation: single.rotation,
                               start: point, id: single.id)
                return
            }
        }

        // ロックと非表示は掴めない
        guard let hit = state.currentBoard.elements.last(where: {
            !$0.locked && !$0.hidden && $0.contains(point)
        }) else {
            if !additive { state.selection.removeAll() }
            drag = .marquee(start: point, additive: additive)
            needsDisplay = true
            return
        }

        if additive {
            state.select(hit.id, additive: true)
            drag = .none
        } else {
            if !state.selection.contains(hit.id) { state.selection = [hit.id] }
            state.beginUndoGroup()
            if event.modifierFlags.contains(.command), hit.imageFrame != nil {
                drag = .content(origin: hit.imageFrame!.contentOffset, start: point)
            } else {
                drag = .move(origin: Dictionary(uniqueKeysWithValues:
                    state.selectedElements.map { ($0.id, $0.rect) }), start: point)
            }
        }
        needsDisplay = true
    }

    private func handleHit(_ vp: CGPoint) -> Bool {
        guard let single = state?.singleSelection else { return false }
        return handleRects(for: single).contains { $0.1.contains(vp) } || rotationHandle(for: single).contains(vp)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state else { return }
        let vp = convert(event.locationInWindow, from: nil)
        let point = docPoint(vp)
        let noSnap = event.modifierFlags.contains(.control) || !state.snapEnabled
        let constrain = event.modifierFlags.contains(.shift)
        let fromCenter = event.modifierFlags.contains(.option)

        switch drag {
        case .none: break

        case .guideLine(let vertical, let index):
            state.moveGuide(vertical: vertical, index: index,
                            to: guidePosition(point, vertical: vertical))
            needsDisplay = true

        case .pan(let start, let origin):
            userAdjusted = true
            pan = CGPoint(x: origin.x + vp.x - start.x, y: origin.y + vp.y - start.y)
            needsDisplay = true

        case .move(let origins, let start):
            var dx = point.x - start.x, dy = point.y - start.y
            if constrain { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
            if let anchor = unionOf(origins.values) {
                let moved = anchor.offsetBy(dx: dx, dy: dy)
                if !noSnap {
                    let (sdx, sdy) = snapDelta(for: moved, excluding: Set(origins.keys))
                    dx += sdx; dy += sdy
                } else {
                    snapLinesX = []; snapLinesY = []
                }
                if state.gridStep > 0 {
                    let g = state.gridStep
                    dx = ((anchor.minX + dx) / g).rounded() * g - anchor.minX
                    dy = ((anchor.minY + dy) / g).rounded() * g - anchor.minY
                }
            }
            for (id, origin) in origins {
                state.update(id: id) { $0.rect = origin.offsetBy(dx: dx, dy: dy) }
            }

        case .resize(let handle, let origin, let rotation, let start, let id):
            let rect = resizedRect(handle: handle, origin: origin, rotation: rotation,
                                   start: start, current: point,
                                   constrain: constrain, fromCenter: fromCenter,
                                   snap: !noSnap && rotation == 0, excluding: [id])
            state.update(id: id) { $0.rect = rect }

        case .rotate(let id, let center, let startAngle, let original):
            let angle = atan2(vp.y - center.y, vp.x - center.x)
            var degrees = original + (angle - startAngle) * 180 / .pi
            if constrain { degrees = (degrees / 15).rounded() * 15 }
            state.update(id: id) { $0.rotation = degrees.truncatingRemainder(dividingBy: 360) }

        case .content(let origin, let start):
            state.updateSelected { element in
                if case .image(var f) = element {
                    f.contentOffset = CGPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y)
                    element = .image(f)
                }
            }

        case .marquee(let start, let additive):
            let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y))
            marquee = rect.applying(docToView)
            let hits = state.currentBoard.elements
                .filter { !$0.locked && !$0.hidden && $0.boundingRect.intersects(rect) }.map(\.id)
            state.selection = additive ? state.selection.union(hits) : Set(hits)
            needsDisplay = true
        }
    }

    /// 回転している枠も正しく掴めるリサイズ。
    /// ローカル座標で矩形を作り直したうえで、掴んでいない側の角が画面上で動かないように平行移動する。
    private func resizedRect(handle: Handle, origin: CGRect, rotation: CGFloat,
                             start: CGPoint, current: CGPoint,
                             constrain: Bool, fromCenter: Bool,
                             snap: Bool, excluding: Set<UUID>) -> CGRect {
        let a = -rotation * .pi / 180
        let rawDX = current.x - start.x, rawDY = current.y - start.y
        var dx = rawDX * cos(a) - rawDY * sin(a)
        var dy = rawDX * sin(a) + rawDY * cos(a)
        if fromCenter { dx *= 2; dy *= 2 }

        var rect = origin
        switch handle {
        case .nw: rect = CGRect(x: origin.minX + dx, y: origin.minY, width: origin.width - dx, height: origin.height + dy)
        case .n:  rect.size.height += dy
        case .ne: rect.size.width += dx; rect.size.height += dy
        case .e:  rect.size.width += dx
        case .se: rect = CGRect(x: origin.minX, y: origin.minY + dy, width: origin.width + dx, height: origin.height - dy)
        case .s:  rect = CGRect(x: origin.minX, y: origin.minY + dy, width: origin.width, height: origin.height - dy)
        case .sw: rect = CGRect(x: origin.minX + dx, y: origin.minY + dy, width: origin.width - dx, height: origin.height - dy)
        case .w:  rect = CGRect(x: origin.minX + dx, y: origin.minY, width: origin.width - dx, height: origin.height)
        }
        rect = rect.standardized
        rect.size.width = max(rect.width, 8)
        rect.size.height = max(rect.height, 8)

        // ⇧ で元の縦横比を保つ
        if constrain, origin.width > 0, origin.height > 0 {
            let ratio = origin.width / origin.height
            if rect.width / rect.height > ratio { rect.size.width = rect.height * ratio }
            else { rect.size.height = rect.width / ratio }
        }

        if fromCenter {
            rect.origin = CGPoint(x: origin.midX - rect.width / 2, y: origin.midY - rect.height / 2)
        } else {
            // 掴んでいない角を固定する
            let anchorLocal = oppositeCorner(handle, of: origin)
            switch handle {
            case .nw, .w: rect.origin.x = anchorLocal.x - rect.width
            case .ne, .e, .n, .s: rect.origin.x = anchorLocal.x
            case .se: rect.origin.x = anchorLocal.x
            case .sw: rect.origin.x = anchorLocal.x - rect.width
            }
            switch handle {
            case .se, .s, .sw: rect.origin.y = anchorLocal.y - rect.height
            default: rect.origin.y = anchorLocal.y
            }
        }

        if snap {
            let (sdx, sdy) = snapDelta(for: rect, excluding: excluding)
            rect = rect.offsetBy(dx: sdx, dy: sdy)
        } else {
            snapLinesX = []; snapLinesY = []
        }

        // 回転している場合、固定したい角が画面上でずれないように補正する
        if rotation != 0, !fromCenter {
            let anchorLocal = oppositeCorner(handle, of: origin)
            let originCenter = CGPoint(x: origin.midX, y: origin.midY)
            let anchorView = rotate(anchorLocal, around: originCenter, by: rotation)
            let newCenter = CGPoint(x: rect.midX, y: rect.midY)
            let mapped = rotate(anchorLocal, around: newCenter, by: rotation)
            rect = rect.offsetBy(dx: anchorView.x - mapped.x, dy: anchorView.y - mapped.y)
        }
        return rect
    }

    private func oppositeCorner(_ handle: Handle, of r: CGRect) -> CGPoint {
        switch handle {
        case .nw: CGPoint(x: r.maxX, y: r.minY)
        case .n:  CGPoint(x: r.minX, y: r.minY)
        case .ne: CGPoint(x: r.minX, y: r.minY)
        case .e:  CGPoint(x: r.minX, y: r.minY)
        case .se: CGPoint(x: r.minX, y: r.maxY)
        case .s:  CGPoint(x: r.minX, y: r.maxY)
        case .sw: CGPoint(x: r.maxX, y: r.maxY)
        case .w:  CGPoint(x: r.maxX, y: r.minY)
        }
    }

    private func rotate(_ p: CGPoint, around c: CGPoint, by degrees: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * cos(a) - dy * sin(a), y: c.y + dx * sin(a) + dy * cos(a))
    }

    override func mouseUp(with event: NSEvent) {
        // ガイドを定規へ戻したら削除
        if case .guideLine(let vertical, let index) = drag {
            let vp = convert(event.locationInWindow, from: nil)
            if vp.x < rulerSize || vp.y > bounds.height - rulerSize || !contentArea.insetBy(dx: -40, dy: -40).contains(vp) {
                state?.removeGuide(vertical: vertical, index: index)
            }
        }
        drag = .none
        snapLinesX = []; snapLinesY = []
        marquee = nil
        needsDisplay = true
    }

    private func unionOf(_ rects: Dictionary<UUID, CGRect>.Values) -> CGRect? {
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    // MARK: - 吸着

    private func snapDelta(for rect: CGRect, excluding: Set<UUID>) -> (CGFloat, CGFloat) {
        guard let state else { return (0, 0) }
        let threshold = 7 / zoom
        let settings = state.settings
        let trim = settings.trimBox

        var xs: [CGFloat] = [trim.minX, trim.midX, trim.maxX]
        var ys: [CGFloat] = [trim.minY, trim.midY, trim.maxY]
        if settings.kind == .zine {
            xs += [settings.mediaBox.minX, settings.mediaBox.maxX]
            ys += [settings.mediaBox.minY, settings.mediaBox.maxY]
        }
        for page in 0..<settings.pagesPerSpread {
            let box = settings.marginBox(page)
            xs += [box.minX, box.midX, box.maxX]
            ys += [box.minY, box.midY, box.maxY]
        }
        if state.showCustomGuides {
            xs += settings.verticalGuideXs
            ys += settings.horizontalGuideYs
        }
        if state.showColumns {
            xs += settings.columnSnapXs
            ys += settings.columnSnapYs
        }
        for element in state.currentBoard.elements where !excluding.contains(element.id) && !element.hidden {
            let r = element.boundingRect
            xs += [r.minX, r.midX, r.maxX]
            ys += [r.minY, r.midY, r.maxY]
        }

        let (dx, hitX) = bestDelta([rect.minX, rect.midX, rect.maxX], xs, threshold)
        let (dy, hitY) = bestDelta([rect.minY, rect.midY, rect.maxY], ys, threshold)
        snapLinesX = hitX.map { [$0] } ?? []
        snapLinesY = hitY.map { [$0] } ?? []
        return (dx, dy)
    }

    private func bestDelta(_ edges: [CGFloat], _ guides: [CGFloat], _ threshold: CGFloat) -> (CGFloat, CGFloat?) {
        var best: CGFloat = 0
        var bestGuide: CGFloat?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for edge in edges {
            for guideValue in guides {
                let delta = guideValue - edge
                if abs(delta) <= threshold, abs(delta) < bestDistance {
                    bestDistance = abs(delta); best = delta; bestGuide = guideValue
                }
            }
        }
        return (best, bestGuide)
    }

    // MARK: - スクロール・ズーム

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            setZoom(zoom * (1 + event.scrollingDeltaY * 0.01), around: convert(event.locationInWindow, from: nil))
        } else if event.modifierFlags.contains(.option), let state, !state.selection.isEmpty {
            state.updateSelected { element in
                if case .image(var f) = element {
                    f.contentScale = max(0.05, min(f.contentScale * (1 + event.scrollingDeltaY * 0.01), 20))
                    element = .image(f)
                }
            }
        } else {
            userAdjusted = true
            pan.x += event.scrollingDeltaX
            pan.y -= event.scrollingDeltaY
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), around: convert(event.locationInWindow, from: nil))
    }

    // MARK: - キーボード

    override func keyDown(with event: NSEvent) {
        guard let state else { return super.keyDown(with: event) }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1

        switch event.keyCode {
        case 51, 117: state.deleteSelected()
        case 123: nudge(dx: -step, dy: 0)
        case 124: nudge(dx: step, dy: 0)
        case 125: nudge(dx: 0, dy: -step)
        case 126: nudge(dx: 0, dy: step)
        case 53:  state.selection.removeAll()
        default: super.keyDown(with: event)
        }
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let state, !state.selection.isEmpty else { return }
        state.beginUndoGroup()
        state.updateSelected { $0.rect = $0.rect.offsetBy(dx: dx, dy: dy) }
    }

    // MARK: - ドラッグ&ドロップ

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDropTarget(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDropTarget(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropTargetID = nil; needsDisplay = true }

    private func updateDropTarget(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = docPoint(convert(sender.draggingLocation, from: nil))
        dropTargetID = state?.currentBoard.elements
            .last { $0.imageFrame != nil && !$0.locked && !$0.hidden && $0.contains(point) }?.id
        needsDisplay = true
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropTargetID = nil; needsDisplay = true }
        guard let state else { return false }
        let point = docPoint(convert(sender.draggingLocation, from: nil))
        let pb = sender.draggingPasteboard
        let targetID = state.currentBoard.elements
            .last { $0.imageFrame != nil && !$0.locked && !$0.hidden && $0.contains(point) }?.id

        if let raw = pb.string(forType: .zineAsset) {
            let ids = raw.split(separator: "\n").compactMap { UUID(uuidString: String($0)) }
            guard !ids.isEmpty else { return false }
            state.beginUndoGroup()
            if let targetID {
                state.update(id: targetID) {
                    if case .image(var f) = $0 { f.assetID = ids[0]; f.contentOffset = .zero; f.contentScale = 1; $0 = .image(f) }
                }
                state.selection = [targetID]
            } else {
                state.addImageFrame(assetID: ids[0], at: point)
            }
            return true
        }

        guard let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] else { return false }
        let readable = Set(ImageStore.readableTypes.map(\.identifier))
        let images = urls.filter { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
                .flatMap { readable.contains($0) } ?? false
        }
        guard !images.isEmpty else { return false }
        let added = state.importPhotos(urls: images)
        if let first = added.first {
            if let targetID {
                state.update(id: targetID) { if case .image(var f) = $0 { f.assetID = first.id; $0 = .image(f) } }
            } else {
                state.addImageFrame(assetID: first.id, at: point)
            }
        }
        return true
    }
}
