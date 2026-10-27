import AppKit

/// Small dialog under the menu bar icon: the "Are you sure? Sound on?" check, or "Safari wants to play sound."
/// ⌘ + Volume Up advances, Mute steps back (or keeps quiet on the first step).
final class PlayPrompt {
    private var panel: NSPanel?
    private var view: PromptView?
    private(set) var app: PlayingApp?
    private var step = 1
    /// 1 when sound is already on and only this app needs a yes; 2 for a full check.
    private var steps = 2
    private var idle: DispatchWorkItem?
    private var shakeRest: NSPoint?
    private var titles: [String] = [], plays: [String] = []
    var volumeText = "15%"
    var onAllow: (() -> Void)?
    /// Called whenever the dialog goes away, answered or not.
    var onClose: (() -> Void)?
    var isOpen: Bool { panel != nil }

    /// An app started playing while sound is on: one yes lets it through.
    func show(for app: PlayingApp, steps: Int = 1, below icon: NSRect?) {
        show(titles: ["\(app.name) wants to play sound.", "Play at \(volumeText)?"], plays: ["Play sound", "Yes, play"], steps: steps,
             announcement: "\(app.name) wants to play sound. Press Command Volume Up to play, or Mute to keep quiet.", below: icon)
        self.app = app
    }
    /// The two-step check for turning sound on, without opening the main window.
    func showSoundCheck(output: String, below icon: NSRect?) {
        let target = output.isEmpty ? "" : " for \(output)"
        show(titles: ["Are you sure? Sound on\(target)?", "Play at \(volumeText)?"], plays: ["Continue", "Yes, sound on"], steps: 2,
             announcement: "Turn sound on\(target)? Press Command Volume Up to continue, or Mute to keep quiet.", below: icon)
    }
    private func show(titles: [String], plays: [String], steps: Int, announcement: String, below icon: NSRect?) {
        close()
        onCloseArmed = true
        self.titles = titles; self.plays = plays; app = nil; step = 1; self.steps = steps
        let panel: NSPanel, view: PromptView
        if let notch = Notch.current {
            // Grows out of the notch.
            let frame = Notch.frame(for: NSSize(width: 340, height: notch.height + 142), notch: notch)
            panel = Notch.panel(frame: frame)
            view = PromptView(frame: NSRect(origin: .zero, size: frame.size), tailX: 0, notch: notch.size)
        } else {
            // Drops from the menu bar icon.
            let size = NSSize(width: 336, height: 156)
            let screen = NSScreen.screens.first { icon.map($0.frame.intersects) ?? false } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let anchor = icon ?? NSRect(x: visible.maxX - 120, y: visible.maxY, width: 22, height: 22)
            let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            let frame = NSRect(x: x, y: anchor.minY - 4 - size.height, width: size.width, height: size.height)
            panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]; panel.appearance = NSAppearance(named: .aqua)
            panel.isReleasedWhenClosed = false
            view = PromptView(frame: NSRect(origin: .zero, size: size), tailX: anchor.midX - x)
        }
        view.onPlay = { [weak self] in self?.advance() }
        view.onKeep = { [weak self] in self?.close() }
        view.onHover = { [weak self] inside in inside ? self?.idle?.cancel() : self?.scheduleIdle() }
        view.restoreTitle = { [weak self] in self?.render() }
        panel.contentView = view
        self.panel = panel; self.view = view
        render()
        panel.orderFrontRegardless()
        view.popIn()
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        scheduleIdle()
    }
    private func render() {
        guard titles.indices.contains(step - 1) else { return }
        view?.set(step: step, of: steps, title: titles[step - 1], play: plays[step - 1])
    }
    /// Unanswered prompts step aside on their own; that app won't ask again until it stops and starts playing.
    private func scheduleIdle() {
        idle?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }
    func key(_ key: QuietInterface.VolumeKey, command: Bool) {
        switch key {
        case .mute, .down:
            if step > 1 { step -= 1; render(); view?.popIn(from: 0.85); scheduleIdle(); return }
            view?.flash(keep: true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.close() }
        case .up where !command: nudge()
        case .up: view?.flash(keep: false); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.advance() }
        }
    }
    private func advance() {
        guard isOpen else { return }
        if step < steps { step += 1; render(); view?.popIn(from: 0.85); scheduleIdle(); return }
        let allow = onAllow
        close()
        allow?()
    }
    /// Plain Volume Up: shake like a wrong password and point at ⌘.
    private func nudge() {
        view?.nudge()
        guard let panel, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let rest = shakeRest ?? panel.frame.origin; shakeRest = rest
        let path = CGMutablePath(); path.move(to: rest)
        for dx in [-12.0, 10, -7, 5, -2, 0] { path.addLine(to: CGPoint(x: rest.x + dx, y: rest.y)) }
        let shake = CAKeyframeAnimation(); shake.path = path; shake.duration = 0.4
        panel.animations = ["frameOrigin": shake]; panel.animator().setFrameOrigin(rest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.shakeRest = nil }
        scheduleIdle()
    }
    private var onCloseArmed = false
    func close() {
        idle?.cancel()
        guard let panel, let view else { return }
        self.panel = nil; self.view = nil; app = nil
        if onCloseArmed { onCloseArmed = false; onClose?() }
        view.popOut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { panel.orderOut(nil) }
    }
}

