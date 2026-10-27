import AppKit
import CoreAudio

/// Per-app volume levels, remembered by app name. 100% means "leave the app alone".
final class AppVolumeStore {
    private let key = "appVolumes"
    private(set) var volumes: [String: Int]
    init() { volumes = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:] }
    func volume(_ app: String) -> Int { volumes[app] ?? 100 }
    func set(_ app: String, _ value: Int) {
        let v = max(0, min(100, value))
        if v == 100 { volumes[app] = nil } else { volumes[app] = v }
        UserDefaults.standard.set(volumes, forKey: key)
    }
}

/// Read by the real-time audio thread; a plain Float is written atomically on Apple silicon and Intel.
final class GainBox { var value: Float = 1 }

/// Captures one app's output with a Core Audio process tap (macOS 14.2+), silences the original,
/// and plays it back through the same output device at `gain`.
@available(macOS 14.2, *)
final class ProcessTap {
    let objects: [AudioObjectID]
    let gain = GainBox()
    let createdAt = Date()
    /// Last time the tap delivered non-silent audio. Long silence while the app plays usually means capture isn't permitted.
    var lastSignal = Date.distantPast
    private var tapID = AudioObjectID(0), aggregateID = AudioObjectID(0)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "AlwaysMute.tap", qos: .userInteractive)

    /// `monitorOnly` listens without touching the app's own playback: used to tell real sound from an open-but-silent audio channel.
    init?(objects: [AudioObjectID], outputUID: String, name: String, monitorOnly: Bool = false) {
        self.objects = objects
        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = monitorOnly ? CATapMuteBehavior.unmuted : CATapMuteBehavior.mutedWhenTapped
        if monitorOnly { gain.value = 0 }
        description.isPrivate = true
        description.name = "AlwaysMute · \(name)"
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return nil }
        var uidAddress = Audio.address(kAudioTapPropertyUID), uid: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        _ = AudioObjectGetPropertyData(tapID, &uidAddress, 0, nil, &size, &uid)
        let tapUID = uid?.takeRetainedValue() as String? ?? description.uuid.uuidString
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AlwaysMute App Volume",
            kAudioAggregateDeviceUIDKey: "AlwaysMute-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]]
        ]
        guard AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregateID) == noErr else { destroy(); return nil }
        let gain = self.gain
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, output, _ in
            if ProcessTap.mix(input, into: output, gain: gain.value) { self?.lastSignal = Date() }
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else { destroy(); return nil }
    }
    /// Copies tapped audio to the output at `gain`, handling interleaved or split channel layouts. Returns whether any sound came in.
    static func mix(_ input: UnsafePointer<AudioBufferList>, into output: UnsafeMutablePointer<AudioBufferList>, gain: Float) -> Bool {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for o in outs where o.mData != nil { memset(o.mData, 0, Int(o.mDataByteSize)) }
        // Flatten the input into (buffer, channel-in-buffer) pairs.
        var sources: [(UnsafeMutablePointer<Float32>, Int, Int)] = []   // data, stride, offset
        var inFrames = Int.max
        for b in ins {
            guard let data = b.mData?.assumingMemoryBound(to: Float32.self), b.mNumberChannels > 0 else { continue }
            let ch = Int(b.mNumberChannels)
            inFrames = min(inFrames, Int(b.mDataByteSize) / (4 * ch))
            for k in 0..<ch { sources.append((data, ch, k)) }
        }
        guard !sources.isEmpty, inFrames != .max else { return false }
        var heard = false
        var channel = 0
        for o in outs {
            guard let out = o.mData?.assumingMemoryBound(to: Float32.self) else { continue }
            let ch = Int(max(1, o.mNumberChannels)), frames = min(inFrames, Int(o.mDataByteSize) / (4 * ch))
            for k in 0..<ch {
                let (src, stride, offset) = sources[(channel + k) % sources.count]
                for f in 0..<frames {
                    let sample = src[f * stride + offset]
                    // Above roughly -66 dB: ignores the dither some players emit while silent.
                    if abs(sample) > 0.0005 { heard = true }
                    out[f * ch + k] = sample * gain
                }
            }
            channel += ch
        }
        return heard
    }
    func destroy() {
        if aggregateID != 0 {
            if let procID { AudioDeviceStop(aggregateID, procID); AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = 0; procID = nil
        }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID); tapID = 0 }
    }
    deinit { destroy() }
}

