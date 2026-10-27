import AppKit

/// "① Check output ── ② Confirm volume" progress drawn in the prompt's toolbar.
final class StepTrack: NSView {
    let step: Int
    static let titles = ["Check output", "Confirm volume"]
    init(step: Int) { self.step = step; super.init(frame: .zero); setAccessibilityLabel("Step \(step) of 2") }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    private func label(_ index: Int) -> NSAttributedString {
        NSAttributedString(string: Self.titles[index], attributes: [.font: Style.font(12.5, index + 1 == step ? .semibold : .medium), .foregroundColor: Artwork.ink.withAlphaComponent(index + 1 <= step ? 1 : 0.5)])
    }
    private let connector: CGFloat = 36
    override var intrinsicContentSize: NSSize { NSSize(width: 22 * 2 + 8 * 2 + label(0).size().width + label(1).size().width + 14 * 2 + connector, height: 28) }
    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 1
        for index in 0..<2 {
            let circle = NSBezierPath(ovalIn: NSRect(x: x, y: 3, width: 22, height: 22))
            let done = index + 1 < step, current = index + 1 == step
            (done || current ? Artwork.coral : Artwork.sheet).setFill(); circle.fill()
            Artwork.sketch(circle, width: 1.3, color: Artwork.ink.withAlphaComponent(done || current ? 1 : 0.5), seed: Double(index) * 5 + 50)
            if done {
                let tick = NSBezierPath(); tick.move(to: NSPoint(x: x + 6.5, y: 14.5)); tick.line(to: NSPoint(x: x + 10, y: 18)); tick.line(to: NSPoint(x: x + 16, y: 10))
                Artwork.ink.setStroke(); tick.lineWidth = 1.9; tick.lineCapStyle = .round; tick.lineJoinStyle = .round; tick.stroke()
            } else {
                let n = NSAttributedString(string: "\(index + 1)", attributes: [.font: Style.font(12, .bold), .foregroundColor: Artwork.ink.withAlphaComponent(current ? 1 : 0.5)])
                n.draw(at: NSPoint(x: x + 11 - n.size().width / 2, y: 14 - n.size().height / 2))
            }
            x += 22 + 8
            let text = label(index); text.draw(at: NSPoint(x: x, y: 14 - text.size().height / 2)); x += text.size().width
            if index == 0 {
                x += 14
                let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: 14)); line.line(to: NSPoint(x: x + connector, y: 14))
                if step > 1 { Artwork.sketch(line, width: 1.6, color: Artwork.coral, seed: 57) }
                else { line.setLineDash([3, 3.5], count: 2, phase: 0); Artwork.ink.withAlphaComponent(0.45).setStroke(); line.lineWidth = 1.3; line.lineCapStyle = .round; line.stroke() }
                x += connector + 14
            }
        }
    }
}

