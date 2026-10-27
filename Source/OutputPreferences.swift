import AppKit
import CoreAudio

struct OutputPreference: Codable, Equatable {
    var name: String
    var trusted = false
    var volume = 15
}
final class OutputPreferences {
    private let defaults: UserDefaults
    private(set) var entries: [String: OutputPreference]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: "outputPreferences").flatMap { try? JSONDecoder().decode([String: OutputPreference].self, from: $0) } ?? [:]
    }
    func value(_ key: String, name: String) -> OutputPreference { entries[key] ?? OutputPreference(name: name) }
    func save(_ key: String, _ value: OutputPreference) {
        var value = value; value.volume = max(1, min(100, value.volume)); entries[key] = value
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: "outputPreferences") }
    }
}
struct RouteIdentity: Equatable {
    let id: AudioObjectID
    let key: String
    let builtIn: Bool
    let source: UInt32?
    let jack: UInt32?
}
enum RoutePolicy {
    static func fallback(old: RouteIdentity?, new: RouteIdentity?, available: Set<AudioObjectID>) -> Bool {
        guard let old, let new, old != new else { return false }
        if !available.contains(old.id) { return true }
        if new.builtIn && (!old.builtIn || old.id != new.id || old.source != new.source || (old.jack == 1 && new.jack == 0)) { return true }
        return false
    }
    static func canTrust(key: String, supported: Bool, fallback: Bool, trusted: Bool) -> Bool {
        !key.isEmpty && supported && !fallback && trusted
    }
}
struct OutputSettingRow: Equatable {
    let key: String
    let name: String
    let active: Bool
    let supported: Bool
    let preference: OutputPreference
}
final class SketchSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX + 1, y: rect.midY - 5, width: rect.width - 2, height: 10)
        let shape = NSBezierPath(roundedRect: track, xRadius: 5, yRadius: 5)
        Artwork.sheet.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        Artwork.hatch(in: track, opacity: 0.16, spacing: 3.5, width: 0.6)
        let filled = NSRect(x: track.minX, y: track.minY, width: knobRect(flipped: flipped).midX - track.minX, height: track.height)
        Artwork.coral.withAlphaComponent(isEnabled ? 1 : 0.4).setFill(); filled.fill(); Artwork.paperGrain(filled)
        NSGraphicsContext.restoreGraphicsState()
        Artwork.sketch(shape, width: 1.2, color: Artwork.ink.withAlphaComponent(isEnabled ? 1 : 0.4), seed: 31)
    }
    override func drawKnob(_ knobRect: NSRect) {
        let knob = NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 10, y: knobRect.midY - 10, width: 20, height: 20))
        Artwork.hatchShadow(knob, offset: NSSize(width: 1.5, height: controlView?.isFlipped == true ? 3 : -3))
        Artwork.sheet.setFill(); knob.fill()
        Artwork.sketch(knob, width: 1.5, color: Artwork.ink.withAlphaComponent(isEnabled ? 1 : 0.4), seed: 33)
        Artwork.coral.withAlphaComponent(isEnabled ? 1 : 0.4).setFill(); NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 3, y: knobRect.midY - 3, width: 6, height: 6)).fill()
    }
}
final class OutputSettingsWindow: NSObject {
    let engine: GuardEngine
    let window: SketchWindow
    let picker = NSPopUpButton()
    let trust = SketchCheckbox(title: "Trust this output")
    let slider = NSSlider(value: 15, minValue: 1, maxValue: 100, target: nil, action: nil)
    let percentage = NSTextField(labelWithString: "15%")
    let note = Style.wrapping("", size: 11.5)
    var rows: [OutputSettingRow] = []
    init(engine: GuardEngine) {
        self.engine = engine
        window = SketchWindow(title: "Output settings", size: NSSize(width: 440, height: 446), footer: 44)
        super.init()
        let root = window.frameView
        func place(_ view: NSView, in parent: NSView? = nil) { view.translatesAutoresizingMaskIntoConstraints = false; (parent ?? root).addSubview(view) }
        let side = SketchFrame.inset.left + 24, toolbarMid = SketchFrame.inset.top + SketchFrame.band + SketchFrame.toolbar / 2
        // Toolbar: the output picker lives in the address pill.
        let pill = SketchPill(), pillIcon = Style.icon("hifispeaker", size: 12, weight: .medium)
        picker.target = self; picker.action = #selector(selectOutput); picker.isBordered = false
        picker.font = Style.mono(13); picker.contentTintColor = Artwork.ink; picker.setAccessibilityLabel("Output")
        place(pill); place(pillIcon, in: pill); place(picker, in: pill)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: side - 6), pill.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -(side - 6)), pill.centerYAnchor.constraint(equalTo: root.topAnchor, constant: toolbarMid), pill.heightAnchor.constraint(equalToConstant: 34),
            pillIcon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16), pillIcon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            picker.leadingAnchor.constraint(equalTo: pillIcon.trailingAnchor, constant: 4), picker.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12), picker.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        // Trust card.
        trust.target = self; trust.action = #selector(changeTrust)
        let trustCard = SketchCard(rows: 1), trustIcon = Style.icon("checkmark.shield", size: 14)
        place(trustCard); place(trustIcon, in: trustCard); place(trust, in: trustCard)
        // Starting volume card.
        slider.cell = SketchSliderCell(); slider.minValue = 1; slider.maxValue = 100; slider.doubleValue = 15
        slider.target = self; slider.action = #selector(changeVolume); slider.isContinuous = true
        slider.setAccessibilityLabel("Starting volume")
        percentage.font = Style.mono(15, .semibold); percentage.textColor = Artwork.ink
        let volumeCard = SketchCard(rows: 2), volumeIcon = Style.icon("speaker.wave.2", size: 13)
        volumeCard.dividers = false
        let volumeTitle = Style.label("Starting volume", size: 13, weight: .semibold)
        for v in [volumeIcon, volumeTitle, percentage, slider] { place(v, in: volumeCard) }
        place(volumeCard)
        // Protection note, drawn like the reference's highlighted dropdown row.
        let protectionCard = SketchCard(rows: 1, highlighted: 0), protectionIcon = Style.icon("headphones", size: 14)
        let protection = Style.wrapping("Headphones unplugged? Muted instantly, even on trusted outputs.", size: 13, color: Artwork.ink)
        protection.font = Style.font(13, .semibold)
        place(protectionCard); place(protectionIcon, in: protectionCard); place(protection, in: protectionCard)
        place(note)
        let cardLeading = side - 4, cardTrailing = -(side - 9)
        NSLayoutConstraint.activate([
            trustCard.topAnchor.constraint(equalTo: root.topAnchor, constant: SketchFrame.contentTop + 16), trustCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: cardLeading), trustCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: cardTrailing), trustCard.heightAnchor.constraint(equalToConstant: 55),
            trustIcon.leadingAnchor.constraint(equalTo: trustCard.leadingAnchor, constant: 18), trustIcon.centerYAnchor.constraint(equalTo: trustCard.topAnchor, constant: 25), trustIcon.widthAnchor.constraint(equalToConstant: 18),
            trust.leadingAnchor.constraint(equalTo: trustIcon.trailingAnchor, constant: 10), trust.centerYAnchor.constraint(equalTo: trustIcon.centerYAnchor),
            volumeCard.topAnchor.constraint(equalTo: trustCard.bottomAnchor, constant: 14), volumeCard.leadingAnchor.constraint(equalTo: trustCard.leadingAnchor), volumeCard.trailingAnchor.constraint(equalTo: trustCard.trailingAnchor), volumeCard.heightAnchor.constraint(equalToConstant: 95),
            volumeIcon.leadingAnchor.constraint(equalTo: trustIcon.leadingAnchor), volumeIcon.centerYAnchor.constraint(equalTo: volumeCard.topAnchor, constant: 26), volumeIcon.widthAnchor.constraint(equalToConstant: 18),
            volumeTitle.leadingAnchor.constraint(equalTo: trust.leadingAnchor), volumeTitle.centerYAnchor.constraint(equalTo: volumeIcon.centerYAnchor),
            percentage.trailingAnchor.constraint(equalTo: volumeCard.trailingAnchor, constant: -22), percentage.centerYAnchor.constraint(equalTo: volumeIcon.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: volumeCard.leadingAnchor, constant: 18), slider.trailingAnchor.constraint(equalTo: volumeCard.trailingAnchor, constant: -22), slider.topAnchor.constraint(equalTo: volumeCard.topAnchor, constant: 48), slider.heightAnchor.constraint(equalToConstant: 26),
            protectionCard.topAnchor.constraint(equalTo: volumeCard.bottomAnchor, constant: 16), protectionCard.leadingAnchor.constraint(equalTo: trustCard.leadingAnchor), protectionCard.trailingAnchor.constraint(equalTo: trustCard.trailingAnchor),
            protectionIcon.leadingAnchor.constraint(equalTo: trustIcon.leadingAnchor), protectionIcon.topAnchor.constraint(equalTo: protection.topAnchor, constant: 1), protectionIcon.widthAnchor.constraint(equalToConstant: 18),
            protection.leadingAnchor.constraint(equalTo: trust.leadingAnchor), protection.trailingAnchor.constraint(equalTo: protectionCard.trailingAnchor, constant: -22), protection.topAnchor.constraint(equalTo: protectionCard.topAnchor, constant: 16), protection.bottomAnchor.constraint(equalTo: protectionCard.bottomAnchor, constant: -21),
            note.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: side), note.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -side), note.centerYAnchor.constraint(equalTo: root.bottomAnchor, constant: -(SketchFrame.inset.bottom + 22))
        ])
    }
    func refresh() {
        let fresh = engine.settingsRows()
        guard fresh != rows else { return }
        let selected = rows.indices.contains(picker.indexOfSelectedItem) ? rows[picker.indexOfSelectedItem].key : nil
        rows = fresh; picker.removeAllItems()
        picker.addItems(withTitles: rows.map { $0.name + ($0.active ? " · active" : " · saved") })
        if let selected, let index = rows.firstIndex(where: { $0.key == selected }) { picker.selectItem(at: index) }
        selectOutput()
    }
    func show() { refresh(); if window.isMiniaturized { window.deminiaturize(nil) }; NSApp.activate(ignoringOtherApps: true); window.present() }
    @objc func selectOutput() {
        guard rows.indices.contains(picker.indexOfSelectedItem) else { trust.isEnabled = false; slider.isEnabled = false; note.stringValue = "Select an output on your Mac to configure it."; return }
        let row = rows[picker.indexOfSelectedItem]
        trust.state = row.preference.trusted ? .on : .off; trust.isEnabled = row.supported || !row.active
        slider.doubleValue = Double(row.preference.volume); slider.isEnabled = row.supported || !row.active
        percentage.stringValue = "\(row.preference.volume)%"
        note.stringValue = row.active && !row.supported ? "This output has no software volume control." : ""
    }
    @objc func changeTrust() {
        guard rows.indices.contains(picker.indexOfSelectedItem) else { return }
        let row = rows[picker.indexOfSelectedItem]
        if trust.state == .on {
            let a = NSAlert(); a.messageText = "Trust \(row.name)?"; a.informativeText = "Switching to this output can enable audio without the two confirmations. It will start at your saved volume. This change will not turn sound on now."
            a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Trust output")
            if a.runModal() != .alertSecondButtonReturn { trust.state = .off; return }
        }
        var preference = row.preference; preference.trusted = trust.state == .on
        engine.savePreference(row.key, preference); refresh()
    }
    @objc func changeVolume() {
        guard rows.indices.contains(picker.indexOfSelectedItem) else { return }
        let value = Int(slider.doubleValue.rounded())
        percentage.stringValue = "\(value)%"
        // The label follows the knob; the preference is saved once the drag ends.
        if let type = NSApp.currentEvent?.type, type == .leftMouseDragged || type == .leftMouseDown { return }
        let row = rows[picker.indexOfSelectedItem]; var preference = row.preference; preference.volume = value
        engine.savePreference(row.key, preference); refresh()
    }
}
