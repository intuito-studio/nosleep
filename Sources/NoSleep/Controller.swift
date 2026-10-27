import AppKit
import Network
import NoSleepCore
import Observation
import ServiceManagement
import UserNotifications

@MainActor @Observable
final class Controller {
    /// The timer slider's stops. The last one, nil, is no limit: dragging all the
    /// way right means "longest", and forever is the longest.
    static let durationChoices: [TimeInterval?] = [
        15 * 60, 30 * 60, 3600, 2 * 3600, 3 * 3600, 4 * 3600, 6 * 3600, 8 * 3600, nil,
    ]
    /// The battery slider's stops, nil first: dragging to the left end turns it off.
    static let batteryFloorChoices: [Int?] = [nil, 5, 10, 15, 20, 25, 30, 40, 50]
    /// How long the network has to be gone before the hotspot is tried, and how
    /// long between tries while it stays gone.
    static let hotspotAfter: TimeInterval = 30
    static let hotspotRetry: TimeInterval = 60

    /// What the system says, not what we last asked for: the terminal's `nosleep`
    /// changes the same setting, and the panel should show that too.
    private(set) var isAwake = false
    private(set) var power = PowerSource(batteryPercent: nil, onBattery: false)
    private(set) var thermal = ProcessInfo.ThermalState.nominal
    private(set) var now = Date()
    private(set) var hasPasswordFreeAccess = false
    /// False when the rule on disk predates a command NoSleep now uses.
    private(set) var ruleIsCurrent = true
    private(set) var launchesAtLogin = false
    private(set) var lastStop: (at: Date, reason: Limits.StopReason)?
    private(set) var problem: String?
    private(set) var log: [SessionEvent] = []
    private(set) var hotspotName: String?

    /// Set when this app switched sleep off, cleared when it switches it back.
    /// Only a session we own is restored on quit or by the backstop; one started
    /// from the terminal belongs to the terminal until the panel changes it.
    private(set) var ownsSession: Bool {
        didSet { defaults.set(ownsSession, forKey: StateKey.ownsSession) }
    }

    /// Kept across launches so a timer survives Open at Login after a restart.
    private(set) var until: Date? {
        didSet { defaults.set(until, forKey: StateKey.until) }
    }

    /// When the current timer was set, for the ring that shows how much is left.
    private(set) var timerStart: Date? {
        didSet { defaults.set(timerStart, forKey: "timerStart") }
    }

    /// How long a session runs, nil for no limit. Set on the slider.
    private(set) var duration: TimeInterval? {
        didSet { defaults.set(duration ?? 0, forKey: "duration") }
    }

    var batteryFloor: Int? {
        didSet { defaults.set(batteryFloor ?? 0, forKey: "batteryFloor") }
    }

    /// Low Power Mode and the mute are only ever undone by whoever did them, so
    /// a mode you switched on yourself stays on. Persisted for the backstop.
    private var lowPowerOwned: Bool {
        didSet { defaults.set(lowPowerOwned, forKey: StateKey.lowPowerOwned) }
    }

    private var mutedByUs: Bool {
        didSet { defaults.set(mutedByUs, forKey: StateKey.mutedByUs) }
    }

    private let defaults: UserDefaults
    private let live: Bool
    /// After a stop that could not run without a password, wait for a click
    /// instead of knocking on sudo every two seconds.
    private var autoStopFailed = false
    private var lidClosed = false
    private var ticker: Timer?
    private var activity: NSObjectProtocol?
    private var network: NWPathMonitor?
    private var offlineSince: Date?
    private var lastHotspotTry: Date?
    private var joiningHotspot = false

