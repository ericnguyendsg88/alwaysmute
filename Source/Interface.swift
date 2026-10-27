import AppKit

enum Style {
    static let canvas = Artwork.paper
    static let green = NSColor(calibratedRed: 0.29, green: 0.45, blue: 0.31, alpha: 1)
    static let warning = NSColor(calibratedRed: 0.80, green: 0.42, blue: 0.14, alpha: 1)
    static let muted = Artwork.ink.withAlphaComponent(0.62)
    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let name = weight == .regular ? "AvenirNext-Regular" : weight == .medium ? "AvenirNext-Medium" : weight == .bold ? "AvenirNext-Bold" : "AvenirNext-DemiBold"
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont { .monospacedSystemFont(ofSize: size, weight: weight) }
    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let v = NSTextField(labelWithString: text); v.font = font(size, weight); v.textColor = color == .labelColor ? Artwork.ink : color; return v
    }
    static func wrapping(_ text: String, size: CGFloat = 12, color: NSColor = muted) -> NSTextField {
        let v = NSTextField(wrappingLabelWithString: text); v.font = font(size); v.textColor = color; v.isSelectable = false; return v
    }
    static func icon(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Artwork.ink) -> NSImageView {
        let v = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: weight)) ?? NSImage())
        v.contentTintColor = color; v.setContentHuggingPriority(.required, for: .horizontal); return v
    }
    static func protectedSpeaker(size: CGFloat, muted: Bool = true) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // A filled protection shield with the speaker cut out of its center.
            let shield = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * rect.width, y: y * rect.height) }
            shield.move(to: point(0.5, 0.96))
            shield.curve(to: point(0.86, 0.81), controlPoint1: point(0.63, 0.92), controlPoint2: point(0.86, 0.86))
            shield.line(to: point(0.86, 0.44))
            shield.curve(to: point(0.5, 0.04), controlPoint1: point(0.86, 0.25), controlPoint2: point(0.67, 0.12))
            shield.curve(to: point(0.14, 0.44), controlPoint1: point(0.33, 0.12), controlPoint2: point(0.14, 0.25))
            shield.line(to: point(0.14, 0.81))
            shield.curve(to: point(0.5, 0.96), controlPoint1: point(0.14, 0.86), controlPoint2: point(0.37, 0.92))
            shield.close(); NSColor.black.setFill(); shield.fill()
            if let speaker = symbol(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: size) {
                let box = NSRect(x: size * 0.28, y: size * 0.30, width: size * 0.44, height: size * 0.44)
                speaker.draw(in: box, from: .zero, operation: .destinationOut, fraction: 1)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    /// Menu bar glyph: the mascot's silhouette (antenna, rounded body, feet) with the speaker cut out of its body.
    static func mascotGlyph(height: CGFloat = 18, muted: Bool = true) -> NSImage {
        let size = NSSize(width: height * 22 / 22, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let t = NSAffineTransform(); t.scale(by: rect.height / 22); t.concat()
            NSColor.black.setFill(); NSColor.black.setStroke()
            let antenna = NSBezierPath(); antenna.move(to: NSPoint(x: 12, y: 16)); antenna.line(to: NSPoint(x: 13.6, y: 19.2)); antenna.lineWidth = 1.5; antenna.lineCapStyle = .round; antenna.stroke()
            NSBezierPath(ovalIn: NSRect(x: 12.3, y: 18.6, width: 3.2, height: 3.2)).fill()
            NSBezierPath(roundedRect: NSRect(x: 2.5, y: 4, width: 17, height: 13), xRadius: 4.5, yRadius: 4.5).fill()
            NSBezierPath(roundedRect: NSRect(x: 5.5, y: 0.8, width: 4.2, height: 2.6), xRadius: 1.3, yRadius: 1.3).fill()
            NSBezierPath(roundedRect: NSRect(x: 12.3, y: 0.8, width: 4.2, height: 2.6), xRadius: 1.3, yRadius: 1.3).fill()
            let legs = NSBezierPath(); legs.move(to: NSPoint(x: 7.6, y: 2.5)); legs.line(to: NSPoint(x: 7.6, y: 4.5)); legs.move(to: NSPoint(x: 14.4, y: 2.5)); legs.line(to: NSPoint(x: 14.4, y: 4.5)); legs.lineWidth = 1.4; legs.stroke()
            if let speaker = symbol(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 22) {
                let box = NSRect(x: 5, y: 5.6, width: 12, height: 9.8)
                speaker.draw(in: box, from: .zero, operation: .destinationOut, fraction: 1)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .medium))
    }
    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect); color.setFill(); rect.fill(using: .sourceIn); return true
        }
        return result
    }
}

// MARK: - Motion

/// Small damped spring that drives hover lifts and pops. Slightly underdamped so things settle with a little bounce.
final class Spring {
    private(set) var value: CGFloat
    private var velocity: CGFloat = 0, target: CGFloat
    private var timer: Timer?
    var stiffness: CGFloat = 360, damping: CGFloat = 17
    private let onChange: () -> Void
    init(_ value: CGFloat = 0, onChange: @escaping () -> Void) { self.value = value; target = value; self.onChange = onChange }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func animate(to newTarget: CGFloat) {
        target = newTarget
        if reduceMotion { value = newTarget; velocity = 0; onChange(); return }
        run()
    }
    func jump(to newValue: CGFloat) { timer?.invalidate(); timer = nil; value = newValue; target = newValue; velocity = 0; onChange() }
    /// Adds velocity without moving the rest point, for hops and bounces.
    func kick(_ impulse: CGFloat) { guard !reduceMotion else { return }; velocity += impulse; run() }
    private func run() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    private func step() {
        let dt: CGFloat = 1.0 / 120
        velocity += (-stiffness * (value - target) - damping * velocity) * dt
        value += velocity * dt
        if abs(value - target) < 0.002 && abs(velocity) < 0.02 { value = target; velocity = 0; timer?.invalidate(); timer = nil }
        onChange()
    }
    deinit { timer?.invalidate() }
}
extension NSView {
    func trackHover() { addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)) }
}

// MARK: - Window chrome

