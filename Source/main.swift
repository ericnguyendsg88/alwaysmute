import AppKit
import CoreAudio
import ServiceManagement

struct Control {
    let device: AudioObjectID
    var address: AudioObjectPropertyAddress
    func read<T: BitwiseCopyable>(_ initial: T) -> T? {
        var value = initial, size = UInt32(MemoryLayout<T>.size), a = address
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr ? value : nil
    }
    var writable: Bool {
        var a = address, result = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &a, &result) == noErr && result.boolValue
    }
    @discardableResult func write<T: BitwiseCopyable>(_ value: T) -> Bool {
        var v = value, a = address
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }
}
struct Output {
    let id: AudioObjectID
    let name: String
    let route: RouteIdentity
    let mutes: [Control]
    let volumes: [Control]
    var supported: Bool { !mutes.isEmpty || !volumes.isEmpty }
    var silent: Bool {
        let muted = !mutes.isEmpty && mutes.allSatisfy { $0.read(UInt32(0)) == 1 }
        let zero = !volumes.isEmpty && volumes.allSatisfy { ($0.read(Float32(1)) ?? 1) <= 0.0001 }
        return muted || zero
    }
    var disturbed: Bool {
        mutes.contains { $0.read(UInt32(1)) != 1 } || volumes.contains { ($0.read(Float32(0)) ?? 0) > 0.0001 }
    }
    var level: Float { volumes.compactMap { $0.read(Float32(0)) }.max() ?? 0 }
    func lock() {
        mutes.forEach { if $0.read(UInt32(0)) != 1 { $0.write(UInt32(1)) } }
        volumes.forEach { if $0.read(Float32(1)) != 0 { $0.write(Float32(0)) } }
    }
    func unlock(volume: Int) -> Bool {
        // Devices without a software volume control cannot promise a quiet start.
        guard !volumes.isEmpty else { return false }
        guard volumes.allSatisfy({ $0.write(Float32(max(1, min(100, volume))) / 100) }) else { lock(); return false }
        guard mutes.allSatisfy({ $0.write(UInt32(0)) }) else { lock(); return false }
        return true
    }
}
enum Audio {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    static func defaults() -> [AudioObjectID] {
        [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice].compactMap {
            Control(device: AudioObjectID(kAudioObjectSystemObject), address: address($0)).read(AudioObjectID(0))
        }.filter { $0 != 0 }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
    static func allDevices() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyDevices), bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &bytes) == noErr else { return [] }
        guard bytes > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
        let result = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &bytes, $0.baseAddress!) }
        return result == noErr ? ids : []
    }
    static func route(_ id: AudioObjectID) -> RouteIdentity {
        var uid: Unmanaged<CFString>?, bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var a = address(kAudioDevicePropertyDeviceUID)
        _ = AudioObjectGetPropertyData(id, &a, 0, nil, &bytes, &uid)
        let stable = uid?.takeRetainedValue() as String? ?? ""
        let source = Control(device: id, address: address(kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput)).read(UInt32(0))
        let jack = Control(device: id, address: address(kAudioDevicePropertyJackIsConnected, kAudioDevicePropertyScopeOutput)).read(UInt32(0))
        let transport = Control(device: id, address: address(kAudioDevicePropertyTransportType)).read(UInt32(0))
        let key = stable.isEmpty ? "" : "\(stable)|source:\(source.map(String.init) ?? "none")|jack:\(jack.map(String.init) ?? "none")"
        return RouteIdentity(id: id, key: key, builtIn: transport == kAudioDeviceTransportTypeBuiltIn, source: source, jack: jack)
    }
    static func outputChannels(_ id: AudioObjectID) -> UInt32 {
        var config = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &config, 0, nil, &bytes) == noErr, bytes > 0 else { return 0 }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(id, &config, 0, nil, &bytes, data) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + $1.mNumberChannels }
    }
    /// Devices the user could pick as the default output, in system order.
    static func outputDevices() -> [AudioObjectID] {
        allDevices().filter { id in
            outputChannels(id) > 0 && Control(device: id, address: address(kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyScopeOutput)).read(UInt32(0)) == 1
                && Control(device: id, address: address(kAudioDevicePropertyIsHidden)).read(UInt32(0)) != 1
        }
    }
    static func symbol(_ id: AudioObjectID) -> String {
        let transport = Control(device: id, address: address(kAudioDevicePropertyTransportType)).read(UInt32(0)) ?? 0
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return route(id).jack == 1 ? "headphones" : "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return "waveform"
        default: return "hifispeaker"
        }
    }
    /// Apps currently sending audio to an output (macOS 14.2+ process objects). Helpers are folded into their app's name.
    static func appsPlaying() -> [PlayingApp] {
        guard #available(macOS 14.2, *) else { return [] }
        var a = address(kAudioHardwarePropertyProcessObjectList), bytes: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &bytes) == noErr, bytes > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
        guard ids.withUnsafeMutableBytes({ AudioObjectGetPropertyData(system, &a, 0, nil, &bytes, $0.baseAddress!) }) == noErr else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        var result: [PlayingApp] = []
        for id in ids {
            guard Control(device: id, address: address(kAudioProcessPropertyIsRunningOutput)).read(UInt32(0)) == 1,
                  let pid = Control(device: id, address: address(kAudioProcessPropertyPID)).read(pid_t(0)), pid > 0, pid != me else { continue }
            var bundle: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size), b = address(kAudioProcessPropertyBundleID)
            _ = AudioObjectGetPropertyData(id, &b, 0, nil, &size, &bundle)
            let bundleID = bundle?.takeRetainedValue() as String? ?? ""
            let owner = PlayingApp.owner(pid: pid, bundleID: bundleID)
            guard !owner.name.isEmpty else { continue }
            if let i = result.firstIndex(where: { $0.name == owner.name }) { result[i].objects.append(id) }
            else { result.append(PlayingApp(name: owner.name, pid: owner.pid, objects: [id])) }
        }
        return result
    }
    static func defaultOutputUID() -> String {
        guard let id = defaults().first else { return "" }
        var uid: Unmanaged<CFString>?, bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size), a = address(kAudioDevicePropertyDeviceUID)
        _ = AudioObjectGetPropertyData(id, &a, 0, nil, &bytes, &uid)
        return uid?.takeRetainedValue() as String? ?? ""
    }
    static func setDefaultOutput(_ id: AudioObjectID) -> Bool {
        Control(device: AudioObjectID(kAudioObjectSystemObject), address: address(kAudioHardwarePropertyDefaultOutputDevice)).write(id)
    }
    static func output(_ id: AudioObjectID) -> Output {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size), a = address(kAudioObjectPropertyName)
        _ = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name)
        let channelCount = outputChannels(id)
        func controls(_ selector: AudioObjectPropertySelector) -> [Control] {
            let master = Control(device: id, address: address(selector, kAudioDevicePropertyScopeOutput))
            if master.writable { return [master] }
            guard channelCount > 0 else { return [] }
            let channels = (1...channelCount).map { Control(device: id, address: address(selector, kAudioDevicePropertyScopeOutput, $0)) }
            // Partial channel control must never be described as full protection.
            return channels.allSatisfy(\.writable) ? channels : []
        }
        return Output(id: id, name: name?.takeRetainedValue() as String? ?? "Audio output", route: route(id), mutes: controls(kAudioDevicePropertyMute), volumes: controls(kAudioDevicePropertyVolumeScalar))
    }
}
struct Gate {
    private(set) var locked = true
    private(set) var generation = 0
    mutating func invalidateConfirmation() { generation += 1 }
    mutating func lock() { locked = true; generation += 1 }
    mutating func allow(token: Int) -> Bool {
        guard token == generation, locked else { return false }
        locked = false; return true
    }
}
struct Snapshot {
    let locked: Bool
    let safe: Bool
    let names: String
    let level: Int
    let canUnmute: Bool
    let startingText: String
    let reason: String
    var volumes: [StartingVolume] = []
}
struct PlayingApp: Equatable {
    let name: String
    let pid: pid_t
    /// Core Audio process objects for the app and its helpers, used to tap its audio.
    var objects: [AudioObjectID] = []
    /// Audio often comes from a helper process ("com.google.Chrome.helper"). Resolve it to the app the user knows:
    /// walk up to the owning app, else look the helper's bundle up without its ".helper" suffix.
    static func owner(pid: pid_t, bundleID: String) -> (name: String, pid: pid_t) {
        if bundleID.hasPrefix("com.apple.WebKit") { return ("Safari", NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.processIdentifier ?? pid) }
        var current = pid
        for _ in 0..<6 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular, let name = app.localizedName { return (name, current) }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else { break }
            current = pid_t(info.pbi_ppid)
        }
        // No owning app in the process tree: try the bundle ID with helper suffixes removed.
        var parts = bundleID.split(separator: ".").map(String.init)
        while let last = parts.last, last.lowercased().contains("helper") || last.lowercased() == "renderer" || last.lowercased() == "gpu" { parts.removeLast() }
        let parent = parts.joined(separator: ".")
        if !parent.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parent) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return (name, NSRunningApplication.runningApplications(withBundleIdentifier: parent).first?.processIdentifier ?? pid)
        }
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return (name.components(separatedBy: " Helper").first ?? name, pid) }
        var buffer = [CChar](repeating: 0, count: 256)
        let processName = proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
        return (parts.last ?? processName, pid)
    }
}
struct OutputChoice: Equatable {
    let id: AudioObjectID
    let name: String
    let symbol: String
    let current: Bool
    let controllable: Bool
}
struct StartingVolume: Equatable {
    let name: String
    let volume: Int
}
final class GuardEngine {
    let queue = DispatchQueue(label: "AlwaysMute.audio", qos: .userInteractive)
    var gate = Gate()
    var outputs: [Output] = []
    var allowed = Set<AudioObjectID>()
    let preferences = OutputPreferences()
    var reason = "Headphone protection is on"
    var trustAfter = Date().addingTimeInterval(3)
    var protectionPauses = Set<String>()
    var timer: DispatchSourceTimer?
    var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    var onUpdate: ((Snapshot) -> Void)?
    /// A volume key press while locked. `raised` is true when the level went up (Volume Up); a mute-only change means Mute or Volume Down.
    var onAttempt: ((_ raised: Bool) -> Void)?
    var lastAttempt = Date.distantPast
    /// Devices settling after a route change can report volume changes; ignore those briefly.
    var quietUntil = Date.distantPast
    /// Direction of a press being collected; nil when no press is pending.
    var pendingRaise: Bool?
    var lastSnapshot = ""
    func start() {
        queue.sync {
            refresh()
            for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDevices] {
                listen(AudioObjectID(kAudioObjectSystemObject), Audio.address(selector)) { [weak self] in self?.refresh() }
            }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(100))
            t.setEventHandler { [weak self] in self?.check() }
            t.resume(); timer = t
        }
    }
    func listen(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, action: @escaping () -> Void) {
        var a = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in action() }
        if AudioObjectAddPropertyListenerBlock(id, &a, queue, block) == noErr { listeners.append((id, a, block)) }
    }
    func refresh() {
        let ids = Audio.defaults(), routes = Audio.defaults().map(Audio.route)
        guard routes != outputs.map(\.route) else { return }
        let previousRoutes = outputs.map(\.route)
        let previous = outputs.first?.route
        let fallback = RoutePolicy.fallback(old: previous, new: routes.first, available: Set(Audio.allDevices()))
        gate.lock(); allowed.removeAll()
        for (id, var a, block) in listeners where id != AudioObjectID(kAudioObjectSystemObject) {
            AudioObjectRemovePropertyListenerBlock(id, &a, queue, block)
        }
        listeners.removeAll { $0.0 != AudioObjectID(kAudioObjectSystemObject) }
        outputs = ids.map(Audio.output)
        outputs.forEach { $0.lock() }
        for output in outputs {
            if !output.route.key.isEmpty {
                var p = preferences.value(output.route.key, name: output.name); p.name = output.name
                preferences.save(output.route.key, p)
            }
            for control in output.mutes + output.volumes { listen(output.id, control.address) { [weak self] in self?.check() } }
            for selector in [kAudioDevicePropertyDataSource, kAudioDevicePropertyJackIsConnected] {
                listen(output.id, Audio.address(selector, kAudioDevicePropertyScopeOutput)) { [weak self] in self?.refresh() }
            }
        }
        reason = fallback ? "Output disconnected or speakers selected · muted" : "New output · confirmation required"
        // Startup always stays muted. Trust only applies to a later route transition.
        if previous != nil && !fallback && protectionPauses.isEmpty && Date() >= trustAfter {
            for output in outputs {
                let p = preferences.value(output.route.key, name: output.name)
                if !previousRoutes.contains(output.route), RoutePolicy.canTrust(key: output.route.key, supported: !output.volumes.isEmpty, fallback: fallback, trusted: p.trusted), output.unlock(volume: p.volume) {
                    allowed.insert(output.id)
                }
            }
            if !allowed.isEmpty { _ = gate.allow(token: gate.generation); reason = "Trusted output allowed · other outputs stay muted" }
        }
        if previous == nil { reason = "Headphone protection is on" }
        quietUntil = Date().addingTimeInterval(3); publish()
    }
    func check() {
        if Audio.defaults().map(Audio.route) != outputs.map(\.route) { refresh(); return }
        let guarded = outputs.filter { !allowed.contains($0.id) }
        let disturbed = guarded.contains { $0.supported && $0.disturbed }
        let raised = guarded.contains { $0.level > 0.0001 }
        guarded.forEach { $0.lock() }
        if outputs.contains(where: { allowed.contains($0.id) && $0.silent }) {
            lockInternal(reason: "Manually muted · protection restored")
        }
        // Report every distinct press (not every 100 ms tick) so an open check can react to each one.
        // One Volume Up press arrives as two changes (unmute, then volume), in either order, so the
        // press is classified after a short window: it counts as "raised" if the level rose at any point.
        // Outputs are already re-locked above; only the report waits.
        if disturbed && Date() > quietUntil {
            if pendingRaise != nil { pendingRaise = pendingRaise! || raised }
            else if Date().timeIntervalSince(lastAttempt) > 0.35 {
                lastAttempt = Date(); pendingRaise = raised
                queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, let result = self.pendingRaise else { return }
                    self.pendingRaise = nil
                    DispatchQueue.main.async { self.onAttempt?(result) }
                }
            }
        }
        publish()
    }
    func publish() {
        let starting = outputs.map { "\($0.name): \(preferences.value($0.route.key, name: $0.name).volume)%" }.joined(separator: ", ")
        let snapshot = Snapshot(locked: allowed.isEmpty, safe: !outputs.isEmpty && outputs.allSatisfy { $0.supported && (allowed.contains($0.id) || $0.silent) }, names: outputs.map(\.name).joined(separator: ", "), level: Int((outputs.map(\.level).max() ?? 0) * 100), canUnmute: !outputs.isEmpty && outputs.allSatisfy { !$0.volumes.isEmpty }, startingText: starting, reason: reason, volumes: outputs.map { StartingVolume(name: $0.name, volume: preferences.value($0.route.key, name: $0.name).volume) })
        let key = "\(snapshot)"
        if key != lastSnapshot { lastSnapshot = key; DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) } }
    }
    func lockInternal(reason: String) { trustAfter = Date().addingTimeInterval(3); gate.lock(); allowed.removeAll(); self.reason = reason; outputs.forEach { $0.lock() }; publish() }
    func lock() { queue.sync { lockInternal(reason: "Muted and locked · headphone protection on") } }
    func lock(reason: String) { queue.sync { lockInternal(reason: reason) } }
    func setProtectionPause(_ key: String, active: Bool) {
        queue.sync {
            if active { protectionPauses.insert(key) } else { protectionPauses.remove(key) }
            lockInternal(reason: "Sleep or screen lock · protection restored")
        }
    }
    func token() -> Int { queue.sync { gate.generation } }
    func outputChoices() -> [OutputChoice] {
        queue.sync {
            let current = Audio.defaults().first
            return Audio.outputDevices().map { id in
                let o = Audio.output(id)
                return OutputChoice(id: id, name: o.name, symbol: Audio.symbol(id), current: id == current, controllable: !o.volumes.isEmpty)
            }
            // Outputs without software volume can't be kept muted, so only offer them if already selected.
            .filter { $0.controllable || $0.current }
        }
    }
    /// Switches the default output. The destination is muted first, then goes through the usual route rules.
    func switchOutput(to id: AudioObjectID) -> Bool {
        queue.sync {
            Audio.output(id).lock()
            guard Audio.setDefaultOutput(id) else { return false }
            refresh(); return true
        }
    }
    func settingsRows() -> [OutputSettingRow] {
        queue.sync {
            preferences.entries.map { key, p in
                let output = outputs.first { $0.route.key == key }
                return OutputSettingRow(key: key, name: p.name, active: output != nil, supported: output.map { !$0.volumes.isEmpty } ?? false, preference: p)
            }.sorted { $0.active != $1.active ? $0.active : $0.name < $1.name }
        }
    }
    func savePreference(_ key: String, _ p: OutputPreference) {
        queue.sync {
            let old = preferences.value(key, name: p.name)
            preferences.save(key, p)
            // Editing next-start volume does not interrupt current playback.
            gate.invalidateConfirmation()
            if old.trusted && !p.trusted && outputs.contains(where: { $0.route.key == key && allowed.contains($0.id) }) {
                lockInternal(reason: "Trust removed · protection restored")
            } else { reason = "Output settings saved"; publish() }
        }
    }
    func allow(token: Int) -> Bool {
        queue.sync {
            guard protectionPauses.isEmpty, Audio.defaults().map(Audio.route) == outputs.map(\.route), !outputs.isEmpty, outputs.allSatisfy({ !$0.volumes.isEmpty }), gate.allow(token: token) else { return false }
            for output in outputs {
                guard output.unlock(volume: preferences.value(output.route.key, name: output.name).volume) else { lockInternal(reason: "Could not safely enable output"); return false }
                allowed.insert(output.id)
            }
            reason = "Sound confirmed · no time limit"; publish(); return true
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = GuardEngine()
    var status: NSStatusItem!
    var stateItem = NSMenuItem(title: "Starting protection…", action: nil, keyEquivalent: "")
    var deviceItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var volumeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var allowItem = NSMenuItem(title: "Allow sound…", action: #selector(confirmFromMenuBar), keyEquivalent: "")
    var loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
    var promptOpen = false
    var lastPromptEnd = Date.distantPast
    var lastMediaKey = Date.distantPast
    let playPrompt = PlayPrompt()
    let appVolumes = AppVolumeManager()
    var appVolumesWindow: AppVolumesWindow?
    @objc func showAppVolumes() {
        if appVolumesWindow == nil { appVolumesWindow = AppVolumesWindow(manager: appVolumes) }
        appVolumesWindow?.show()
    }
    var playTimer: Timer?
    /// Consecutive polls each app has been playing, and apps already asked about during their current run.
    var playStreak: [String: Int] = [:]
    var askedApps = Set<String>()
    var mediaMonitor: Any?
    var snapshot: Snapshot?
    var observers: [NSObjectProtocol] = []
    var settings: OutputSettingsWindow?
    @objc func showOutputSettings() {
        if settings == nil { settings = OutputSettingsWindow(engine: engine) }
        settings?.show()
    }
    var interface: QuietInterface?
    @objc func showWindow() {
        if interface == nil { interface = QuietInterface(owner: self) }
        if let s = snapshot { interface?.render(s, promptOpen: promptOpen) }
        refreshLogin()
        if interface?.window.isMiniaturized == true { interface?.window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true); interface?.window.present()
    }
    @objc func primaryAction() {
        if snapshot?.locked == false { muteNow() } else { confirmSound() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.QuietGuard")
        if others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { NSApp.terminate(nil); return }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = Style.mascotGlyph()
        let menu = NSMenu()
        let title = NSMenuItem(title: "AlwaysMute", action: nil, keyEquivalent: "")
        menu.addItem(title)
        let open = NSMenuItem(title: "Open AlwaysMute", action: #selector(showWindow), keyEquivalent: ""); open.target = self; menu.addItem(open)
        menu.addItem(stateItem); menu.addItem(deviceItem); menu.addItem(volumeItem); menu.addItem(.separator())
        allowItem.target = self; menu.addItem(allowItem)
        let mute = NSMenuItem(title: "Mute and lock now", action: #selector(muteNow), keyEquivalent: "m"); mute.target = self; menu.addItem(mute)
        menu.addItem(.separator())
        let volumesItem = NSMenuItem(title: "App volumes…", action: #selector(showAppVolumes), keyEquivalent: ""); volumesItem.target = self; menu.addItem(volumesItem)
        let outputSettings = NSMenuItem(title: "Output settings…", action: #selector(showOutputSettings), keyEquivalent: ","); outputSettings.target = self; menu.addItem(outputSettings)
        loginItem.target = self; refreshLogin(); menu.addItem(loginItem)
        let about = NSMenuItem(title: "About protection…", action: #selector(aboutProtection), keyEquivalent: ""); about.target = self; menu.addItem(about)
        let quit = NSMenuItem(title: "Quit AlwaysMute…", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        status.menu = menu
        SketchWindow.menuBarTarget = { [weak self] in self?.status.button?.window?.frame }
        engine.onUpdate = { [weak self] in self?.render($0) }
        engine.onAttempt = { [weak self] raised in
            guard let self else { return }
            if self.playPrompt.isOpen {
                guard Date().timeIntervalSince(self.lastMediaKey) > 0.6 else { return }
                self.playPrompt.key(raised ? .up : .mute, command: NSEvent.modifierFlags.contains(.command)); return
            }
            if self.promptOpen {
                // The media-key monitor below already answered this press precisely.
                guard Date().timeIntervalSince(self.lastMediaKey) > 0.6 else { return }
                // Fallback when AlwaysMute isn't frontmost: infer the key from what changed on the output.
                self.showWindow(); self.interface?.volumeKey(raised ? .up : .mute, command: NSEvent.modifierFlags.contains(.command))
            } else if Date().timeIntervalSince(self.lastMediaKey) > 0.6 { self.idleVolumeKey(up: raised) }
        }
        // While AlwaysMute is frontmost, macOS delivers the media keys themselves: exact key and modifiers.
        mediaMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8, let self else { return event }
            let code = (event.data1 & 0xFFFF0000) >> 16, state = (event.data1 & 0xFF00) >> 8, isRepeat = event.data1 & 0x1 == 1
            // NX_KEYTYPE_SOUND_UP = 0, SOUND_DOWN = 1, MUTE = 7; 0xA is key-down.
            guard state == 0xA, !isRepeat, let key: QuietInterface.VolumeKey = [0: .up, 1: .down, 7: .mute][code] else { return event }
            self.lastMediaKey = Date()
            if self.playPrompt.isOpen { self.playPrompt.key(key, command: event.modifierFlags.contains(.command)) }
            else if self.promptOpen { self.interface?.volumeKey(key, command: event.modifierFlags.contains(.command)) }
            else { self.idleVolumeKey(up: key == .up) }
            return event
        }
        engine.start()
        appVolumes.onChange = { [weak self] in self?.appVolumesWindow?.rebuild() }
        appVolumes.onPermissionProblem = { [weak self] in self?.showAppVolumes(); self?.appVolumesWindow?.showPermissionHint() }
        // Ask when an app starts playing while muted (needs macOS 14.2+ to know which app).
        playTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.pollPlayback() }
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, String, Bool)] = [
            (NSWorkspace.willSleepNotification, "sleep", true), (NSWorkspace.didWakeNotification, "sleep", false),
            (NSWorkspace.screensDidSleepNotification, "display", true), (NSWorkspace.screensDidWakeNotification, "display", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true), (NSWorkspace.sessionDidBecomeActiveNotification, "session", false)
        ]
        for (name, key, active) in events {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.engine.setProtectionPause(key, active: active) })
        }
        for (name, active) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.engine.setProtectionPause("lock", active: active) })
        }
        showWindow()
    }
    func render(_ s: Snapshot) {
        if let previous = snapshot, !previous.locked, s.locked {
            if !s.reason.hasPrefix("New app playing") { announceMuted(s.reason) }
        }
        snapshot = s
        settings?.refresh()
        stateItem.title = !s.safe ? "⚠︎ Protection unavailable" : s.locked ? "Muted and locked" : "Sound allowed"
        deviceItem.title = s.names.isEmpty ? "No audio output found" : s.names
        volumeItem.title = "Output volume: \(s.level)%"
        allowItem.isEnabled = s.locked && s.safe && s.canUnmute && !promptOpen
        status.button?.image = s.safe ? Style.mascotGlyph(muted: s.locked) : NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: stateItem.title)
        status.button?.title = !s.safe ? " !" : ""
        interface?.render(s, promptOpen: promptOpen)
        status.button?.toolTip = "AlwaysMute — \(stateItem.title)\n\(s.names)"
    }
    @objc func confirmSound() {
        // Both steps run inside the main window; asking again just brings it forward.
        guard !promptOpen else { showWindow(); return }
        // Sound is already on: nothing to confirm, and locking here would mute it.
        guard snapshot?.locked != false else { return }
        playPrompt.close()
        engine.lock()
        guard let s = snapshot, s.safe, s.canUnmute else { return }
        showWindow()
        promptOpen = true; allowItem.isEnabled = false
        let token = engine.token()
        interface?.beginVerification(s) { [weak self] allowed in
            guard let self else { return }
            self.promptOpen = false; self.lastPromptEnd = Date()
            if allowed {
                if self.engine.allow(token: token) {
                    self.approvedApps.formUnion(Audio.appsPlaying().map(\.name))
                    // Sound is on: get out of the way once the "Sound allowed" state has registered.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        for case let window as SketchWindow in NSApp.windows where window.isVisible { window.collapseToMenuBar() }
                    }
                } else {
                    let alert = NSAlert(); alert.messageText = "Sound stayed locked"; alert.informativeText = "The audio device or protection state changed, or volume could not be set safely. Try again from the menu bar."; alert.runModal()
                }
            }
            if let s = self.snapshot { self.render(s) }
        }
    }
    @objc func muteNow() { engine.lock() }
    /// The two-step check as a small pop-up under the menu bar icon, for Volume Up and the menu bar menu.
    @objc func confirmFromMenuBar() {
        guard !promptOpen else { return }
        guard snapshot?.locked != false else { return }
        engine.lock()
        guard let s = snapshot, s.safe, s.canUnmute else { return }
        promptOpen = true; allowItem.isEnabled = false; interface?.render(s, promptOpen: true)
        let token = engine.token()
        playPrompt.volumeText = s.volumes.map { "\($0.volume)%" }.joined(separator: " / ")
        playPrompt.onAllow = { [weak self] in
            guard let self else { return }
            if self.engine.allow(token: token) { self.approvedApps.formUnion(Audio.appsPlaying().map(\.name)) }
            else { self.toast.show(title: "Sound stayed muted.", detail: "", below: self.status.button?.window?.frame) }
        }
        playPrompt.onClose = { [weak self] in
            guard let self else { return }
            self.promptOpen = false; self.lastPromptEnd = Date()
            if let s = self.snapshot { self.render(s) }
        }
        playPrompt.showSoundCheck(output: s.names, below: status.button?.window?.frame)
    }
    /// Apps allowed to play while sound is on: those already playing when sound was turned on, plus any confirmed since.
    /// Remembered across mutes and restarts: an app you've said yes to doesn't ask again.
    var approvedApps = Set(UserDefaults.standard.stringArray(forKey: "approvedApps") ?? []) {
        didSet { if approvedApps != oldValue { UserDefaults.standard.set(approvedApps.sorted(), forKey: "approvedApps") } }
    }
    /// Silent listeners on not-yet-approved apps (macOS 14.2+, needs the system-audio permission).
    var probes: [String: AnyObject] = [:]
    /// Set once any tap has carried real audio, i.e. the permission is granted. From then on only real sound asks.
    var captureWorks = UserDefaults.standard.bool(forKey: "audioCaptureWorks") {
        didSet { if captureWorks != oldValue { UserDefaults.standard.set(captureWorks, forKey: "audioCaptureWorks") } }
    }
    /// Whether this app is making actual sound right now, as far as AlwaysMute can tell.
    func isSounding(_ app: PlayingApp) -> Bool {
        let steady = (playStreak[app.name] ?? 0) >= 2
        guard #available(macOS 14.2, *) else { return steady }
        let heard = [appVolumes.lastSignal(for: app.name), (probes[app.name] as? ProcessTap)?.lastSignal].compactMap { $0 }.max() ?? .distantPast
        let recent = Date().timeIntervalSince(heard) < 1.2
        if recent { captureWorks = true }
        // Until listening is known to work, fall back to "has had an audio channel open for a moment".
        return captureWorks ? recent : steady
    }
    /// While sound is on, a newly playing app is paused behind mute until confirmed. While muted, nothing asks.
    func pollPlayback() {
        let playing = Audio.appsPlaying(), names = Set(playing.map(\.name))
        appVolumes.sync(playing)
        playStreak = playStreak.filter { names.contains($0.key) }
        for name in names { playStreak[name, default: 0] += 1 }
        askedApps.formIntersection(names)
        if let app = playPrompt.app, !names.contains(app.name) { playPrompt.close() }
        // Keep a listener on each unapproved app while sound is on (or while its question is showing).
        let watching = (snapshot?.locked == false || playPrompt.isOpen) && !promptOpen
        let candidates = watching ? playing.filter { !approvedApps.contains($0.name) && !askedApps.contains($0.name) } : []
        if #available(macOS 14.2, *) {
            let uid = Audio.defaultOutputUID()
            for name in Array(probes.keys) where !candidates.contains(where: { $0.name == name && ($0.objects == (probes[name] as? ProcessTap)?.objects) }) { probes[name] = nil }
            for app in candidates where probes[app.name] == nil && appVolumes.lastSignal(for: app.name) == nil && !uid.isEmpty {
                probes[app.name] = ProcessTap(objects: app.objects, outputUID: uid, name: app.name, monitorOnly: true)
            }
        }
        guard let s = snapshot, !s.locked, !promptOpen, !playPrompt.isOpen else { return }
        guard let app = candidates.first(where: { isSounding($0) }) else { return }
        probes[app.name] = nil
        askedApps.insert(app.name)
        engine.lock(reason: "New app playing · confirmation required")
        let token = engine.token()
        playPrompt.onAllow = { [weak self] in
            guard let self else { return }
            if self.engine.allow(token: token) { self.approvedApps.insert(app.name) }
            else { self.toast.show(title: "Sound stayed muted.", detail: "", below: self.status.button?.window?.frame) }
        }
        playPrompt.onClose = nil
        playPrompt.show(for: app, steps: 1, below: status.button?.window?.frame)
    }
    /// A volume key with no check open: Volume Up asks to turn sound on; Mute or Volume Down tucks the window into the menu bar.
    func idleVolumeKey(up: Bool) {
        // With sound allowed, volume keys are just volume keys.
        guard snapshot?.locked != false else { return }
        if up { if Date().timeIntervalSince(lastPromptEnd) > 2 { confirmFromMenuBar() } }
        else if let window = interface?.window, window.isVisible { window.collapseToMenuBar() }
    }
    let toast = MenuBarToast()
    /// Tells the user when sound they allowed has been muted again, since the window is usually tucked away by then.
    func announceMuted(_ reason: String) {
        // Asleep or locked: nobody is watching. Muting from the window itself already shows the change there.
        if reason.hasPrefix("Sleep") { return }
        if let window = interface?.window, window.isVisible, window.isKeyWindow, NSApp.isActive { return }
        let title =
            reason.hasPrefix("Output disconnected") ? "Headphones out. Muted." :
            reason.hasPrefix("New output") ? "New output. Muted." :
            reason.hasPrefix("Trust removed") ? "Trust removed. Muted." : "Muted."
        toast.onClick = { [weak self] in self?.showWindow() }
        toast.show(title: title, detail: "", below: status.button?.window?.frame)
    }
    func refreshLogin() { loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off; interface?.login.state = loginItem.state }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let a = NSAlert(); a.messageText = "Could not change Start at login"; a.informativeText = error.localizedDescription; a.runModal()
        }
        refreshLogin()
    }
    @objc func aboutProtection() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "AlwaysMute keeps sound intentional"
        a.informativeText = "Your Mac defaults to mute while AlwaysMute runs. Use the shield icon in the menu bar to allow sound with two confirmations. Pressing volume or unmute keys while locked restores mute and opens the same confirmation flow.\n\nSound has no timer and stays allowed until you mute it or a protection reset occurs. Sleep, screen lock, and manual mute restore protection. Trusted outputs can play at their saved starting volume when selected again. Headphone disconnection or fallback to built-in speakers overrides trust and restores mute. Enable Start at login from the menu for future sign-ins.\n\nProtection covers the default media and system-alert outputs. macOS delivers changes after they occur, so a brief sound may escape. HDMI, AirPlay, external hardware, or apps using a separate output may bypass software control. A warning icon means protection is unavailable. AlwaysMute does not listen to your microphone."
        a.addButton(withTitle: "Got it"); a.runModal()
    }
    @objc func quitApp() {
        engine.lock()
        let a = NSAlert(); a.messageText = "Quit sound protection?"; a.informativeText = "Your outputs will remain muted, but AlwaysMute will no longer block changes."
        a.addButton(withTitle: "Keep protecting"); a.addButton(withTitle: "Quit")
        if a.runModal() == .alertSecondButtonReturn { NSApp.terminate(nil) }
    }
    func applicationWillTerminate(_ notification: Notification) { engine.lock() }
}