/// Keeps a tap running for each playing app whose volume is below 100%.
final class AppVolumeManager {
    let store = AppVolumeStore()
    private var taps: [String: AnyObject] = [:]
    private var idlePolls: [String: Int] = [:]
    private var outputUID = ""
    /// Apps whose tap stayed silent while playing; skipped until their slider is moved again.
    private var blocked = Set<String>()
    private(set) var playing: [PlayingApp] = []
    var onChange: (() -> Void)?
    var onPermissionProblem: (() -> Void)?
    var supported: Bool { if #available(macOS 14.2, *) { return true } else { return false } }
    /// Perceived loudness follows roughly the square of the slider.
    static func gain(_ volume: Int) -> Float { let x = Float(volume) / 100; return x * x }

    func sync(_ playing: [PlayingApp]) {
        let changed = playing.map(\.name) != self.playing.map(\.name)
        self.playing = playing
        if changed { onChange?() }
        guard #available(macOS 14.2, *) else { return }
        let uid = Audio.defaultOutputUID()
        if uid != outputUID { outputUID = uid; taps.removeAll() }
        guard !uid.isEmpty else { return }
        for app in playing {
            idlePolls[app.name] = 0
            let volume = store.volume(app.name)
            guard volume < 100, !blocked.contains(app.name) else { taps[app.name] = nil; continue }
            if let tap = taps[app.name] as? ProcessTap, tap.objects == app.objects {
                tap.gain.value = Self.gain(volume)
                // Silent for 3s after starting while the app plays: most likely no capture permission. Hand the app its audio back.
                if Date().timeIntervalSince(tap.createdAt) > 3, Date().timeIntervalSince(tap.lastSignal) > 3 {
                    taps[app.name] = nil; blocked.insert(app.name); onPermissionProblem?()
                }
                continue
            }
            let tap = ProcessTap(objects: app.objects, outputUID: uid, name: app.name)
            tap?.gain.value = Self.gain(volume)
            taps[app.name] = tap
        }
        for name in Array(taps.keys) where !playing.contains(where: { $0.name == name }) {
            idlePolls[name, default: 0] += 1
            if idlePolls[name]! > 6 { taps[name] = nil }
        }
    }
    /// When the app-volume tap for this app last carried real sound, if it has one.
    func lastSignal(for app: String) -> Date? {
        guard #available(macOS 14.2, *) else { return nil }
        return (taps[app] as? ProcessTap)?.lastSignal
    }
    func setVolume(_ app: String, _ volume: Int) {
        store.set(app, volume)
        blocked.remove(app)
        guard #available(macOS 14.2, *) else { return }
        if volume >= 100 { taps[app] = nil }
        else if let tap = taps[app] as? ProcessTap { tap.gain.value = Self.gain(volume) }
        else { sync(playing) }
    }
    /// Rows for the window: apps playing now, then apps with a saved level.
    var rows: [(name: String, playing: PlayingApp?)] {
        var result = playing.map { (name: $0.name, playing: Optional($0)) }
        for name in store.volumes.keys.sorted() where !result.contains(where: { $0.name == name }) { result.append((name: name, playing: nil)) }
        return result
    }
}

/// "App volumes" window: one sketch slider per app.
final class AppVolumesWindow: NSObject {
    let window: SketchWindow
    private let manager: AppVolumeManager
    private let card = NSStackView()
    private let empty = Style.label("Nothing is playing right now.", size: 13, weight: .medium, color: Style.muted)
    private let permission = NSStackView()
    private var shown: [String] = []
    init(manager: AppVolumeManager) {
        self.manager = manager
        window = SketchWindow(title: "App volumes", size: NSSize(width: 440, height: 360), footer: 44, resizable: true, minimum: NSSize(width: 380, height: 300))
        super.init()
        let root = window.frameView
        let side = SketchFrame.inset.left + 24
        let pill = SketchPill(), pillIcon = Style.icon("slider.vertical.3", size: 13, weight: .medium), pillText = NSTextField(labelWithString: "Volume for each app")
        pillText.font = Style.mono(13.5); pillText.textColor = Artwork.ink
        card.orientation = .vertical; card.alignment = .leading; card.spacing = 0
        let box = SketchCard(rows: 1); box.dividers = false
        let settingsLink = SketchLink("Open Privacy settings", symbol: "lock.shield", target: self, action: #selector(openPrivacy))
        let permissionText = Style.label("Allow audio access to change app volumes.", size: 12, weight: .medium, color: Style.warning)
        permission.orientation = .horizontal; permission.spacing = 10; permission.setViews([permissionText, settingsLink], in: .center); permission.isHidden = true
        for v in [pill, box, empty, permission] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        for v in [pillIcon, pillText] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; pill.addSubview(v) }
        card.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(card)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: side - 6), pill.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -(side - 6)), pill.centerYAnchor.constraint(equalTo: root.topAnchor, constant: SketchFrame.inset.top + SketchFrame.band + SketchFrame.toolbar / 2), pill.heightAnchor.constraint(equalToConstant: 34),
            pillIcon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16), pillIcon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pillText.leadingAnchor.constraint(equalTo: pillIcon.trailingAnchor, constant: 8), pillText.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            box.topAnchor.constraint(equalTo: root.topAnchor, constant: SketchFrame.contentTop + 14), box.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: side - 4), box.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -(side - 9)),
            card.topAnchor.constraint(equalTo: box.topAnchor, constant: SketchCard.top + 6), card.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 2), card.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -5), card.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -(SketchCard.extra - SketchCard.top) - 6),
            empty.centerXAnchor.constraint(equalTo: box.centerXAnchor), empty.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            permission.centerXAnchor.constraint(equalTo: root.centerXAnchor, constant: -2), permission.centerYAnchor.constraint(equalTo: root.bottomAnchor, constant: -(SketchFrame.inset.bottom + 22))
        ])
        rebuild()
    }
    func show() { rebuild(force: true); NSApp.activate(ignoringOtherApps: true); window.present() }
    func showPermissionHint() { permission.isHidden = false }
    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
    }
    /// Rebuilds rows only when the list of apps changes, so a slider being dragged is never replaced.
    func rebuild(force: Bool = false) {
        let rows = manager.rows
        guard force || rows.map(\.name) != shown else { return }
        shown = rows.map(\.name)
        card.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in rows {
            let view = AppVolumeRow(name: row.name, playing: row.playing, volume: manager.store.volume(row.name)) { [weak self] value in self?.manager.setVolume(row.name, value) }
            card.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: card.widthAnchor).isActive = true
        }
        empty.isHidden = !rows.isEmpty
        // Fit the window to its rows, top edge fixed.
        let height = SketchFrame.contentTop + 14 + CGFloat(max(1, rows.count)) * AppVolumeRow.height + 12 + SketchCard.extra + 30 + 44 + SketchFrame.inset.bottom
        var frame = window.frame
        let target = max(window.contentMinSize.height, height)
        if abs(frame.height - target) > 1 { frame.origin.y += frame.height - target; frame.size.height = target; window.setFrame(frame, display: true, animate: window.isVisible) }
    }
}