/// Borderless window whose whole shape is the hand-drawn frame.
final class SketchWindow: NSWindow {
    let frameView: SketchFrame
    let allowsResize: Bool
    /// The size the layout was designed at; the green dot returns here.
    let designSize: NSSize
    init(title: String, size: NSSize, footer: CGFloat, resizable: Bool = false, minimum: NSSize? = nil) {
        designSize = size
        frameView = SketchFrame(tab: title, footer: footer)
        self.allowsResize = resizable
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: resizable ? [.borderless, .closable, .miniaturizable, .resizable] : [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
        self.title = title
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        isMovableByWindowBackground = true; isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)
        contentMinSize = minimum ?? size; contentMaxSize = resizable ? NSSize(width: 900, height: 1100) : size
        contentView = frameView; frameView.installChrome(resizable: resizable)
        center()
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { close() }
    /// Lets the content claim Esc (for example to mean "Keep muted") before it closes the window.
    var onEscape: (() -> Bool)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { close() }
        else if event.keyCode == 53 { if onEscape?() != true { close() } } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { if onEscape?() != true { close() } }
    /// Where collapsed windows fly to: the menu bar icon's frame on screen. Set by the app delegate.
    static var menuBarTarget: (() -> NSRect?)?
    private(set) var collapsed = false
    private var ghost: NSWindow?
    /// A borderless stand-in showing a snapshot of this window, used for the fly-in and fly-out.
    private func makeGhost() -> NSWindow? {
        guard let view = contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size); image.addRepresentation(rep)
        let ghost = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        ghost.isOpaque = false; ghost.backgroundColor = .clear; ghost.hasShadow = false; ghost.ignoresMouseEvents = true; ghost.level = level; ghost.isReleasedWhenClosed = false
        let imageView = NSImageView(image: image); imageView.imageScaling = .scaleProportionallyUpOrDown
        ghost.contentView = imageView
        return ghost
    }
    /// A small rect at the menu bar icon with this window's proportions.
    private var iconRect: NSRect {
        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? .zero
        let icon = Self.menuBarTarget?() ?? NSRect(x: screenFrame.midX - 11, y: screenFrame.maxY - 24, width: 22, height: 22)
        let height: CGFloat = 22, width = height * frame.width / max(1, frame.height)
        return NSRect(x: icon.midX - width / 2, y: icon.midY - height / 2, width: width, height: height)
    }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Shrinks the window into the menu bar icon and hides it. The app keeps protecting in the background.
    func collapseToMenuBar() {
        guard isVisible, !collapsed else { return }
        collapsed = true
        guard !reduceMotion, let ghost = makeGhost() else { orderOut(nil); return }
        self.ghost?.orderOut(nil); self.ghost = ghost
        ghost.orderFront(nil); orderOut(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.38; ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.9, 0.4)
            ghost.animator().setFrame(iconRect, display: true); ghost.animator().alphaValue = 0.15
        }, completionHandler: { [weak self] in ghost.orderOut(nil); if self?.ghost === ghost { self?.ghost = nil } })
    }
    /// Shows the window, growing it back out of the menu bar icon if it was collapsed there.
    func present() {
        guard collapsed else { makeKeyAndOrderFront(nil); return }
        collapsed = false
        guard !reduceMotion, let ghost = makeGhost() else { makeKeyAndOrderFront(nil); return }
        self.ghost?.orderOut(nil); self.ghost = ghost
        let target = frame
        ghost.setFrame(iconRect, display: false); ghost.alphaValue = 0.15; ghost.orderFront(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.34; ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.05)
            ghost.animator().setFrame(target, display: true); ghost.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.makeKeyAndOrderFront(nil); ghost.orderOut(nil)
            if self?.ghost === ghost { self?.ghost = nil }
        })
    }
    /// Green dot: toggle between the compact size and a roomier one, keeping the top-left corner in place.
    func toggleRoomy() {
        guard allowsResize else { return }
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        let compact = designSize
        let roomy = NSSize(width: min(compact.width + 220, visible.width, contentMaxSize.width), height: min(compact.height + 140, visible.height, contentMaxSize.height))
        let target = abs(frame.width - compact.width) < 2 && abs(frame.height - compact.height) < 2 ? roomy : compact
        var next = frame; next.origin.y += next.height - target.height; next.size = target
        setFrame(next, display: true, animate: true)
    }
}

/// Browser-style paper frame: tan title band with a tab, a toolbar strip, paper body and a grey footer band.
final class SketchFrame: NSView {
    static let band: CGFloat = 42, toolbar: CGFloat = 54
    static let inset = NSEdgeInsets(top: 12, left: 16, bottom: 22, right: 16)
    let tab: String
    let footer: CGFloat
    init(tab: String, footer: CGFloat) { self.tab = tab; self.footer = footer; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    var onResize: ((NSSize) -> Void)?
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsDisplay = true; onResize?(newSize) }
    var sheet: NSRect { NSRect(x: Self.inset.left, y: Self.inset.top, width: bounds.width - Self.inset.left - Self.inset.right, height: bounds.height - Self.inset.top - Self.inset.bottom) }
    /// Top of the page body, below band and toolbar, in this view's coordinates.
    static var contentTop: CGFloat { inset.top + band + toolbar }
    var toolbarRect: NSRect { NSRect(x: sheet.minX, y: sheet.minY + Self.band, width: sheet.width, height: Self.toolbar) }
    func installChrome(resizable: Bool) {
        let colors = [NSColor(calibratedRed: 0.88, green: 0.37, blue: 0.33, alpha: 1), NSColor(calibratedRed: 0.93, green: 0.73, blue: 0.29, alpha: 1), NSColor(calibratedRed: 0.42, green: 0.68, blue: 0.36, alpha: 1)]
        for (index, color) in colors.enumerated() {
            let dot = WindowDot(color: color, kind: index)
            dot.isEnabled = index != 2 || resizable
            dot.frame = NSRect(x: Self.inset.left + 13 + CGFloat(index) * 20, y: Self.inset.top + (Self.band - 18) / 2, width: 18, height: 18)
            addSubview(dot)
        }
        guard resizable else { return }
        let grip = ResizeGrip(); grip.translatesAutoresizingMaskIntoConstraints = false; addSubview(grip)
        NSLayoutConstraint.activate([grip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(Self.inset.right + 3)), grip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(Self.inset.bottom + 3)), grip.widthAnchor.constraint(equalToConstant: 16), grip.heightAnchor.constraint(equalToConstant: 16)])
    }
    private var tabPath: NSBezierPath {
        let s = sheet, width = min(200, s.width * 0.46)
        let left = s.minX + 78, top = s.minY + 8, bottom = s.minY + Self.band + 0.5, slant: CGFloat = 9, r: CGFloat = 7
        let p = NSBezierPath()
        p.move(to: NSPoint(x: left - 2, y: bottom))
        p.line(to: NSPoint(x: left + slant - 2, y: top + r))
        p.curve(to: NSPoint(x: left + slant + r, y: top), controlPoint1: NSPoint(x: left + slant, y: top + 2), controlPoint2: NSPoint(x: left + slant + 2, y: top))
        p.line(to: NSPoint(x: left + width - slant - r, y: top))
        p.curve(to: NSPoint(x: left + width - slant + 2, y: top + r), controlPoint1: NSPoint(x: left + width - slant - 2, y: top), controlPoint2: NSPoint(x: left + width - slant, y: top + 2))
        p.line(to: NSPoint(x: left + width + 2, y: bottom))
        return p
    }
    override func draw(_ dirtyRect: NSRect) {
        let s = sheet
        let outline = NSBezierPath(roundedRect: s, xRadius: 16, yRadius: 16)
        // Soft cast shadow under the sheet.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = Artwork.ink.withAlphaComponent(0.22); shadow.shadowBlurRadius = 9; shadow.shadowOffset = NSSize(width: 2, height: -4); shadow.set()
        Artwork.sheet.setFill(); outline.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); outline.addClip()
        Artwork.sheet.setFill(); s.fill()
        let band = NSRect(x: s.minX, y: s.minY, width: s.width, height: Self.band)
        Artwork.band.setFill(); band.fill()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.18), ending: NSColor.clear)!.draw(in: band, angle: 90)
        NSGradient(starting: Artwork.sheet, ending: Artwork.paper)!.draw(in: toolbarRect, angle: 90)
        let body = NSRect(x: s.minX, y: toolbarRect.maxY, width: s.width, height: s.maxY - toolbarRect.maxY)
        NSGradient(starting: Artwork.paper, ending: Artwork.sheet)!.draw(in: body, angle: 90)
        // Grey footer band, fading in from the page like the reference's bottom bar.
        if footer > 0 {
            let foot = NSRect(x: s.minX, y: s.maxY - footer, width: s.width, height: footer)
            Artwork.footer.setFill(); foot.fill()
            NSGradient(starting: Artwork.paper.withAlphaComponent(0), ending: Artwork.footer)!.draw(in: NSRect(x: s.minX, y: foot.minY - 18, width: s.width, height: 18), angle: 90)
            NSColor.white.withAlphaComponent(0.75).setFill(); NSRect(x: s.minX, y: foot.minY, width: s.width, height: 1.2).fill()
            Artwork.ink.withAlphaComponent(0.12).setFill(); NSRect(x: s.minX, y: foot.minY - 0.6, width: s.width, height: 0.6).fill()
        }
        // Tab, merged into the toolbar below it.
        let tab = tabPath
        let tabFill = tab.copy() as! NSBezierPath; tabFill.close()
        Artwork.sheet.setFill(); tabFill.fill()
        Artwork.paperGrain(s, strength: 1)
        let rule = NSBezierPath(); rule.move(to: NSPoint(x: s.minX, y: band.maxY)); rule.line(to: NSPoint(x: tab.bounds.minX, y: band.maxY))
        rule.move(to: NSPoint(x: tab.bounds.maxX, y: band.maxY)); rule.line(to: NSPoint(x: s.maxX, y: band.maxY))
        Artwork.sketch(rule, width: 1.2, seed: 3)
        Artwork.sketch(tab, width: 1.5, seed: 5)
        let square = NSBezierPath(roundedRect: NSRect(x: tab.bounds.minX + 24, y: s.minY + 20, width: 11, height: 11), xRadius: 3, yRadius: 3)
        Artwork.coral.setFill(); square.fill()
        let title = NSAttributedString(string: self.tab, attributes: [.font: Style.font(13.5, .medium), .foregroundColor: Artwork.ink.withAlphaComponent(0.85)])
        title.draw(at: NSPoint(x: tab.bounds.minX + 43, y: s.minY + 16.5))
        let toolRule = NSBezierPath(); toolRule.move(to: NSPoint(x: s.minX, y: toolbarRect.maxY)); toolRule.line(to: NSPoint(x: s.maxX, y: toolbarRect.maxY))
        Artwork.sketch(toolRule, width: 1.0, color: Artwork.ink.withAlphaComponent(0.7), seed: 9)
        NSGraphicsContext.restoreGraphicsState()
        Artwork.sketch(outline, width: 2.1, seed: 1)
    }
}