/// Hand-lettered speech bubble that pops out of the mascot's mouth.
final class SketchBubble: NSView {
    private(set) var text: String
    private lazy var pop = Spring { [weak self] in self?.needsDisplay = true }
    init(_ text: String) { self.text = text; super.init(frame: .zero); setAccessibilityLabel(text); setAccessibilityRole(.staticText) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    private var lettering: NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont(name: "ChalkboardSE-Bold", size: 14) ?? Style.font(14, .semibold), .foregroundColor: Artwork.ink])
    }
    override var intrinsicContentSize: NSSize { let s = lettering.size(); return NSSize(width: ceil(s.width) + 12 + 28 + 7, height: ceil(s.height) + 18 + 9) }
    /// Starts collapsed and springs open.
    func popIn() { pop.animate(to: 1) }
    /// Swaps the line and re-pops the bubble.
    func say(_ line: String) {
        text = line; setAccessibilityLabel(line); invalidateIntrinsicContentSize()
        pop.jump(to: 0.55); pop.animate(to: 1)
    }
    override func draw(_ dirtyRect: NSRect) {
        let scale = pop.value
        guard scale > 0.02 else { return }
        let body = NSRect(x: 12, y: 2, width: bounds.width - 19, height: bounds.height - 9)
        let anchor = NSPoint(x: 0, y: body.maxY - 4)
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: anchor.x, yBy: anchor.y); t.scale(by: scale); t.translateX(by: -anchor.x, yBy: -anchor.y); t.concat()
        let shape = NSBezierPath(roundedRect: body, xRadius: 14, yRadius: 14)
        Artwork.hatchShadow(shape, offset: NSSize(width: 3, height: 5))
        Artwork.sheet.setFill(); shape.fill()
        Artwork.sketch(shape, width: 1.5, seed: 61)
        // Tail drawn over the outline so it reads as one continuous shape.
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: body.minX + 2, y: body.maxY - 20)); tail.line(to: anchor); tail.line(to: NSPoint(x: body.minX + 2, y: body.maxY - 9)); tail.close()
        Artwork.sheet.setFill(); tail.fill()
        let edges = NSBezierPath(); edges.move(to: NSPoint(x: body.minX + 0.5, y: body.maxY - 20)); edges.line(to: anchor); edges.line(to: NSPoint(x: body.minX + 0.5, y: body.maxY - 9))
        Artwork.sketch(edges, width: 1.5, seed: 63)
        let letters = lettering, size = letters.size()
        letters.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// One of the two unmute confirmations, shown in place inside the main window.
