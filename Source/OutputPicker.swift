import AppKit

/// The address-bar dropdown from the sketch reference: output devices, a sliding sky highlight, and a link to Sound settings.
final class OutputPicker: NSObject {
    private var panel: NSPanel?
    private var list: PickerList?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private weak var anchor: NSView?
    var onClose: (() -> Void)?
    var isOpen: Bool { panel != nil }

    func show(from anchor: NSView, choices: [OutputChoice], onPick: @escaping (OutputChoice) -> Void) {
        close()
        guard let parent = anchor.window else { return }
        self.anchor = anchor
        let anchorRect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let list = PickerList(choices: choices)
        let size = NSSize(width: anchorRect.width + 12, height: list.preferredHeight)
        list.frame = NSRect(origin: .zero, size: size)
        let panel = NSPanel(contentRect: NSRect(x: anchorRect.minX - 6, y: anchorRect.minY - 2 - size.height, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true; panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = list
        list.onPick = { [weak self] choice in self?.close(); onPick(choice) }
        list.onSettings = { [weak self] in
            self?.close()
            let pane = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!
            if !NSWorkspace.shared.open(pane) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.sound")!) }
        }
        parent.addChildWindow(panel, ordered: .above)
        self.panel = panel; self.list = list
        list.appear()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                switch event.keyCode {
                case 53: self.close(); return nil
                case 125: self.list?.move(1); return nil
                case 126: self.list?.move(-1); return nil
                case 36, 76, 49: self.list?.pickHighlighted(); return nil
                default: return event
                }
            }
            if event.window === panel { return event }
            // A click on the pill itself just closes, rather than closing and reopening.
            if let anchor = self.anchor, event.window === anchor.window, anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) { self.close(); return nil }
            self.close(); return event
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in self?.close() })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.close() })
    }
    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
        self.panel = nil; list = nil
        onClose?()
    }
}