final class WindowDot: NSButton {
    let color: NSColor
    let kind: Int
    private lazy var pop = Spring { [weak self] in self?.needsDisplay = true }
    init(color: NSColor, kind: Int) {
        self.color = color; self.kind = kind; super.init(frame: .zero)
        isBordered = false; title = ""; target = self; action = #selector(activate)
        setAccessibilityLabel(["Close", "Hide to menu bar", "Resize"][kind])
        trackHover()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseEntered(with event: NSEvent) { if isEnabled { pop.animate(to: 1) } }
    override func mouseExited(with event: NSEvent) { pop.animate(to: 0) }
    @objc func activate() {
        switch kind {
        case 0: window?.performClose(nil)
        case 1: (window as? SketchWindow)?.collapseToMenuBar()
        default: (window as? SketchWindow)?.toggleRoomy()
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let d = 12 * (1 + 0.2 * pop.value)
        let circle = NSBezierPath(ovalIn: NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d))
        color.withAlphaComponent(isEnabled ? (isHighlighted ? 0.75 : 1) : 0.45).setFill(); circle.fill()
        Artwork.ink.withAlphaComponent(isEnabled ? 1 : 0.5).setStroke(); circle.lineWidth = 1.3; circle.stroke()
        NSColor.white.withAlphaComponent(0.45).setFill(); NSBezierPath(ovalIn: NSRect(x: bounds.midX - d * 0.22, y: bounds.midY - d * 0.3, width: d * 0.3, height: d * 0.22)).fill()
        guard pop.value > 0.3 && isEnabled else { return }
        let glyph = NSBezierPath(), c = NSPoint(x: bounds.midX, y: bounds.midY), g = d * 0.22
        switch kind {
        case 0: glyph.move(to: NSPoint(x: c.x - g, y: c.y - g)); glyph.line(to: NSPoint(x: c.x + g, y: c.y + g)); glyph.move(to: NSPoint(x: c.x + g, y: c.y - g)); glyph.line(to: NSPoint(x: c.x - g, y: c.y + g))
        case 1: glyph.move(to: NSPoint(x: c.x - g * 1.2, y: c.y)); glyph.line(to: NSPoint(x: c.x + g * 1.2, y: c.y))
        default: glyph.move(to: NSPoint(x: c.x - g, y: c.y + g)); glyph.line(to: NSPoint(x: c.x + g, y: c.y - g)); glyph.move(to: NSPoint(x: c.x - g, y: c.y)); glyph.line(to: NSPoint(x: c.x - g, y: c.y + g)); glyph.line(to: NSPoint(x: c.x, y: c.y + g)); glyph.move(to: NSPoint(x: c.x + g, y: c.y)); glyph.line(to: NSPoint(x: c.x + g, y: c.y - g)); glyph.line(to: NSPoint(x: c.x, y: c.y - g))
        }
        Artwork.ink.withAlphaComponent(0.75 * min(1, pop.value)).setStroke(); glyph.lineWidth = 1.2; glyph.lineCapStyle = .round; glyph.stroke()
    }
}

/// Pencil-scratch corner grip for resizing the borderless window.
final class ResizeGrip: NSView {
    private lazy var pop = Spring { [weak self] in self?.needsDisplay = true }
    override init(frame: NSRect) { super.init(frame: frame); trackHover(); setAccessibilityLabel("Resize window"); toolTip = "Drag to resize" }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseEntered(with event: NSEvent) { pop.animate(to: 1) }
    override func mouseExited(with event: NSEvent) { pop.animate(to: 0) }
    override func resetCursorRects() {
        if #available(macOS 15.0, *) { addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all)) } else { addCursorRect(bounds, cursor: .crosshair) }
    }
    override func draw(_ dirtyRect: NSRect) {
        for (i, inset) in [3.0, 7.5, 12.0].enumerated() {
            let p = NSBezierPath(); p.move(to: NSPoint(x: bounds.maxX - 1, y: CGFloat(inset))); p.line(to: NSPoint(x: CGFloat(inset), y: bounds.maxY - 1))
            Artwork.ink.withAlphaComponent(0.35 + 0.45 * pop.value).setStroke(); p.lineWidth = 1.1; p.lineCapStyle = .round
            let shift = NSAffineTransform(); shift.translateX(by: -pop.value * CGFloat(i) * 0.6, yBy: -pop.value * CGFloat(i) * 0.6); p.transform(using: shift as AffineTransform)
            p.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = NSEvent.mouseLocation, origin = window.frame
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let now = NSEvent.mouseLocation
            let width = max(window.contentMinSize.width, min(window.contentMaxSize.width, origin.width + now.x - start.x))
            let height = max(window.contentMinSize.height, min(window.contentMaxSize.height, origin.height - (now.y - start.y)))
            window.setFrame(NSRect(x: origin.minX, y: origin.maxY - height, width: width, height: height), display: true)
            if next.type == .leftMouseUp { break }
        }
    }
}

// MARK: - Components

/// The address-bar pill. With `onClick` set it becomes a button with a chevron that tints on hover.
final class SketchPill: NSView {
    var onClick: (() -> Void)? { didSet { if onClick != nil && oldValue == nil { trackHover(); setAccessibilityRole(.button) } } }
    var open = false { didSet { chevron.animate(to: open ? 1 : 0) } }
    private lazy var hover = Spring { [weak self] in self?.needsDisplay = true }
    private lazy var chevron = Spring { [weak self] in self?.needsDisplay = true }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { onClick == nil }
    override func mouseEntered(with event: NSEvent) { hover.animate(to: 1) }
    override func mouseExited(with event: NSEvent) { hover.animate(to: 0) }
    override func mouseDown(with event: NSEvent) { if let onClick { hover.kick(-6); onClick() } else { super.mouseDown(with: event) } }
    override func accessibilityPerformPress() -> Bool { onClick?(); return onClick != nil }
    override func resetCursorRects() { if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: (bounds.height - 4) / 2, yRadius: (bounds.height - 4) / 2)
        Artwork.sheet.setFill(); pill.fill()
        NSColor.white.withAlphaComponent(0.5).setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 12, yRadius: 12).fill()
        let tint = max(hover.value, chevron.value)
        if tint > 0.01 { Artwork.sky.withAlphaComponent(0.8 * min(1, tint)).setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 13, yRadius: 13).fill() }
        Artwork.sketch(pill, width: 1.5, seed: 11)
        guard onClick != nil else { return }
        // Chevron flips up while the dropdown is open.
        let c = NSPoint(x: bounds.maxX - 22, y: bounds.midY + hover.value * 0.6), w: CGFloat = 4.5, h = 2.6 * (1 - 2 * chevron.value)
        let v = NSBezierPath(); v.move(to: NSPoint(x: c.x - w, y: c.y - h)); v.line(to: NSPoint(x: c.x, y: c.y + h)); v.line(to: NSPoint(x: c.x + w, y: c.y - h))
        Artwork.ink.setStroke(); v.lineWidth = 1.8; v.lineCapStyle = .round; v.lineJoinStyle = .round; v.stroke()
    }
}

