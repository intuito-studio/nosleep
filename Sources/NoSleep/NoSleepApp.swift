import AppKit
import SwiftUI

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

    // The menu bar item and its panel are AppKit (see StatusPanel); SwiftUI
    // still wants a scene.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    private var statusPanel: StatusPanel?
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["NOSLEEP_SNAPSHOT_DIR"] {
            Snapshots.render(to: URL(fileURLWithPath: directory))
            exit(0)
        }
        #endif

        Backstop.install()
        let statusPanel = StatusPanel(controller: controller)
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

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreIfOwned()
    }
}