    init(defaults: UserDefaults = .standard, live: Bool = true) {
        self.defaults = defaults
        self.live = live
        defaults.register(defaults: ["batteryFloor": 20])
        ownsSession = defaults.bool(forKey: StateKey.ownsSession)
        until = defaults.object(forKey: StateKey.until) as? Date
        timerStart = defaults.object(forKey: "timerStart") as? Date
        lowPowerOwned = defaults.bool(forKey: StateKey.lowPowerOwned)
        mutedByUs = defaults.bool(forKey: StateKey.mutedByUs)
        let duration = defaults.double(forKey: "duration")
        self.duration = duration > 0 ? duration : nil
        let floor = defaults.integer(forKey: "batteryFloor")
        batteryFloor = floor > 0 ? floor : nil
        guard live else { return }

        log = SessionLog.load(defaults)
        hotspotName = Hotspot.name
        ruleIsCurrent = SleepSwitch.hasCurrentRule || !SleepSwitch.hasPasswordFreeAccess
        // The lid's state at launch is where we start from, not a change to act on.
        lidClosed = SleepSwitch.isLidClosedAndWouldSleep
        watchNetwork()

        tick()
        // Every 2 s keeps the panel in step with a `nosleep` typed in the
        // terminal; the reads are registry lookups, not processes.
        let ticker = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker.tolerance = 1
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    /// 1 when the timer has just been set, 0 when it runs out; nil without a timer.
    var timerFractionLeft: Double? {
        guard isAwake, let until, let timerStart else { return nil }
        let total = until.timeIntervalSince(timerStart)
        guard total > 0 else { return nil }
        return min(1, max(0, until.timeIntervalSince(now) / total))
    }

    // MARK: - Actions

    func setAwake(_ awake: Bool) {
        if awake { start() } else { stop(because: nil) }
    }

    /// Moving the slider during a session restarts its clock from now. Doing it
    /// to a session the terminal started makes the session ours, timer and all.
    func setDuration(_ duration: TimeInterval?) {
        self.duration = duration
        guard isAwake else { return }
        setTimer(duration)
        ownsSession = true
    }

    /// Rewrites the sudoers rule after an update added a command to it.
    func updateAccess() {
        problem = nil
        do {
            try SleepSwitch.installAccess(applying: nil)
        } catch SleepSwitch.Failure.cancelled {
        } catch {
            problem = error.localizedDescription
        }
        ruleIsCurrent = SleepSwitch.hasCurrentRule
        tick()
    }

    func saveHotspot(name: String, password: String) {
        Hotspot.save(name: name, password: password)
        hotspotName = Hotspot.name
    }

    func removeHotspot() {
        Hotspot.remove()
        hotspotName = nil
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problem = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func quit() {
        NSApp.terminate(nil)
    }

    /// Called on the way out. Never prompts: a password dialog during logout helps nobody.
    func restoreIfOwned() {
        undoLidActions()
        if lowPowerOwned, (try? SleepSwitch.setLowPower(false)) != nil { lowPowerOwned = false }
        guard ownsSession, SleepSwitch.isSleepDisabled else { return }
        if (try? SleepSwitch.setSleepDisabled(false)) != nil {
            ownsSession = false
            setTimer(nil)
        }
    }

    // MARK: - Sessions

    private func start() {
        problem = nil
        autoStopFailed = false
        if case .battery(let percent) = Limits(batteryFloor: batteryFloor).reasonToStop(now: Date(), power: .current) {
            problem = "Battery is at \(percent)%, at or below the \(batteryFloor ?? 0)% stop. Plug in, or lower the stop."
            return
        }
        guard apply(disabled: true, interactive: true) else { return }
        setTimer(duration)
        ownsSession = true
        lastStop = nil
        record("Kept awake", duration.map { "for \(Format.durationName($0))" } ?? "no time limit")
        // Asked here, the first time it could matter, rather than at launch.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        tick()
    }

    private func stop(because reason: Limits.StopReason?) {
        problem = nil
        autoStopFailed = false
        // The battery, the heat and the timer act on their own, often with the lid
        // shut and nobody there to type a password; only a click may bring up the dialog.
        guard apply(disabled: false, interactive: reason == nil) else { return }
        ownsSession = false
        setTimer(nil)
        undoLidActions()
        if let reason {
            lastStop = (Date(), reason)
            let why = Self.describe(reason)
            record("Back to normal sleep", why)
            notify("Back to normal sleep", why)
            if SleepSwitch.isLidClosedAndWouldSleep { SleepSwitch.sleepNow() }
        } else {
            record("Back to normal sleep", "switched off")
        }
        tick()
    }

    static func describe(_ reason: Limits.StopReason) -> String {
        switch reason {
        case .timer: "timer ran out"
        case .battery(let percent): "battery at \(percent)%"
        case .heat: "Mac got critically hot"
        }
    }

    private func setTimer(_ duration: TimeInterval?) {
        let now = Date()
        until = duration.map { now.addingTimeInterval($0) }
        timerStart = duration == nil ? nil : now
    }

    private func apply(disabled: Bool, interactive: Bool) -> Bool {
        do {
            try SleepSwitch.setSleepDisabled(disabled)
            return true
        } catch SleepSwitch.Failure.needsAccess where interactive {
            do {
                try SleepSwitch.installAccess(applying: disabled)
                ruleIsCurrent = SleepSwitch.hasCurrentRule
                return true
            } catch SleepSwitch.Failure.cancelled {
                return false
            } catch {
                problem = error.localizedDescription
                return false
            }
        } catch {
            if interactive {
                problem = error.localizedDescription
            } else {
                autoStopFailed = true
                problem = "Couldn't switch sleep back on by itself. Click the tile once to set that up."
            }
            return false
        }
    }

    // MARK: - Every tick

    private func tick() {
        now = Date()
        power = .current
        thermal = ProcessInfo.processInfo.thermalState
        isAwake = SleepSwitch.isSleepDisabled
        hasPasswordFreeAccess = SleepSwitch.hasPasswordFreeAccess
        launchesAtLogin = SMAppService.mainApp.status == .enabled

        if !isAwake, ownsSession || until != nil {
            // Switched back from somewhere else: `nosleep off`, or a restart.
            ownsSession = false
            setTimer(nil)
            undoLidActions()
        }
        // The stops guard any awake session, including one the terminal
        // started; there is only a timer on ours.
        if isAwake, !autoStopFailed,
           let reason = Limits(until: until, batteryFloor: batteryFloor).reasonToStop(now: now, power: power, thermal: thermal) {
            stop(because: reason)
            return
        }
        followLid()
        followLowPower()
        followNetwork()
        holdOffAppNap(isAwake)
    }

    /// What closing the lid does during a session, and what opening it undoes.
    private func followLid() {
        let closed = SleepSwitch.isLidClosedAndWouldSleep
        guard closed != lidClosed else { return }
        lidClosed = closed
        guard isAwake || mutedByUs else { return }

        if closed {
            var done = ["display off"]
            SleepSwitch.displaySleepNow()
            if Audio.isMuted == false {
                Audio.setMuted(true)
                mutedByUs = true
                done.append("audio muted")
            }
            followLowPower(quiet: true)
            if lowPowerOwned { done.append("low power on") }
            record("Lid closed", done.joined(separator: " · "))
        } else {
            var done: [String] = []
            if mutedByUs { done.append("audio unmuted") }
            undoLidActions()
            let hadLowPower = lowPowerOwned
            followLowPower(quiet: true)
            if hadLowPower, !lowPowerOwned { done.append("low power off") }
            record("Lid opened", done.isEmpty ? "still running" : done.joined(separator: " · "))
        }
    }

    private func undoLidActions() {
        guard mutedByUs else { return }
        Audio.setMuted(false)
        mutedByUs = false
    }

    /// `quiet` when the lid's own log line already says what changed.
    private func followLowPower(quiet: Bool = false) {
        guard ruleIsCurrent, hasPasswordFreeAccess else { return }
        let reason = isAwake ? LowPowerRule.reason(lidClosed: lidClosed, power: power, thermal: thermal) : nil
        if let reason, !lowPowerOwned, !SleepSwitch.isLowPowerOn {
            guard (try? SleepSwitch.setLowPower(true)) != nil else { return }
            lowPowerOwned = true
            switch reason {
            case .lidClosed: if !quiet { record("Low Power Mode on", "lid closed") }
            case .battery(let percent): record("Low Power Mode on", "battery at \(percent)%")
            case .heat: record("Low Power Mode on", "Mac is getting hot")
            }
        } else if reason == nil, lowPowerOwned {
            guard (try? SleepSwitch.setLowPower(false)) != nil else { return }
            lowPowerOwned = false
            if !quiet { record("Low Power Mode off") }
        }
    }

    // MARK: - Hotspot

    private func watchNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if online {
                    self.offlineSince = nil
                    self.lastHotspotTry = nil
                } else if self.offlineSince == nil {
                    self.offlineSince = Date()
                }
            }
        }
        monitor.start(queue: .main)
        network = monitor
    }

    private func followNetwork() {
        guard isAwake, let name = hotspotName, !joiningHotspot,
              let offlineSince, now.timeIntervalSince(offlineSince) >= Self.hotspotAfter
        else { return }
        if let lastHotspotTry, now.timeIntervalSince(lastHotspotTry) < Self.hotspotRetry { return }
        lastHotspotTry = now
        joiningHotspot = true
        DispatchQueue.global(qos: .utility).async {
            let result = Hotspot.join(name)
            Task { @MainActor in
                self.joiningHotspot = false
                switch result {
                case .success: self.record("Joined hotspot", "\(name), Wi-Fi had dropped")
                case .failure(let error): self.record("Couldn't join hotspot", "\(name): \(error.message)")
                }
            }
        }
    }

    // MARK: - Telling the user

    private func record(_ title: String, _ detail: String = "") {
        guard live else { return }
        log = SessionLog.append(SessionEvent(at: Date(), title: title, detail: detail), defaults)
    }

    private func notify(_ title: String, _ body: String) {
        guard live else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body.prefix(1).uppercased() + body.dropFirst()
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// With the lid shut and the display off, App Nap lets the timer drift by
    /// minutes. Held only while there is something to watch.
    private func holdOffAppNap(_ hold: Bool) {
        if hold, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Watching the NoSleep timer, battery and lid"
            )
        } else if !hold, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }
}