final class PromptView: NSView {
    let tailX: CGFloat
    /// Set when the dialog is a notch island rather than a paper bubble.
    let notch: NSSize?
    var onPlay: (() -> Void)?
    var onKeep: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let mascot = MascotView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let play = PrimaryButton(title: "Play sound", target: nil, action: nil)
    private let keep = PrimaryButton(title: "Keep muted", target: nil, action: nil)
    private var step = 1, total = 2
    private lazy var pop = Spring { [weak self] in self?.needsDisplay = true; self?.applyPop() }
    init(frame: NSRect, tailX: CGFloat, notch: NSSize? = nil) {
        self.tailX = tailX; self.notch = notch
        super.init(frame: frame)
        trackHover()
        mascot.minimumSize = 0
        let top = notch.map { $0.height + 10 } ?? 20, side = notch == nil ? 18 : Notch.ear + 16
        title.isSelectable = false; title.font = Style.font(14, .bold); title.textColor = Artwork.ink; title.maximumNumberOfLines = 2
        play.tone = Artwork.sheet; play.isBordered = false; play.keyHints = [("⌘", "speaker.plus.fill")]; play.target = self; play.action = #selector(playTapped)
        keep.isBordered = false; keep.keyHints = [("", "speaker.slash.fill")]; keep.target = self; keep.action = #selector(keepTapped)
        for v in [mascot, title, play, keep] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            mascot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: side), mascot.topAnchor.constraint(equalTo: topAnchor, constant: top), mascot.widthAnchor.constraint(equalToConstant: 56), mascot.heightAnchor.constraint(equalToConstant: 56),
            title.leadingAnchor.constraint(equalTo: mascot.trailingAnchor, constant: 10), title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(side + 22)), title.centerYAnchor.constraint(equalTo: mascot.centerYAnchor, constant: 2),
            play.leadingAnchor.constraint(equalTo: leadingAnchor, constant: side), play.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16), play.heightAnchor.constraint(equalToConstant: 48),
            keep.leadingAnchor.constraint(equalTo: play.trailingAnchor, constant: 4), keep.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(side - 2)), keep.topAnchor.constraint(equalTo: play.topAnchor), keep.heightAnchor.constraint(equalTo: play.heightAnchor), keep.widthAnchor.constraint(equalTo: play.widthAnchor)
        ])
        setAccessibilityRole(.group); setAccessibilityLabel("Sound request")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    @objc private func playTapped() { onPlay?() }
    @objc private func keepTapped() { onKeep?() }
    func set(step: Int, of total: Int, title text: String, play label: String) {
        self.step = step; self.total = total; title.stringValue = text; play.title = label
        mascot.wave = step == 2; needsDisplay = true
    }
    func popIn(from start: CGFloat = 0) { pop.jump(to: start); pop.animate(to: 1); mascot.bounce() }
    func popOut() { pop.animate(to: 0) }
    func nudge() { mascot.bounce(); title.stringValue = "Hold ⌘ and press Volume Up."; DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.restoreTitle?() } }
    var restoreTitle: (() -> Void)?
    func flash(keep useKeep: Bool) { (useKeep ? keep : play).highlight(true) }
    /// Subviews fade with the bubble so the whole dialog pops as one piece.
    private func applyPop() { for v in subviews { v.alphaValue = notch == nil ? max(0, min(1, pop.value)) : Notch.contentAlpha(pop.value) } }
    override func draw(_ dirtyRect: NSRect) {
        let v = pop.value
        if let notch { drawIsland(notch: notch, progress: v); return }
        guard v > 0.02 else { return }
        let body = NSRect(x: 8, y: 14, width: bounds.width - 20, height: bounds.height - 26)
        let tip = NSPoint(x: min(max(tailX, body.minX + 24), body.maxX - 24), y: 3)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(min(1, v))
        let shape = NSBezierPath(roundedRect: body, xRadius: 16, yRadius: 16)
        Artwork.hatchShadow(shape, offset: NSSize(width: 3, height: 5))
        Artwork.sheet.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip(); Artwork.paperGrain(body, strength: 0.7); NSGraphicsContext.restoreGraphicsState()
        Artwork.sketch(shape, width: 1.5, seed: 101)
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: tip.x - 9, y: body.minY + 1.5)); tail.line(to: tip); tail.line(to: NSPoint(x: tip.x + 9, y: body.minY + 1.5)); tail.close()
        Artwork.sheet.setFill(); tail.fill()
        let edges = NSBezierPath(); edges.move(to: NSPoint(x: tip.x - 9, y: body.minY + 0.5)); edges.line(to: tip); edges.line(to: NSPoint(x: tip.x + 9, y: body.minY + 0.5))
        Artwork.sketch(edges, width: 1.5, seed: 103)
        // Step dots, top right, only when there is more than one step.
        for i in 0..<(total > 1 ? total : 0) {
            let dot = NSBezierPath(ovalIn: NSRect(x: body.maxX - 34 + CGFloat(i) * 12, y: body.minY + 12, width: 8, height: 8))
            (i < step ? Artwork.coral : Artwork.sheet).setFill(); dot.fill()
            Artwork.ink.setStroke(); dot.lineWidth = 1.2; dot.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    /// Paper sheet set into a black island hanging from the notch, with step dots under the notch.
    private func drawIsland(notch: NSSize, progress v: CGFloat) {
        Notch.drawIsland(in: bounds, notch: notch, progress: v)
        let alpha = Notch.contentAlpha(v)
        guard alpha > 0, total > 1 else { return }
        for i in 0..<total {
            let dot = NSBezierPath(ovalIn: NSRect(x: bounds.maxX - Notch.ear - 38 + CGFloat(i) * 12, y: notch.height + 12, width: 8, height: 8))
            (i < step ? Artwork.coral : Artwork.sheet).withAlphaComponent(alpha).setFill(); dot.fill()
            Artwork.ink.withAlphaComponent(alpha).setStroke(); dot.lineWidth = 1.2; dot.stroke()
        }
    }
}
