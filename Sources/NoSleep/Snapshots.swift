#if DEBUG
import AppKit
import NoSleepCore
import SwiftUI

/// `NOSLEEP_SNAPSHOT_DIR=/tmp/nosleep .build/NoSleep.app/Contents/MacOS/NoSleep`
/// renders the panel in each state, light and dark, so it can be judged by eye
/// without clicking through the menu bar. A window flickers in the bottom-left
/// corner while it runs: glass only renders on screen.
@MainActor
enum Snapshots {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let states: [(String, Controller)] = [
            ("normal", .preview(awake: false)),
            ("awake", .preview(awake: true)),
            ("timer", .preview(awake: true, duration: 2 * 3600, elapsed: 1080)),
            ("stopped", .preview(awake: false, lastStop: (Date(), .battery(20)))),
            ("first-run", .preview(awake: false, hasPasswordFreeAccess: false)),
            ("problem", .preview(
                awake: false,
                power: PowerSource(batteryPercent: 18, onBattery: true),
                problem: "Battery is at 18%, at or below the 20% stop. Plug in, or lower the stop."
            )),
            ("charging", .preview(awake: true, power: PowerSource(batteryPercent: 8, onBattery: false), batteryFloor: nil)),
            ("desktop", .preview(awake: true, power: PowerSource(batteryPercent: nil, onBattery: false))),
            ("night", .preview(
                awake: true, duration: 8 * 3600, elapsed: 4 * 3600
            ).withLog(night)),
            ("update", .preview(awake: false, ruleIsCurrent: false)),
        ]
        let update = Updater.preview(.available(version: "1.1.0", dmg: URL(string: "https://example.com")!))
        let window = SnapshotWindow()
        for (name, controller) in states {
            for dark in [false, true] {
                write(MenuPanel(dark: dark) { PanelView(controller: controller, updater: name == "update" ? update : nil) },
                      dark: dark, in: window, to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        let settings = Controller.preview(awake: true).withLog(night)
        for dark in [false, true] {
            write(SettingsView(controller: settings), dark: dark, in: window,
                  to: directory.appendingPathComponent("settings-\(dark ? "dark" : "light").png"))
        }
        window.orderOut(nil)
    }

    private static let night: [SessionEvent] = {
        let start = Calendar.current.date(bySettingHour: 23, minute: 14, second: 0, of: Date())!
        return [
            SessionEvent(at: start, title: "Kept awake", detail: "for 8 hours"),
            SessionEvent(at: start.addingTimeInterval(124), title: "Lid closed", detail: "display off · audio muted · low power on"),
            SessionEvent(at: start.addingTimeInterval(7.8 * 3600), title: "Lid opened", detail: "audio unmuted · low power off"),
        ]
    }()

    /// The panel over a desktop. It draws its own outer sheet of glass, as it
    /// does in the menu bar.
    private struct MenuPanel<Content: View>: View {
        let dark: Bool
        @ViewBuilder let content: Content

        var body: some View {
            content
                .padding(28)
                .background(dark ? Color(red: 0.13, green: 0.16, blue: 0.24) : Color(red: 0.62, green: 0.72, blue: 0.84))
        }
    }

    /// Reports itself as key, so switches and sliders draw in their active
    /// colours as they do in the open panel, without stealing focus to get there.
    private final class SnapshotWindow: NSWindow {
        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                       styleMask: .borderless, backing: .buffered, defer: false)
            hasShadow = false
            isReleasedWhenClosed = false
        }

        override var isKeyWindow: Bool { true }
    }

    private static func write(_ view: some View, dark: Bool, in window: NSWindow, to url: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.environment(\.controlActiveState, .key))
        host.appearance = appearance
        window.appearance = appearance
        window.contentView = host
        let size = host.fittingSize
        window.setFrame(NSRect(origin: NSPoint(x: 0, y: 0), size: size), display: true)
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        guard let image = captureOwnWindow(window) else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Glass is composited by the window server, so drawing the view into a
    /// bitmap leaves it out. CGWindowListCreateImage is gone from the SDK but
    /// still in the OS, and needs no Screen Recording permission for a process's
    /// own windows.
    static func captureOwnWindow(_ window: NSWindow) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3
        let boundsIgnoreFramingAndBestResolution: UInt32 = 1 | 1 << 3
        return createImage(.null, includingWindow, UInt32(window.windowNumber), boundsIgnoreFramingAndBestResolution)?
            .takeRetainedValue()
    }
}
#endif
