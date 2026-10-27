import AppKit

/// A small sketch note that drops from the menu bar icon, e.g. "Muted. Protection is back on."
final class MenuBarToast {
    private var panel: NSPanel?
    private var view: ToastView?
    private var hide: DispatchWorkItem?
    var onClick: (() -> Void)?

    func show(title: String, detail: String, below icon: NSRect?) {
        let titleWidth = NSAttributedString(string: title, attributes: [.font: Style.font(13, .bold)]).size().width
        if let notch = Notch.current {
            // A short black island out of the notch.
            let frame = Notch.frame(for: NSSize(width: max(notch.width + 40, ceil(titleWidth) + 36 + 12 + 40), height: notch.height + 50), notch: notch)
            let panel = Notch.panel(frame: frame)
            let view = ToastView(title: title, detail: "", tailX: 0, notch: notch.size)
            present(panel: panel, view: view, announcement: title)
            return
        }
        let size = detail.isEmpty ? NSSize(width: max(176, ceil(titleWidth) + 40 + 14 + 24 + 26), height: 84) : NSSize(width: 360, height: 104)
        let screen = NSScreen.screens.first { icon.map($0.frame.intersects) ?? false } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = icon ?? NSRect(x: visible.maxX - 120, y: visible.maxY, width: 22, height: 22)
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let frame = NSRect(x: x, y: anchor.minY - 4 - size.height, width: size.width, height: size.height)
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]; p.appearance = NSAppearance(named: .aqua)
            p.isReleasedWhenClosed = false
            return p
        }()
        let view = ToastView(title: title, detail: detail, tailX: anchor.midX - x)
        panel.setFrame(frame, display: true)
        present(panel: panel, view: view, announcement: "\(title) \(detail)")
    }
    private func present(panel: NSPanel, view: ToastView, announcement: String) {
        if let old = self.panel, old !== panel { old.orderOut(nil) }
        view.onClick = { [weak self] in self?.dismiss(); self?.onClick?() }
        view.onHover = { [weak self] inside in inside ? self?.hide?.cancel() : self?.scheduleHide(after: 1.4) }
        panel.contentView = view
        self.panel = panel; self.view = view
        panel.orderFrontRegardless()
        view.popIn()
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        scheduleHide(after: 3.2)
    }
    private func scheduleHide(after seconds: Double) {
        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
    func dismiss() {
        hide?.cancel()
        guard let panel, let view else { return }
        view.popOut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if self?.view === view { panel.orderOut(nil) }
        }
    }
}

final class ToastView: NSView {
    let title: String, detail: String, tailX: CGFloat
    let notch: NSSize?
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private lazy var pop = Spring { [weak self] in self?.needsDisplay = true }
    init(title: String, detail: String, tailX: CGFloat, notch: NSSize? = nil) {
        self.title = title; self.detail = detail; self.tailX = tailX; self.notch = notch
        super.init(frame: .zero)
        trackHover()
        setAccessibilityRole(.button); setAccessibilityLabel(detail.isEmpty ? "\(title) Open AlwaysMute" : "\(title) \(detail) Open AlwaysMute")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    func popIn() { pop.jump(to: 0); pop.animate(to: 1) }
    func popOut() { pop.animate(to: 0) }
    override func draw(_ dirtyRect: NSRect) {
        let v = pop.value
        if let notch {
            Notch.drawIsland(in: bounds, notch: notch, progress: v)
            let alpha = Notch.contentAlpha(v)
            guard alpha > 0 else { return }
            let art: CGFloat = 36, midY = notch.height + (bounds.height - notch.height) / 2 - 3
            Artwork.mascot(size: art, muted: true).draw(in: NSRect(x: Notch.ear + 14, y: midY - art / 2, width: art, height: art), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            let heading = NSAttributedString(string: title, attributes: [.font: Style.font(13.5, .bold), .foregroundColor: Artwork.ink.withAlphaComponent(alpha)])
            heading.draw(at: NSPoint(x: Notch.ear + 14 + art + 12, y: midY - heading.size().height / 2))
            return
        }
        guard v > 0.02 else { return }
        // Margins leave room for the springy overshoot and the hatched shadow, so nothing clips at the panel edge.
        let body = NSRect(x: 10, y: 16, width: bounds.width - 24, height: bounds.height - 32)
        let tip = NSPoint(x: min(max(tailX, body.minX + 22), body.maxX - 22), y: 4)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(min(1, v))
        // Grows out of the tail tip, as if dropping from the menu bar icon.
        let t = NSAffineTransform(); t.translateX(by: tip.x, yBy: tip.y); t.scale(by: 0.6 + 0.4 * min(v, 1.04)); t.translateX(by: -tip.x, yBy: -tip.y); t.concat()
        let shape = NSBezierPath(roundedRect: body, xRadius: 14, yRadius: 14)
        Artwork.hatchShadow(shape, offset: NSSize(width: 3, height: 5))
        Artwork.sheet.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip(); Artwork.paperGrain(body, strength: 0.7); NSGraphicsContext.restoreGraphicsState()
        Artwork.sketch(shape, width: 1.5, seed: 81)
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: tip.x - 9, y: body.minY + 1.5)); tail.line(to: tip); tail.line(to: NSPoint(x: tip.x + 9, y: body.minY + 1.5)); tail.close()
        Artwork.sheet.setFill(); tail.fill()
        let edges = NSBezierPath(); edges.move(to: NSPoint(x: tip.x - 9, y: body.minY + 0.5)); edges.line(to: tip); edges.line(to: NSPoint(x: tip.x + 9, y: body.minY + 0.5))
        Artwork.sketch(edges, width: 1.5, seed: 83)
        // Title-only notes are compact: smaller mascot and type.
        let compact = detail.isEmpty, art: CGFloat = compact ? 40 : 54
        Artwork.mascot(size: art, muted: true).draw(in: NSRect(x: body.minX + 6, y: body.midY - art / 2 - 1, width: art, height: art), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let heading = NSAttributedString(string: title, attributes: [.font: Style.font(compact ? 13 : 14.5, .bold), .foregroundColor: Artwork.ink])
        let sub = NSAttributedString(string: detail, attributes: [.font: Style.font(12), .foregroundColor: Style.muted])
        // A title-only note sits centred; the detail line is optional.
        let textX = body.minX + art + 14, total = heading.size().height + (detail.isEmpty ? 0 : sub.size().height)
        heading.draw(at: NSPoint(x: textX, y: body.midY - total / 2))
        sub.draw(with: NSRect(x: textX, y: body.midY - total / 2 + heading.size().height, width: body.maxX - textX - 12, height: sub.size().height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
    }
}