if CommandLine.arguments.contains("--export-icon") {
    let folder = CommandLine.arguments.last!
    try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            Artwork.mascot(size: CGFloat(pixels), appIcon: true).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            let suffix = scale == 2 ? "@2x" : ""
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/icon_\(points)x\(points)\(suffix).png"))
        }
    }
} else if CommandLine.arguments.contains("--self-test") {
    var g = Gate()
    precondition(g.locked)
    let first = g.generation
    precondition(g.allow(token: first)); precondition(!g.locked)
    precondition(!g.allow(token: first))
    g.lock(); precondition(g.locked)
    precondition(!g.allow(token: first))
    precondition(g.allow(token: g.generation)); precondition(!g.locked)
    g.lock(); precondition(g.locked)
    let builtIn = RouteIdentity(id: 1, key: "builtin|speaker", builtIn: true, source: 1, jack: 0)
    let headphones = RouteIdentity(id: 2, key: "headphones", builtIn: false, source: nil, jack: nil)
    let wired = RouteIdentity(id: 1, key: "builtin|headphones", builtIn: true, source: 2, jack: 1)
    let other = RouteIdentity(id: 3, key: "usb", builtIn: false, source: nil, jack: nil)
    precondition(RoutePolicy.fallback(old: headphones, new: builtIn, available: [1, 2]))
    precondition(RoutePolicy.fallback(old: wired, new: builtIn, available: [1]))
    precondition(RoutePolicy.fallback(old: headphones, new: other, available: [1, 3]))
    precondition(!RoutePolicy.fallback(old: builtIn, new: headphones, available: [1, 2]))
    precondition(!RoutePolicy.fallback(old: builtIn, new: builtIn, available: [1]))
    precondition(!RoutePolicy.canTrust(key: "headphones", supported: true, fallback: true, trusted: true))
    precondition(!RoutePolicy.canTrust(key: "", supported: true, fallback: false, trusted: true))
    precondition(!RoutePolicy.canTrust(key: "headphones", supported: false, fallback: false, trusted: true))
    precondition(!RoutePolicy.canTrust(key: "headphones", supported: true, fallback: false, trusted: false))
    precondition(RoutePolicy.canTrust(key: "headphones", supported: true, fallback: false, trusted: true))
    let suite = "AlwaysMute.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = OutputPreferences(defaults: defaults)
    precondition(!store.value("new", name: "New output").trusted)
    store.save("headphones", OutputPreference(name: "Headphones", trusted: true, volume: 27))
    let reloaded = OutputPreferences(defaults: defaults)
    precondition(reloaded.value("headphones", name: "Renamed").volume == 27)
    precondition(reloaded.value("headphones", name: "Renamed").trusted)
    precondition(!reloaded.value("different-uid", name: "Headphones").trusted)
    store.save("headphones", OutputPreference(name: "Headphones", trusted: false, volume: 999))
    precondition(store.value("headphones", name: "").volume == 100)
    defaults.removePersistentDomain(forName: suite)
    print("PASS: mute gate, stale confirmations, USB/Bluetooth and wired fallback policy, trust safety, per-device persistence and volume bounds")
} else if CommandLine.arguments.contains("--diagnose") {
    for app in Audio.appsPlaying() { print("playing: \(app.name) (pid \(app.pid), \(app.objects.count) audio process\(app.objects.count == 1 ? "" : "es"))") }
    for o in Audio.defaults().map(Audio.output) { print("\(o.name): mute controls=\(o.mutes.count), volume controls=\(o.volumes.count), silent=\(o.silent), level=\(o.level)") }
} else if CommandLine.arguments.contains("--smoke-test") {
    let e = GuardEngine(); e.start()
    Thread.sleep(forTimeInterval: 0.3)
    let safe = e.queue.sync { !e.outputs.isEmpty && e.outputs.allSatisfy { $0.supported && $0.silent } }
    guard safe else { print("FAIL: output could not be muted"); exit(1) }
    // Keep hardware mute asserted while testing restoration of a raised volume.
    let tested = e.queue.sync { () -> Bool in
        guard let o = e.outputs.first, !o.mutes.isEmpty, !o.volumes.isEmpty, o.mutes.allSatisfy({ $0.read(UInt32(0)) == 1 }) else { return false }
        return o.volumes.allSatisfy { $0.write(Float32(0.03)) }
    }
    Thread.sleep(forTimeInterval: 0.5)
    let restored = e.queue.sync { e.outputs.allSatisfy { $0.silent && !$0.disturbed } }
    e.lock()
    print("\(restored ? "PASS" : "FAIL"): real output muted; volume disturbance tested=\(tested); mute + zero restored=\(restored)")
    exit(restored ? 0 : 1)
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}