/// Esc keeps sound off; volume keys answer it too (see QuietInterface.volumeKey).
final class VerificationPanel: NSView {
    let step: Int
    let mascot = MascotView()
    let bubble: SketchBubble
    let keep: PrimaryButton
    private(set) var proceed: PrimaryButton!
    private let onContinue: () -> Void, onKeep: () -> Void
    override var isFlipped: Bool { true }
    init(step: Int, snapshot s: Snapshot, onContinue: @escaping () -> Void, onKeep: @escaping () -> Void) {
        self.step = step; self.onContinue = onContinue; self.onKeep = onKeep
        bubble = SketchBubble(step == 1 ? "Are you sure? Sound on?" : "Last check, promise!")
        keep = PrimaryButton(title: "Keep muted", target: nil, action: nil)
        super.init(frame: .zero)
        func place(_ view: NSView, in parent: NSView? = nil) { view.translatesAutoresizingMaskIntoConstraints = false; (parent ?? self).addSubview(view) }
        mascot.wave = step == 2; place(mascot); place(bubble)
        let heading = Style.label(step == 1 ? "Turn on sound?" : "Ready to turn sound on?", size: 23, weight: .bold)
        let body = NSTextField(wrappingLabelWithString: "")
        // Selecting a mixed-style label makes AppKit redraw it in the plain system font; this is display-only text.
        body.isSelectable = false
        let names = s.names.isEmpty ? "this output" : s.names
        let regular: [NSAttributedString.Key: Any] = [.font: Style.font(13.5), .foregroundColor: Artwork.ink.withAlphaComponent(0.8)]
        let bold: [NSAttributedString.Key: Any] = [.font: Style.font(13.5, .semibold), .foregroundColor: Artwork.ink]
        let copy = NSMutableAttributedString()
        if step == 1 {
            copy.append(NSAttributedString(string: "Your Mac is muted right now. Continue only if you meant to play audio from ", attributes: regular))
            copy.append(NSAttributedString(string: names, attributes: bold)); copy.append(NSAttributedString(string: ".", attributes: regular))
        } else {
            copy.append(NSAttributedString(string: "Sound starts at the \(s.volumes.count > 1 ? "volumes" : "volume") below and stays on ", attributes: regular))
            copy.append(NSAttributedString(string: "with no timer", attributes: bold))
            copy.append(NSAttributedString(string: " until you mute it. Anything already playing may be heard right away.", attributes: regular))
        }
        body.attributedStringValue = copy
        body.setContentCompressionResistancePriority(.required, for: .vertical)
        for v in [heading, body] { place(v) }
        NSLayoutConstraint.activate([
            mascot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -4), mascot.topAnchor.constraint(equalTo: topAnchor), mascot.widthAnchor.constraint(equalToConstant: 108), mascot.heightAnchor.constraint(equalToConstant: 108),
            bubble.leadingAnchor.constraint(equalTo: mascot.trailingAnchor, constant: -8), bubble.topAnchor.constraint(equalTo: mascot.topAnchor, constant: 10), bubble.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            heading.topAnchor.constraint(equalTo: mascot.bottomAnchor, constant: 8), heading.leadingAnchor.constraint(equalTo: leadingAnchor), heading.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4), body.leadingAnchor.constraint(equalTo: leadingAnchor), body.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        var above: NSView = body
        // Step 2 lists exactly what will be enabled, and how loud.
        if step == 2, !s.volumes.isEmpty {
            let card = SketchCard(rows: s.volumes.count); place(card)
            let rowHeight: CGFloat = 40
            NSLayoutConstraint.activate([card.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 12), card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -4), card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 5), card.heightAnchor.constraint(equalToConstant: rowHeight * CGFloat(s.volumes.count) + SketchCard.extra)])
            for (index, output) in s.volumes.enumerated() {
                let icon = Style.icon("speaker.wave.1", size: 12), name = NSTextField(labelWithString: output.name), meter = SketchMeter(), value = NSTextField(labelWithString: "\(output.volume)%")
                name.font = Style.mono(12.5); name.textColor = Artwork.ink; name.lineBreakMode = .byTruncatingTail; name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                value.font = Style.mono(13, .semibold); value.textColor = Artwork.ink; value.alignment = .right
                meter.level = Double(output.volume) / 100
                for v in [icon, name, meter, value] { place(v, in: card) }
                let mid = SketchCard.top + rowHeight * (CGFloat(index) + 0.5)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16), icon.centerYAnchor.constraint(equalTo: card.topAnchor, constant: mid), icon.widthAnchor.constraint(equalToConstant: 16),
                    name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8), name.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
                    meter.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 10), meter.widthAnchor.constraint(equalToConstant: 80), meter.heightAnchor.constraint(equalToConstant: 10), meter.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
                    value.leadingAnchor.constraint(equalTo: meter.trailingAnchor, constant: 8), value.widthAnchor.constraint(equalToConstant: 42), value.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18), value.centerYAnchor.constraint(equalTo: icon.centerYAnchor)
                ])
            }
            above = card
        }
        // Actions: the safe choice is the bright, default one.
        proceed = PrimaryButton(title: step == 1 ? "Continue…" : "Yes, enable sound", target: self, action: #selector(proceedTapped))
        proceed.tone = Artwork.sheet; proceed.isBordered = false; proceed.keyHints = [("⌘", "speaker.plus.fill")]; proceed.setAccessibilityLabel(step == 1 ? "Continue to step 2" : "Yes, enable sound")
        keep.target = self; keep.action = #selector(keepTapped); keep.isBordered = false; keep.keyHints = [("", "speaker.slash.fill")]; keep.setAccessibilityLabel("Keep muted")
        place(proceed); place(keep)
        NSLayoutConstraint.activate([
            proceed.topAnchor.constraint(equalTo: above.bottomAnchor, constant: 18), proceed.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -4), proceed.heightAnchor.constraint(equalToConstant: 57),
            keep.leadingAnchor.constraint(equalTo: proceed.trailingAnchor, constant: 6), keep.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 5), keep.topAnchor.constraint(equalTo: proceed.topAnchor), keep.heightAnchor.constraint(equalTo: proceed.heightAnchor), keep.widthAnchor.constraint(equalTo: proceed.widthAnchor),
            proceed.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func proceedTapped() { onContinue() }
    @objc private func keepTapped() { onKeep() }
    func greet() { mascot.bounce(); bubble.popIn() }
    func nudge(_ line: String = "Hold on! Answer me first.") { mascot.bounce(); bubble.say(line) }
}
