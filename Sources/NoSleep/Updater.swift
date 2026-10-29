import AppKit
import NoSleepCore
import Observation
@preconcurrency import UserNotifications

/// Finds a newer NoSleep on GitHub and puts it in place of this copy with one
/// click: download the DMG, swap the app bundle, relaunch.
///
/// No Sparkle: it would bring its own window and a row of buttons, and its
/// signatures are about trust in a Developer ID this app doesn't have. The
/// download comes over HTTPS from the repo's own releases, which is the same
/// trust the cask and install.sh already rely on.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case upToDate
        case available(version: String, dmg: URL)
        case installing(version: String)
        case failed(String)
    }

    nonisolated static let notificationCategory = "update"
    private static let announcedKey = "announcedUpdate"
    private static let checkEvery: TimeInterval = 24 * 3600

    private(set) var state: State = .upToDate
    /// Quits this copy without undoing its session; set by the app delegate.
    var quitForRelaunch: () -> Void = { NSApp.terminate(nil) }

    private let feed: URL?
    private var timer: Timer?

    /// Release builds read GitHub's latest release. Debug builds check only when
    /// `NOSLEEP_UPDATE_FEED` names a feed, so `make run` never replaces itself.
    init() {
        if let override = ProcessInfo.processInfo.environment["NOSLEEP_UPDATE_FEED"] {
            feed = URL(string: override)
        } else {
            #if DEBUG
            feed = nil
            #else
            feed = URL(string: "https://api.github.com/repos/intuito-studio/nosleep/releases/latest")
            #endif
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Checks shortly after launch, then once a day.
    func start() {
        guard feed != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.check() }
        let timer = Timer(timeInterval: Self.checkEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 3600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check() {
        guard let feed, case .upToDate = state else { return }
        Task {
            // Offline, rate-limited, no release yet: all the same, try tomorrow.
            guard let (data, _) = try? await URLSession.shared.data(from: feed),
                  let release = try? JSONDecoder().decode(Release.self, from: data),
                  let dmg = release.assets.first(where: { $0.name == "NoSleep.dmg" })?.browser_download_url
            else { return }
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard Version.isNewer(version, than: Self.currentVersion) else { return }
            state = .available(version: version, dmg: dmg)
            #if DEBUG
            // For testing the whole path without a click.
            if ProcessInfo.processInfo.environment["NOSLEEP_INSTALL_UPDATE"] != nil { return install() }
            #endif
            announce(version)
        }
    }

    /// One click from the panel or the notification. A session that is running
    /// carries over: the new copy picks up the same timer from the defaults.
    func install() {
        guard case .available(let version, let dmg) = state else { return }
        let app = Bundle.main.bundleURL
        // Somewhere this user can't write, such as an /Applications owned by
        // root: hand over the download instead.
        guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            NSWorkspace.shared.open(dmg)
            return
        }
        state = .installing(version: version)
        Task.detached {
            do {
                try await Self.replace(app, withAppIn: dmg, version: version)
                await MainActor.run { self.relaunch(app) }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    func retry() {
        state = .upToDate
        check()
    }

    // MARK: - Steps

    /// Once per version, so a skipped update doesn't nag every day. The panel
    /// keeps showing it either way.
    private func announce(_ version: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.announcedKey) != version else { return }
        defaults.set(version, forKey: Self.announcedKey)

        let center = UNUserNotificationCenter.current()
        let update = UNNotificationAction(identifier: "install", title: "Update")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.notificationCategory, actions: [update], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = "NoSleep \(version) is ready"
            content.body = "Click to update. It restarts in a second and keeps any session running."
            content.categoryIdentifier = Self.notificationCategory
            center.add(UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil))
        }
    }

    private nonisolated static func replace(_ app: URL, withAppIn dmg: URL, version: String) async throws {
        let (downloaded, _) = try await URLSession.shared.download(from: dmg)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("NoSleep-update-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let image = work.appendingPathComponent("NoSleep.dmg")
        try FileManager.default.moveItem(at: downloaded, to: image)

        try run("/usr/bin/hdiutil", "attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path)
        defer { _ = try? run("/usr/bin/hdiutil", "detach", mount.path, "-force") }

        let new = mount.appendingPathComponent("NoSleep.app")
        guard let bundle = Bundle(url: new),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version
        else { throw UpdateError("The download isn't NoSleep \(version).") }

        // Staged next to the app, on the same volume, so the swap is a rename
        // and a half-copied app is never what launches.
        let staged = app.deletingLastPathComponent().appendingPathComponent(".NoSleep-\(version).app")
        try? FileManager.default.removeItem(at: staged)
        try run("/usr/bin/ditto", new.path, staged.path)
        _ = try FileManager.default.replaceItemAt(app, withItemAt: staged)
        // Signed ad hoc, so a quarantine flag would stop it opening.
        _ = try? run("/usr/bin/xattr", "-dr", "com.apple.quarantine", app.path)
    }

    /// Opens the new copy once this one has gone.
    private func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; open \"$2\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier), app.path,
        ]
        try? process.run()
        quitForRelaunch()
    }

    @discardableResult
    private nonisolated static func run(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\((arguments[0] as NSString).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let assets: [Asset]
    }

    #if DEBUG
    /// An updater in a given state, for rendering the panel to an image.
    static func preview(_ state: State) -> Updater {
        let updater = Updater()
        updater.state = state
        return updater
    }
    #endif

    struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
