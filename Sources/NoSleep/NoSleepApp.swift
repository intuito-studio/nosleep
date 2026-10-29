import AppKit
import SwiftUI
@preconcurrency import UserNotifications

/// One binary, two jobs: the menu bar app, or, run by launchd with
/// `--backstop`, the check that cleans up after an app that is gone.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains(Backstop.argument) {
            Backstop.run()
            return
        }
        NoSleepApp.main()
    }
}

struct NoSleepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item, its panel and the Settings window are AppKit (see
    // StatusPanel); SwiftUI still wants a scene. One that is never inserted,
    // because a `Settings` scene here opens as an empty window at launch.
    var body: some Scene {
        MenuBarExtra("NoSleep", isInserted: .constant(false)) { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let controller = Controller()
    let updater = Updater()
    private var statusPanel: StatusPanel?
    private var terminationSignal: DispatchSourceSignal?
    /// Quitting to make way for a newer copy, which takes the session over.
    private var relaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["NOSLEEP_SNAPSHOT_DIR"] {
            Snapshots.render(to: URL(fileURLWithPath: directory))
            exit(0)
        }
        #endif

        Backstop.install()
        UNUserNotificationCenter.current().delegate = self
        updater.quitForRelaunch = { [weak self] in
            self?.relaunching = true
            NSApp.terminate(nil)
        }
        updater.start()
        let statusPanel = StatusPanel(controller: controller, updater: updater)
        self.statusPanel = statusPanel
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["NOSLEEP_PANEL_PROBE"] {
            statusPanel.probe(to: URL(fileURLWithPath: directory))
        }
        if let seconds = ProcessInfo.processInfo.environment["NOSLEEP_START"].flatMap(TimeInterval.init) {
            controller.startForVerify(seconds: seconds)
        }
        #endif

        // `kill` and `pkill` send SIGTERM, which skips applicationWillTerminate
        // and would leave the Mac never sleeping. Route it through a normal quit.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    /// Leaves sleep, Low Power Mode and the mute as they are when an update
    /// relaunches the app: the new copy reads the same defaults and carries on.
    func applicationWillTerminate(_ notification: Notification) {
        guard !relaunching else { return }
        controller.restoreIfOwned()
    }

    // MARK: - Notifications

    /// Clicking the update notification, or its Update button, installs it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == Updater.notificationCategory,
           response.actionIdentifier != UNNotificationDismissActionIdentifier {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.updater.install() } }
        }
        completionHandler()
    }

    /// Shown even while the panel is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