final class AppVolumeRow: NSView {
    static let height: CGFloat = 56
    private let percentage = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let onChange: (Int) -> Void
    init(name: String, playing: PlayingApp?, volume: Int, onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        let icon = NSImageView()
        icon.image = playing.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }
            ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
            ?? ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"].lazy.map { "\($0)/\(name).app" }.first { FileManager.default.fileExists(atPath: $0) }.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: name)
        title.font = Style.font(13.5, .semibold); title.textColor = Artwork.ink.withAlphaComponent(playing == nil ? 0.5 : 1); title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        slider.cell = SketchSliderCell(); slider.minValue = 0; slider.maxValue = 100; slider.doubleValue = Double(volume); slider.isContinuous = true
        slider.target = self; slider.action = #selector(changed); slider.setAccessibilityLabel("\(name) volume")
        percentage.font = Style.mono(13, .semibold); percentage.textColor = Artwork.ink; percentage.alignment = .right; percentage.stringValue = "\(volume)%"
        for v in [icon, title, slider, percentage] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), icon.centerYAnchor.constraint(equalTo: centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 26), icon.heightAnchor.constraint(equalToConstant: 26),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), title.centerYAnchor.constraint(equalTo: centerYAnchor), title.widthAnchor.constraint(equalToConstant: 124),
            slider.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10), slider.centerYAnchor.constraint(equalTo: centerYAnchor), slider.heightAnchor.constraint(equalToConstant: 26),
            percentage.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10), percentage.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18), percentage.widthAnchor.constraint(equalToConstant: 46), percentage.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func changed() {
        let value = Int(slider.doubleValue.rounded())
        percentage.stringValue = "\(value)%"
        onChange(value)
    }
}
