import AppKit
import NoSleepCore

/// The safety net for a NoSleep that is no longer running.
///
/// `SleepDisabled` outlives the process that set it: if the app crashes or is
/// force-quit mid-session, the Mac would never sleep again. A launchd agent
/// runs this same binary with `--backstop` every minute. When it finds a
/// session NoSleep owned and no NoSleep running, it undoes what the session
/// changed. It never touches a session the terminal started.
enum Backstop {
    static let label = "dev.intuito.nosleep.backstop"
    static let argument = "--backstop"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Called at every launch: writes the agent if it is missing or points at
    /// another copy of the app, and loads it.
    static func install() {
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, argument],
            "StartInterval": 60,
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        let domain = "gui/\(getuid())"
        let current = try? Data(contentsOf: plistURL)
        if current == data, launchctl(["print", "\(domain)/\(label)"]) == 0 { return }

        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: plistURL, options: .atomic)
        launchctl(["bootout", "\(domain)/\(label)"])
        launchctl(["bootstrap", domain, plistURL.path])
    }

    static func run() {
        let defaults = UserDefaults.standard
        let me = ProcessInfo.processInfo.processIdentifier
        let id = Bundle.main.bundleIdentifier ?? "dev.intuito.nosleep"
        let appIsRunning = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != me }
        guard !appIsRunning else { return }

        var undone: [String] = []
        if defaults.bool(forKey: StateKey.ownsSession) {
            let wasAwake = SleepSwitch.isSleepDisabled
            if !wasAwake || (try? SleepSwitch.setSleepDisabled(false)) != nil {
                if wasAwake { undone.append("sleep back on") }
                defaults.set(false, forKey: StateKey.ownsSession)
                defaults.removeObject(forKey: StateKey.until)
            }
        }
        if defaults.bool(forKey: StateKey.lowPowerOwned), (try? SleepSwitch.setLowPower(false)) != nil {
            defaults.set(false, forKey: StateKey.lowPowerOwned)
            undone.append("low power off")
        }
        if defaults.bool(forKey: StateKey.mutedByUs) {
            Audio.setMuted(false)
            defaults.set(false, forKey: StateKey.mutedByUs)
            undone.append("audio unmuted")
        }
        guard !undone.isEmpty else { return }
        SessionLog.append(SessionEvent(at: Date(), title: "Recovered after NoSleep stopped", detail: undone.joined(separator: " · ")))
        if SleepSwitch.isLidClosedAndWouldSleep { SleepSwitch.sleepNow() }
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