/// Dropdown-style card: ink outline, hatched shadow, optional sky-blue highlighted row. Lifts off the page on hover.
final class SketchCard: NSView {
    static let top: CGFloat = 4, extra: CGFloat = 11
    let rows: [CGFloat]
    var highlighted: Int?
    var dividers = true
    private lazy var lift = Spring { [weak self] in self?.applyLift() }
    /// Row heights are proportions of the card body.
    init(rows: [CGFloat] = [1], highlighted: Int? = nil) { self.rows = rows; self.highlighted = highlighted; super.init(frame: .zero); trackHover() }
    convenience init(rows: Int, highlighted: Int? = nil) { self.init(rows: Array(repeating: 1, count: rows), highlighted: highlighted) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func mouseEntered(with event: NSEvent) { lift.animate(to: 1) }
    override func mouseExited(with event: NSEvent) { lift.animate(to: 0) }
    /// Shifting the bounds origin raises the card and its contents together; the shadow is drawn back in place.
    private func applyLift() { setBoundsOrigin(NSPoint(x: lift.value * 1, y: lift.value * 2.6)); needsDisplay = true }
    var body: NSRect { NSRect(x: 2, y: Self.top, width: bounds.width - 7, height: bounds.height - Self.extra) }
    func row(_ index: Int) -> NSRect {
        let unit = body.height / rows.reduce(0, +), top = rows[..<index].reduce(0, +) * unit
        return NSRect(x: body.minX, y: body.minY + top, width: body.width, height: rows[index] * unit)
    }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: body, xRadius: 9, yRadius: 9)
        Artwork.hatchShadow(shape, offset: NSSize(width: 3 + bounds.origin.x, height: 6 + bounds.origin.y), opacity: 0.42 + 0.12 * lift.value)
        Artwork.sheet.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        Artwork.paperGrain(body, strength: 0.7)
        if let highlighted {
            let r = row(highlighted).insetBy(dx: 6, dy: 5)
            let pill = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
            Artwork.sky.setFill(); pill.fill()
            Artwork.paperGrain(r, strength: 0.6)
        }
        if dividers {
            for index in 1..<max(1, rows.count) where index != highlighted && index - 1 != highlighted {
                let y = row(index).minY
                let line = NSBezierPath(); line.move(to: NSPoint(x: body.minX + 12, y: y)); line.line(to: NSPoint(x: body.maxX - 12, y: y))
                Artwork.sketch(line, width: 0.8, color: Artwork.ink.withAlphaComponent(0.25), seed: Double(index) * 3)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        Artwork.sketch(shape, width: 1.5, seed: 13)
    }
}

/// A hand-drawn level bar: hatched when empty, coral fill for the current level.
final class SketchMeter: NSView {
    var level: Double = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 1.5, dy: 1.5)
        let shape = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        Artwork.sheet.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        Artwork.hatch(in: track, opacity: 0.16, spacing: 3.5, width: 0.6)
        let filled = NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(max(0, min(1, level))), height: track.height)
        Artwork.coral.setFill(); filled.fill(); Artwork.paperGrain(filled)
        NSGraphicsContext.restoreGraphicsState()
        Artwork.sketch(shape, width: 1.1, seed: 17)
    }
}

/// Chunky sketch button. Rises on hover (its hatched shadow stays on the page), sinks when pressed, bounces on release.
final class PrimaryButton: NSButton {
    var tone = Artwork.coral { didSet { needsDisplay = true } }
    /// Keyboard hint drawn after the title, e.g. "⏎" or "⌘⏎".
    var shortcut: String? { didSet { needsDisplay = true } }
    /// Extra key hints after the shortcut: optional text (e.g. "⌘") followed by an SF Symbol key cap.
    var keyHints: [(prefix: String, symbol: String)] = [] { didSet { needsDisplay = true } }
    /// Key equivalents are ignored until this time, so a held or double-tapped shortcut can't skip a step unseen.
    var keysArmedAt = Date.distantPast
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !event.isARepeat, Date() >= keysArmedAt else { return false }
        return super.performKeyEquivalent(with: event)
    }
    private lazy var lift = Spring { [weak self] in self?.needsDisplay = true }
    override init(frame: NSRect) { super.init(frame: frame); trackHover() }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    /// Works on the first click, including inside panels that don't take focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { if isEnabled { lift.animate(to: 1) } }
    override func mouseExited(with event: NSEvent) { lift.animate(to: 0) }
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event); lift.kick(-9) }
    private func keyHintText(size: CGFloat, color: NSColor) -> NSAttributedString? {
        guard shortcut != nil || !keyHints.isEmpty else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [.font: Style.font(size, .medium), .foregroundColor: color]
        let text = NSMutableAttributedString(string: shortcut ?? "", attributes: attributes)
        for (index, hint) in keyHints.enumerated() {
            text.append(NSAttributedString(string: (index == 0 && shortcut == nil ? "" : "  ·  ") + hint.prefix, attributes: attributes))
            if let symbol = NSImage(systemSymbolName: hint.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size - 1, weight: .medium)) {
                let attachment = NSTextAttachment(); attachment.image = Style.tinted(symbol, color)
                attachment.bounds = NSRect(x: 0, y: -1.5, width: symbol.size.width, height: symbol.size.height)
                text.append(NSAttributedString(attachment: attachment))
            }
        }
        return text
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 2, y: 5, width: bounds.width - 7, height: bounds.height - 12)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        let rise = isHighlighted ? -1.5 : lift.value * 2.8
        if isEnabled { Artwork.hatchShadow(shape, offset: NSSize(width: 3, height: 6), opacity: 0.4 + 0.15 * lift.value) }
        let face = shape.copy() as! NSBezierPath
        let push = NSAffineTransform(); push.translateX(by: -rise * 0.35, yBy: -rise); face.transform(using: push as AffineTransform)
        (isEnabled ? tone : Artwork.band).setFill(); face.fill()
        NSGraphicsContext.saveGraphicsState(); face.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.16 + 0.08 * lift.value), ending: NSColor.clear)!.draw(in: face.bounds, angle: 90)
        Artwork.paperGrain(face.bounds, strength: 1.4)
        NSGraphicsContext.restoreGraphicsState()
        Artwork.sketch(face, width: 1.6, color: Artwork.ink.withAlphaComponent(isEnabled ? 1 : 0.45), seed: 21)
        let color = Artwork.ink.withAlphaComponent(isEnabled ? 1 : 0.45)
        // Title plus an optional key hint; shrink the type a little if a narrow window squeezes them.
        var fontSize: CGFloat = 15, text: NSAttributedString, hint: NSAttributedString?, width: CGFloat
        repeat {
            text = NSAttributedString(string: title, attributes: [.font: Style.font(fontSize, .semibold), .foregroundColor: color])
            hint = keyHintText(size: fontSize - 2, color: color.withAlphaComponent(0.55))
            width = text.size().width + (hint.map { $0.size().width + 8 } ?? 0)
            fontSize -= 0.5
        } while width > face.bounds.width - 24 && fontSize > 11
        let size = text.size(), x = face.bounds.midX - width / 2
        text.draw(at: NSPoint(x: x, y: face.bounds.midY - size.height / 2))
        if let hint { hint.draw(at: NSPoint(x: x + size.width + 8, y: face.bounds.midY - hint.size().height / 2)) }
    }
}