#if DEBUG
extension Controller {
    /// For Scripts/verify.sh: a session started without a click, running for
    /// `seconds`, which can be shorter than any slider choice. The slider's
    /// saved duration is left alone.
    func startForVerify(seconds: TimeInterval) {
        start()
        guard isAwake else { return }
        setTimer(seconds)
    }

    /// A controller that never reads or changes the system, for rendering the panel to an image.
    static func preview(
        awake: Bool,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval = 0,
        power: PowerSource = PowerSource(batteryPercent: 64, onBattery: true),
        batteryFloor: Int? = 20,
        hasPasswordFreeAccess: Bool = true,
        ruleIsCurrent: Bool = true,
        lastStop: (Date, Limits.StopReason)? = nil,
        problem: String? = nil,
        log: [SessionEvent] = [],
        hotspotName: String? = nil
    ) -> Controller {
        let controller = Controller(defaults: UserDefaults(suiteName: "nosleep.preview")!, live: false)
        let now = Date()
        controller.now = now
        controller.isAwake = awake
        controller.ownsSession = awake
        controller.duration = duration
        if awake, let duration {
            controller.timerStart = now.addingTimeInterval(-elapsed)
            controller.until = now.addingTimeInterval(duration - elapsed)
        } else {
            controller.timerStart = nil
            controller.until = nil
        }
        controller.power = power
        controller.batteryFloor = batteryFloor
        controller.hasPasswordFreeAccess = hasPasswordFreeAccess
        controller.ruleIsCurrent = ruleIsCurrent
        controller.lastStop = lastStop.map { (at: $0.0, reason: $0.1) }
        controller.problem = problem
        controller.log = log
        controller.hotspotName = hotspotName
        return controller
    }

    func withLog(_ events: [SessionEvent]) -> Controller {
        log = events
        return self
    }
}
#endif