final class PickerList: NSView {
    let choices: [OutputChoice]
    var onPick: ((OutputChoice) -> Void)?
    var onSettings: (() -> Void)?
    static let rowHeight: CGFloat = 40, pad: CGFloat = 6
    /// Rows are the choices plus the trailing "Sound settings…" row.
    private var hover: Int? { didSet { if hover != oldValue { slideHighlight() } } }
    private lazy var highlightY = Spring { [weak self] in self?.needsDisplay = true }
    private lazy var highlightAlpha = Spring { [weak self] in self?.needsDisplay = true }
    private lazy var shown = Spring { [weak self] in self?.needsDisplay = true }
    init(choices: [OutputChoice]) {
        self.choices = choices
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityRole(.menu); setAccessibilityLabel("Audio outputs")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var rowCount: Int { max(1, choices.count) + 1 }
    var preferredHeight: CGFloat { SketchCard.top + Self.pad * 2 + CGFloat(rowCount) * Self.rowHeight + 9 + (SketchCard.extra - SketchCard.top) }
    private var body: NSRect { NSRect(x: 2, y: SketchCard.top, width: bounds.width - 7, height: bounds.height - SketchCard.extra) }
    private func rowRect(_ index: Int) -> NSRect {
        let settingsGap: CGFloat = index == rowCount - 1 ? 9 : 0
        return NSRect(x: body.minX, y: body.minY + Self.pad + CGFloat(index) * Self.rowHeight + settingsGap, width: body.width, height: Self.rowHeight)
    }
    private func row(at point: NSPoint) -> Int? {
        (0..<rowCount).first { rowRect($0).contains(point) && !(choices.isEmpty && $0 == 0) }
    }
    func appear() {
        let current = choices.firstIndex { $0.current } ?? 0
        hover = choices.isEmpty ? nil : current
        shown.animate(to: 1)
    }
    private func slideHighlight() {
        guard let hover else { highlightAlpha.animate(to: 0); return }
        let target = rowRect(hover).minY
        if highlightAlpha.value < 0.05 { highlightY.jump(to: target) } else { highlightY.animate(to: target) }
        highlightAlpha.animate(to: 1)
    }
    func move(_ delta: Int) {
        let selectable = Array(choices.isEmpty ? [rowCount - 1] : Array(0..<rowCount))
        let index = hover.flatMap { selectable.firstIndex(of: $0) } ?? (delta > 0 ? -1 : selectable.count)
        hover = selectable[max(0, min(selectable.count - 1, index + delta))]
    }
    func pickHighlighted() {
        guard let hover else { return }
        if hover == rowCount - 1 { onSettings?() } else if choices.indices.contains(hover) { onPick?(choices[hover]) }
    }
    override func mouseMoved(with event: NSEvent) { hover = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hover = choices.firstIndex { $0.current } }
    override func mouseDown(with event: NSEvent) {
        hover = row(at: convert(event.locationInWindow, from: nil))
        pickHighlighted()
    }
    override func draw(_ dirtyRect: NSRect) {
        let v = shown.value
        guard v > 0.01 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(min(1, v))
        let drop = NSAffineTransform(); drop.translateX(by: 0, yBy: -10 * (1 - v)); drop.concat()
        let shape = NSBezierPath(roundedRect: body, xRadius: 11, yRadius: 11)
        Artwork.hatchShadow(shape, offset: NSSize(width: 3, height: 6))
        Artwork.sheet.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        Artwork.paperGrain(body, strength: 0.7)
        if highlightAlpha.value > 0.01 {
            let r = NSRect(x: body.minX + 6, y: highlightY.value + 3, width: body.width - 12, height: Self.rowHeight - 6)
            Artwork.sky.withAlphaComponent(min(1, highlightAlpha.value)).setFill(); NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        if choices.isEmpty {
            draw(symbol: "speaker.slash", text: "No outputs found", in: rowRect(0), font: Style.font(13, .medium), color: Style.muted)
        }
        for (index, choice) in choices.enumerated() {
            let r = rowRect(index)
            let trailing: CGFloat = choice.current ? 34 : !choice.controllable ? 118 : 16
            draw(symbol: choice.symbol, text: choice.name, in: r, font: Style.mono(13, choice.current ? .bold : .medium), color: Artwork.ink.withAlphaComponent(choice.controllable ? 1 : 0.6), trailing: trailing)
            if choice.current {
                let tick = NSBezierPath(), x = r.maxX - 28, y = r.midY
                tick.move(to: NSPoint(x: x, y: y)); tick.line(to: NSPoint(x: x + 4, y: y + 4)); tick.line(to: NSPoint(x: x + 11, y: y - 5))
                Artwork.coral.setStroke(); tick.lineWidth = 2.2; tick.lineCapStyle = .round; tick.lineJoinStyle = .round; tick.stroke()
            } else if !choice.controllable {
                let note = NSAttributedString(string: "no volume control", attributes: [.font: Style.font(11), .foregroundColor: Style.muted])
                note.draw(at: NSPoint(x: r.maxX - 16 - note.size().width, y: r.midY - note.size().height / 2))
            }
        }
        // Divider, then the Sound settings row.
        let settings = rowRect(rowCount - 1)
        let line = NSBezierPath(); line.move(to: NSPoint(x: body.minX + 14, y: settings.minY - 4.5)); line.line(to: NSPoint(x: body.maxX - 14, y: settings.minY - 4.5))
        Artwork.sketch(line, width: 0.8, color: Artwork.ink.withAlphaComponent(0.25), seed: 71)
        draw(symbol: "gearshape", text: "Sound settings…", in: settings, font: Style.font(13, .medium), color: Artwork.ink)
        Artwork.sketch(shape, width: 1.5, seed: 73)
        NSGraphicsContext.restoreGraphicsState()
    }
    private func draw(symbol: String, text: String, in r: NSRect, font: NSFont, color: NSColor, trailing: CGFloat = 16) {
        if let image = Style.symbol(symbol, size: 13) {
            let s = image.size, box = NSRect(x: r.minX + 16 + (18 - s.width) / 2, y: r.midY - s.height / 2, width: s.width, height: s.height)
            Style.tinted(image, color).draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        let h = label.size().height
        label.draw(with: NSRect(x: r.minX + 44, y: r.midY - h / 2, width: r.width - 44 - trailing, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