final class SketchCheckbox: NSButton {
    private lazy var lift = Spring { [weak self] in self?.needsDisplay = true }
    override init(frame: NSRect) { super.init(frame: frame); setButtonType(.switch); trackHover() }
    convenience init(title: String) { self.init(frame: .zero); self.title = title; font = Style.font(12.5, .medium) }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }
    override func mouseEntered(with event: NSEvent) { if isEnabled { lift.animate(to: 1) } }
    override func mouseExited(with event: NSEvent) { lift.animate(to: 0) }
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event); lift.kick(-12) }
    private var text: NSAttributedString { NSAttributedString(string: title, attributes: [.font: font ?? Style.font(12.5), .foregroundColor: Artwork.ink.withAlphaComponent(isEnabled ? 1 : 0.4)]) }
    override var intrinsicContentSize: NSSize { NSSize(width: 26 + ceil(text.size().width), height: 22) }
    override func draw(_ dirtyRect: NSRect) {
        let rise = lift.value * 1.8
        let base = NSRect(x: 1.5, y: bounds.midY - 7.5, width: 15, height: 15)
        if lift.value > 0.01 { Artwork.hatchShadow(NSBezierPath(roundedRect: base, xRadius: 4, yRadius: 4), offset: NSSize(width: 2, height: 3), opacity: 0.45 * min(1, lift.value)) }
        let box = base.offsetBy(dx: -rise * 0.3, dy: -rise)
        let shape = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        (state == .on ? Artwork.coral : Artwork.sheet).withAlphaComponent(isEnabled ? 1 : 0.5).setFill(); shape.fill()
        if isHighlighted { Artwork.ink.withAlphaComponent(0.1).setFill(); shape.fill() }
        Artwork.sketch(shape, width: 1.3, color: Artwork.ink.withAlphaComponent(isEnabled ? 1 : 0.4), seed: 25)
        if state == .on {
            let tick = NSBezierPath(); tick.move(to: NSPoint(x: box.minX + 3.5, y: box.midY + 0.5)); tick.line(to: NSPoint(x: box.minX + 6.5, y: box.maxY - 3.5)); tick.line(to: NSPoint(x: box.maxX - 2.5, y: box.minY + 3))
            Artwork.ink.setStroke(); tick.lineWidth = 1.9; tick.lineCapStyle = .round; tick.lineJoinStyle = .round; tick.stroke()
        }
        text.draw(at: NSPoint(x: 26, y: bounds.midY - text.size().height / 2))
    }
}

/// Text link with a pencil squiggle that draws itself in on hover.
final class SketchLink: NSButton {
    private var symbolName = ""
    private lazy var lift = Spring { [weak self] in self?.needsDisplay = true }
    convenience init(_ title: String, symbol: String, target: AnyObject?, action: Selector) {
        self.init(frame: .zero)
        self.title = title; symbolName = symbol; self.target = target; self.action = action; isBordered = false
        trackHover()
    }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseEntered(with event: NSEvent) { lift.animate(to: 1) }
    override func mouseExited(with event: NSEvent) { lift.animate(to: 0) }
    private var text: NSAttributedString { NSAttributedString(string: title, attributes: [.font: Style.font(12.5, .medium), .foregroundColor: Artwork.ink]) }
    override var intrinsicContentSize: NSSize { NSSize(width: 20 + ceil(text.size().width) + 4, height: 24) }
    override func draw(_ dirtyRect: NSRect) {
        let rise = lift.value * 1.5 + (isHighlighted ? -1 : 0)
        if let image = Style.symbol(symbolName, size: 12) {
            let size = image.size
            Style.tinted(image, Artwork.ink).draw(in: NSRect(x: 1, y: bounds.midY - size.height / 2 - rise - 1, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let t = text, origin = NSPoint(x: 20, y: bounds.midY - t.size().height / 2 - rise - 1)
        t.draw(at: origin)
        guard lift.value > 0.01 else { return }
        let length = t.size().width * min(1, lift.value), y = bounds.maxY - 3
        let squiggle = NSBezierPath(); squiggle.move(to: NSPoint(x: 20, y: y))
        var x: CGFloat = 20
        while x < 20 + length { x += 3; squiggle.line(to: NSPoint(x: min(x, 20 + length), y: y + (Int(x) % 6 < 3 ? -0.9 : 0.9))) }
        Artwork.coral.setStroke(); squiggle.lineWidth = 1.5; squiggle.lineCapStyle = .round; squiggle.lineJoinStyle = .round; squiggle.stroke()
    }
}

/// Toolbar icon button: a paper disc pops up behind the glyph on hover.
final class SketchIconButton: NSButton {
    private var symbolName = ""
    private lazy var pop = Spring { [weak self] in self?.needsDisplay = true }
    convenience init(symbol: String, target: AnyObject?, action: Selector) {
        self.init(frame: .zero); symbolName = symbol; self.target = target; self.action = action; isBordered = false; title = ""
        trackHover()
    }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 32) }
    override func mouseEntered(with event: NSEvent) { pop.animate(to: 1) }
    override func mouseExited(with event: NSEvent) { pop.animate(to: 0) }
    override func draw(_ dirtyRect: NSRect) {
        let v = pop.value, d = 26 * max(0, v)
        if d > 1 {
            let disc = NSBezierPath(ovalIn: NSRect(x: bounds.midX - d / 2 - 1, y: bounds.midY - d / 2 - 1, width: d, height: d))
            Artwork.hatchShadow(disc, offset: NSSize(width: 1.5, height: 2.5), opacity: 0.4 * min(1, v))
            (isHighlighted ? Artwork.sky : Artwork.sheet).setFill(); disc.fill()
            Artwork.sketch(disc, width: 1.3, color: Artwork.ink.withAlphaComponent(min(1, v)), seed: 41)
        }
        guard let image = Style.symbol(symbolName, size: 15) else { return }
        let size = image.size, rise = v * 1.2
        Style.tinted(image, Artwork.ink).draw(in: NSRect(x: bounds.midX - size.width / 2 - rise * 0.6, y: bounds.midY - size.height / 2 - rise, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// The mascot as a live view: hops when the pointer arrives or when clicked.
final class MascotView: NSView {
    var muted = true { didSet { needsDisplay = true } }
    var wave = false { didSet { needsDisplay = true } }
    /// Below this size the mascot isn't drawn (used when the main window folds up).
    var minimumSize: CGFloat = 56
    private lazy var hop = Spring { [weak self] in self?.needsDisplay = true }
    override init(frame: NSRect) { super.init(frame: frame); trackHover(); setAccessibilityElement(false) }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseEntered(with event: NSEvent) { hop.kick(22) }
    override func mouseDown(with event: NSEvent) { hop.kick(30) }
    func bounce() { hop.kick(26) }
    override func draw(_ dirtyRect: NSRect) {
        // Too small to read as a character; leave the space quiet instead.
        guard bounds.height >= minimumSize else { return }
        Artwork.mascot(size: bounds.width, muted: muted, lift: max(0, hop.value), wave: wave).draw(in: bounds)
    }
}

/// "🎧 Unplug = mute" chip: headphone protection is always on, whatever the mute state.
final class UnplugBadge: NSView {
    private let text = NSAttributedString(string: "Unplug = mute", attributes: [.font: Style.font(11.5, .semibold), .foregroundColor: Artwork.ink])
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Headphones unplugged or audio falls back to the speakers: AlwaysMute mutes instantly, even for trusted outputs."
        setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityLabel("Headphone protection on: unplugging mutes")
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 30 + ceil(text.size().width), height: 22) }
    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        Artwork.sheet.setFill(); pill.fill()
        Artwork.sketch(pill, width: 1.1, seed: 91)
        if let icon = Style.symbol("headphones", size: 11) {
            Style.tinted(icon, Artwork.ink).draw(in: NSRect(x: 9, y: bounds.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        text.draw(at: NSPoint(x: 24, y: bounds.midY - text.size().height / 2))
    }
}

// MARK: - Main window

final class QuietInterface {
    let window: SketchWindow
    let heading = Style.label("Speaker is muted.", size: 25, weight: .bold)
    let subtitle = Style.label("Sound only when you say so.", size: 13.5, color: Style.muted)
    let status = Style.label("Muted & protected", size: 13, weight: .semibold)
    let statusDot = NSView()
    let reason = Style.label("", size: 11, color: Style.muted)
    /// Always-on headphone protection, called out where the status lives.
    private let unplugBadge = UnplugBadge()
    let device = NSTextField(labelWithString: "Mac speakers")
    let deviceIcon = Style.icon("speaker.slash.fill", size: 12, weight: .medium)
    let shield = NSImageView()
    let volume = NSTextField(labelWithString: "0%")
    let meter = SketchMeter()
    let action = PrimaryButton(title: "Allow sound…", target: nil, action: nil)
    let hint = Style.label("Two confirmations. Your saved starting volume.", size: 11.5, color: Style.muted)
    let login = SketchCheckbox(title: "Start at login")
    let mascot = MascotView()
    let pill = SketchPill()
    private let card = SketchCard(rows: [42, 46], highlighted: 1)
    private let hero = NSStackView()
    private var stageTop: (card: NSLayoutConstraint, toolbar: NSLayoutConstraint)!
    private var cardFits = true
    private var settingsLink: SketchLink!
    private let footerNote = NSStackView()
    private let picker = OutputPicker()
    private weak var owner: AppDelegate?
    private let side = SketchFrame.inset.left + 24
    private var footerTop: CGFloat { SketchFrame.inset.bottom + 46 }
    // Verification happens inside this window: the home content steps aside for one step panel at a time.
    private var verifying: (snapshot: Snapshot, done: (Bool) -> Void)?
    private var panel: VerificationPanel?
    private var track: StepTrack?
    private var panelOffset: NSLayoutConstraint?
    /// The window's own frame from before the check; steps resize to fit and this is restored afterwards.
    private var compactFrame: NSRect?
    private lazy var slide = Spring { [weak self] in self?.applySlide() }
    private func applySlide() { panelOffset?.constant = -2 + 44 * slide.value; panel?.alphaValue = max(0, 1 - abs(slide.value) * 1.4) }
    var isVerifying: Bool { verifying != nil }
    init(owner: AppDelegate) {
        self.owner = owner
        window = SketchWindow(title: "AlwaysMute", size: NSSize(width: 440, height: 632), footer: 46, resizable: true, minimum: NSSize(width: 340, height: 260))
        let root = window.frameView
        func place(_ view: NSView, in parent: NSView? = nil) { view.translatesAutoresizingMaskIntoConstraints = false; (parent ?? root).addSubview(view) }
        let side = self.side, toolbarMid = SketchFrame.inset.top + SketchFrame.band + SketchFrame.toolbar / 2
        // Toolbar: state shield, address pill that picks the output, help.
        shield.image = Style.protectedSpeaker(size: 20); shield.contentTintColor = Artwork.ink; shield.toolTip = "Protection status"
        let help = SketchIconButton(symbol: "questionmark.circle", target: owner, action: #selector(AppDelegate.aboutProtection))
        help.toolTip = "About protection & limitations"; help.setAccessibilityLabel("About protection and limitations")
        let mixer = SketchIconButton(symbol: "slider.vertical.3", target: owner, action: #selector(AppDelegate.showAppVolumes))
        mixer.toolTip = "App volumes"; mixer.setAccessibilityLabel("App volumes")
        device.font = Style.mono(13.5); device.textColor = Artwork.ink; device.lineBreakMode = .byTruncatingTail; device.maximumNumberOfLines = 1
        device.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pill.onClick = { [weak self] in self?.togglePicker() }
        picker.onClose = { [weak self] in self?.pill.open = false }
        for v in [shield, pill, mixer, help] { place(v) }
        for v in [deviceIcon, device] { place(v, in: pill) }
        NSLayoutConstraint.activate([
            shield.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: side - 4), shield.centerYAnchor.constraint(equalTo: root.topAnchor, constant: toolbarMid), shield.widthAnchor.constraint(equalToConstant: 20), shield.heightAnchor.constraint(equalToConstant: 20),
            pill.leadingAnchor.constraint(equalTo: shield.trailingAnchor, constant: 12), pill.trailingAnchor.constraint(equalTo: mixer.leadingAnchor, constant: -6), pill.centerYAnchor.constraint(equalTo: shield.centerYAnchor), pill.heightAnchor.constraint(equalToConstant: 34),
            mixer.trailingAnchor.constraint(equalTo: help.leadingAnchor, constant: -2), mixer.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
            help.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -(side - 10)), help.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
            deviceIcon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16), deviceIcon.centerYAnchor.constraint(equalTo: pill.centerYAnchor), deviceIcon.widthAnchor.constraint(equalToConstant: 16),
            device.leadingAnchor.constraint(equalTo: deviceIcon.trailingAnchor, constant: 8), device.trailingAnchor.constraint(lessThanOrEqualTo: pill.trailingAnchor, constant: -38), device.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        // Dropdown card hanging from the pill: volume row, then the highlighted status row.
        let volumeIcon = Style.icon("speaker.wave.2", size: 12)
        let volumeCaption = Style.label("Output volume", size: 12.5, weight: .medium, color: Style.muted)
        volume.font = Style.mono(13, .semibold); volume.textColor = Artwork.ink; volume.alignment = .right
        statusDot.wantsLayer = true; statusDot.layer?.cornerRadius = 4.5; statusDot.layer?.borderWidth = 1.1; statusDot.layer?.borderColor = Artwork.ink.cgColor
                place(card)
        for v in [volumeIcon, volumeCaption, meter, volume, statusDot, status, unplugBadge] { place(v, in: card) }
        let top = SketchCard.top
        let cardWidth = card.widthAnchor.constraint(equalTo: pill.widthAnchor, constant: 16); cardWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor, constant: SketchFrame.contentTop + 10), card.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: -6), cardWidth, card.widthAnchor.constraint(lessThanOrEqualToConstant: 460), card.heightAnchor.constraint(equalToConstant: 42 + 46 + SketchCard.extra),
            volumeIcon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), volumeIcon.centerYAnchor.constraint(equalTo: card.topAnchor, constant: top + 22), volumeIcon.widthAnchor.constraint(equalToConstant: 16),
            volumeCaption.leadingAnchor.constraint(equalTo: volumeIcon.trailingAnchor, constant: 9), volumeCaption.centerYAnchor.constraint(equalTo: volumeIcon.centerYAnchor),
            meter.leadingAnchor.constraint(equalTo: volumeCaption.trailingAnchor, constant: 12), meter.centerYAnchor.constraint(equalTo: volumeIcon.centerYAnchor), meter.heightAnchor.constraint(equalToConstant: 10),
            volume.leadingAnchor.constraint(equalTo: meter.trailingAnchor, constant: 10), volume.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20), volume.centerYAnchor.constraint(equalTo: volumeIcon.centerYAnchor), volume.widthAnchor.constraint(equalToConstant: 40),
            statusDot.centerXAnchor.constraint(equalTo: volumeIcon.centerXAnchor), statusDot.centerYAnchor.constraint(equalTo: status.centerYAnchor), statusDot.widthAnchor.constraint(equalToConstant: 9), statusDot.heightAnchor.constraint(equalToConstant: 9),
            status.leadingAnchor.constraint(equalTo: volumeCaption.leadingAnchor), status.centerYAnchor.constraint(equalTo: card.topAnchor, constant: top + 42 + 23),
            unplugBadge.leadingAnchor.constraint(greaterThanOrEqualTo: status.trailingAnchor, constant: 8), unplugBadge.trailingAnchor.constraint(equalTo: volume.trailingAnchor, constant: 4), unplugBadge.centerYAnchor.constraint(equalTo: status.centerYAnchor)
        ])
        // Hero group floats in the middle of whatever room the window has; pieces fold away as it gets short.
        place(hero)
        hero.orientation = .vertical; hero.alignment = .centerX; hero.spacing = 0; hero.detachesHiddenViews = true
        heading.alignment = .center; subtitle.alignment = .center; hint.alignment = .center
        action.target = owner; action.action = #selector(AppDelegate.primaryAction); action.isBordered = false
        for v in [mascot, heading, action] { hero.addArrangedSubview(v) }
        let stage = NSLayoutGuide(); root.addLayoutGuide(stage)
        // Preferred size only: in a short window the mascot gives up height before anything else.
        let mascotSize = mascot.heightAnchor.constraint(equalToConstant: 164); mascotSize.priority = .defaultLow
        mascot.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let heroCenter = hero.centerYAnchor.constraint(equalTo: stage.centerYAnchor); heroCenter.priority = .defaultHigh
        let heroWidth = hero.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -2 * side); heroWidth.priority = .defaultHigh
        stageTop = (stage.topAnchor.constraint(equalTo: card.bottomAnchor), stage.topAnchor.constraint(equalTo: root.topAnchor, constant: SketchFrame.contentTop))
        NSLayoutConstraint.activate([
            stageTop.card, stage.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -footerTop),
            heroCenter, hero.topAnchor.constraint(greaterThanOrEqualTo: stage.topAnchor, constant: 4), hero.bottomAnchor.constraint(lessThanOrEqualTo: stage.bottomAnchor, constant: -10),
            hero.centerXAnchor.constraint(equalTo: root.centerXAnchor, constant: -2), heroWidth, hero.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            mascot.widthAnchor.constraint(equalTo: mascot.heightAnchor), mascot.heightAnchor.constraint(lessThanOrEqualToConstant: 164), mascotSize,
            action.widthAnchor.constraint(equalTo: hero.widthAnchor, constant: -5), action.heightAnchor.constraint(equalToConstant: 57)
        ])
        // Footer band: login preference and output settings, or a reassurance line while verifying.
        login.target = owner; login.action = #selector(AppDelegate.toggleLogin)
        settingsLink = SketchLink("Output settings…", symbol: "slider.horizontal.3", target: owner, action: #selector(AppDelegate.showOutputSettings))
        footerNote.orientation = .horizontal; footerNote.spacing = 6; footerNote.isHidden = true
        for v in [login, settingsLink!, footerNote] { place(v) }
        let footerMid = SketchFrame.inset.bottom + 23
        NSLayoutConstraint.activate([
            login.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: side), login.centerYAnchor.constraint(equalTo: root.bottomAnchor, constant: -footerMid),
            settingsLink.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -(side + 8)), settingsLink.centerYAnchor.constraint(equalTo: login.centerYAnchor),
            footerNote.centerXAnchor.constraint(equalTo: root.centerXAnchor, constant: -2), footerNote.centerYAnchor.constraint(equalTo: login.centerYAnchor)
        ])
        root.onResize = { [weak self] size in self?.applyDensity(size) }
        applyDensity(root.bounds.size)
        window.onEscape = { [weak self] in
            guard let self else { return false }
            if self.picker.isOpen { self.picker.close(); return true }
            guard self.isVerifying else { return false }
            self.finish(false); return true
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.finish(false) }
    }

    // MARK: Output picker

    private func togglePicker() {
        if picker.isOpen { picker.close(); return }
        guard let owner, !isVerifying else { return }
        pill.open = true
        picker.show(from: pill, choices: owner.engine.outputChoices()) { [weak owner] choice in
            guard let owner, !choice.current else { return }
            if !owner.engine.switchOutput(to: choice.id) {
                let a = NSAlert(); a.messageText = "Couldn't switch to \(choice.name)"; a.informativeText = "macOS didn't accept the change. Try again, or pick the output in Sound settings."; a.runModal()
            }
        }
    }

    // MARK: Two-step verification, in place

    func beginVerification(_ s: Snapshot, done: @escaping (Bool) -> Void) {
        picker.close()
        verifying = (s, done)
        showStep(1)
    }
    /// `from` is the side the step slides in from: 1 for forward (right), -1 for back (left).
    private func showStep(_ step: Int, from direction: CGFloat = 1) {
        guard let s = verifying?.snapshot else { return }
        let root = window.frameView
        panel?.removeFromSuperview(); track?.removeFromSuperview()
        let next = VerificationPanel(step: step, snapshot: s, onContinue: { [weak self] in if step == 1 { self?.showStep(2) } else { self?.finish(true) } }, onKeep: { [weak self] in self?.finish(false) })
        let steps = StepTrack(step: step)
        for v in [next, steps] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        let offset = next.centerXAnchor.constraint(equalTo: root.centerXAnchor, constant: -2)
        let width = next.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -2 * side); width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            next.topAnchor.constraint(equalTo: root.topAnchor, constant: SketchFrame.contentTop + 16), offset, width, next.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            steps.centerXAnchor.constraint(equalTo: root.centerXAnchor, constant: -2), steps.centerYAnchor.constraint(equalTo: root.topAnchor, constant: SketchFrame.inset.top + SketchFrame.band + SketchFrame.toolbar / 2)
        ])
        panel = next; track = steps; panelOffset = offset
        setHome(visible: false)
        root.layoutSubtreeIfNeeded()
        // Fit the window to this step (grow or shrink, top edge fixed), remembering the size to return to.
        let delta = next.frame.maxY + 22 + footerTop - root.bounds.height
        if abs(delta) > 1 {
            if compactFrame == nil { compactFrame = window.frame }
            var frame = window.frame; frame.size.height += delta; frame.origin.y -= delta
            window.setFrame(frame, display: true, animate: true)
        }
        slide.jump(to: direction); slide.animate(to: 0)
        next.greet()
        window.makeFirstResponder(nil)
    }
    /// Shakes the window like a rejected password field, so a volume key press points back at the open check.
    func shakeForAttention() {
        guard isVerifying else { return }
        panel?.nudge()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let rest = shakeRest ?? window.frame.origin
        shakeRest = rest
        let path = CGMutablePath(); path.move(to: rest)
        for (i, dx) in [-14.0, 12, -9, 6, -3, 0].enumerated() { _ = i; path.addLine(to: CGPoint(x: rest.x + dx, y: rest.y)) }
        let shake = CAKeyframeAnimation(); shake.path = path; shake.duration = 0.42; shake.calculationMode = .linear
        window.animations = ["frameOrigin": shake]
        window.animator().setFrameOrigin(rest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.shakeRest = nil }
    }
    private var shakeRest: NSPoint?
    enum VolumeKey { case up, down, mute }
    /// ⌘ + Volume Up presses Continue; Mute or Volume Down goes back a step; plain Volume Up only nudges.
    /// Auto-repeat from a held key is filtered out before it gets here.
    func volumeKey(_ key: VolumeKey, command: Bool) {
        guard isVerifying, let panel else { return }
        switch key {
        case .mute, .down:
            if panel.step == 2 { showStep(1, from: -1) }
            else { panel.keep.highlight(true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { panel.keep.performClick(nil) } }
        case .up where !command:
            shakeForAttention(); panel.nudge("Hold ⌘ and press Volume Up.")
        case .up:
            // ⌘ + Volume Up counts immediately; each step is its own deliberate chord.
            guard let proceed = panel.proceed else { return }
            proceed.highlight(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { proceed.performClick(nil) }
        }
    }
    private func finish(_ allowed: Bool) {
        guard let v = verifying else { return }
        verifying = nil
        panel?.removeFromSuperview(); track?.removeFromSuperview(); panel = nil; track = nil; panelOffset = nil
        if let compactFrame { window.setFrame(compactFrame, display: true, animate: true) }
        compactFrame = nil
        setHome(visible: true)
        mascot.bounce()
        v.done(allowed)
    }
    private func setHome(visible: Bool) {
        let home: [NSView] = [pill, card, hero, login, settingsLink]
        let note = footerNoteContent(step: panel?.step ?? 1)
        footerNote.setViews(note, in: .center)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            for v in home where !(v === self.card && !self.cardFits) { if visible { v.isHidden = false }; v.animator().alphaValue = visible ? 1 : 0 }
            if !visible { footerNote.isHidden = false }
            footerNote.animator().alphaValue = visible ? 0 : 1
        }, completionHandler: { [weak self] in
            guard let self else { return }
            // Hidden views take no clicks or key equivalents.
            for v in home { v.isHidden = self.isVerifying || (v === self.card && !self.cardFits) }
            self.footerNote.isHidden = !self.isVerifying
        })
    }
    /// Folds the page to fit short or narrow windows: mascot first (by constraint), then card, subtitle and hint, then heading.
    private func applyDensity(_ size: NSSize) {
        let room = size.height - SketchFrame.contentTop - footerTop
        let fitsCard = room >= 300, fitsText = room >= 175, fitsHeading = room >= 125
        if fitsCard != cardFits {
            cardFits = fitsCard
            stageTop.card.isActive = false; stageTop.toolbar.isActive = false
            (fitsCard ? stageTop.card : stageTop.toolbar).isActive = true
            if !isVerifying { card.isHidden = !fitsCard; card.alphaValue = 1 }
        }
        mascot.isHidden = !fitsCard
        heading.isHidden = !fitsHeading
        _ = fitsText
        hero.setCustomSpacing(4, after: mascot); hero.setCustomSpacing(16, after: heading)
        settingsLink?.title = size.width < 390 ? "Settings…" : "Output settings…"
        settingsLink?.invalidateIntrinsicContentSize()
    }
    private func footerNoteContent(step: Int) -> [NSView] {
        []
    }

    func render(_ s: Snapshot, promptOpen: Bool) {
        // If the output changes mid-check, the answer no longer applies.
        if let v = verifying, v.snapshot.names != s.names || !s.safe { finish(false) }
        heading.stringValue = !s.safe ? "Check your output." : s.locked ? "Speaker is muted." : "Sound, on your terms."
        subtitle.stringValue = !s.safe ? "This output cannot be safely controlled." : s.locked ? "Sound only when you say so." : "Sound stays on until you mute it."
        status.stringValue = !s.safe ? "Protection unavailable" : s.locked ? "Muted & protected" : "Sound allowed"
        status.textColor = s.safe ? Artwork.ink : Style.warning
        statusDot.layer?.backgroundColor = (s.safe ? (s.locked ? Style.green : Artwork.coral) : Style.warning).cgColor
        reason.stringValue = s.reason; reason.toolTip = s.reason; status.toolTip = s.reason
        hint.toolTip = s.startingText
        device.stringValue = s.names.isEmpty ? "no audio output" : s.names
        pill.toolTip = "\(device.stringValue)\nClick to choose an output"; pill.setAccessibilityLabel("Audio output: \(device.stringValue). Choose output")
        deviceIcon.image = NSImage(systemSymbolName: s.locked ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        shield.image = s.safe ? Style.protectedSpeaker(size: 20, muted: s.locked) : NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Protection unavailable")
        shield.contentTintColor = s.safe ? Artwork.ink : Style.warning
        volume.stringValue = "\(s.level)%"; meter.level = Double(s.level) / 100
        if mascot.muted != s.locked { mascot.muted = s.locked; mascot.bounce() }
        action.title = s.locked ? "Allow sound…" : "Mute and lock"
        action.isEnabled = !promptOpen && (!s.locked || (s.safe && s.canUnmute))
        action.needsDisplay = true
        action.toolTip = !s.safe ? "Choose a supported output to continue." : !s.canUnmute ? "This output has no safe volume control." : nil
        hint.stringValue = !s.safe ? "Choose a supported output to continue." : !s.canUnmute ? "This output has no safe volume control." : s.locked ? "Two confirmations. Your saved starting volume." : "You can return to silence at any time."
    }
}
