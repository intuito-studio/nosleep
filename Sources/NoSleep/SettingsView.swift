import AppKit
import NoSleepCore
import SwiftUI

/// What is read back now and then: the full activity log. Kept out of the
/// panel, which is for switching on and off.
struct SettingsView: View {
    let controller: Controller
    let lidEffect: LidEffect

    var body: some View {
        Form {
            if lidEffect.isAvailable {
                LidSection(effect: lidEffect)
            }
            ActivitySection(events: controller.log)
        }
        .formStyle(.grouped)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    static let size = NSSize(width: 460, height: 560)
}

/// The lid effect's one choice. The cat needs nothing; the fold needs
/// Screen Recording, and this click is the only place that asks for it.
private struct LidSection: View {
    let effect: LidEffect

    var body: some View {
        Section {
            Toggle("Fold the screen as the lid closes", isOn: Binding(
                get: { effect.foldsScreen },
                set: { effect.setFoldsScreen($0) }
            ))
            if effect.foldsScreen, !effect.hasScreenRecording {
                HStack {
                    Text("Needs Screen Recording. Until then, only the cat shows.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings…") { effect.openScreenRecordingSettings() }
                }
            }
        } header: {
            Text("Lid")
        } footer: {
            Text("While NoSleep is on, the cat comes up as the lid closes. Folding holds the desktop still while the lid turns around it, and needs Screen Recording.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            effect.refreshPermission()
        }
    }
}

/// Every event kept, newest first, like a log read back in the morning.
private struct ActivitySection: View {
    let events: [SessionEvent]

    var body: some View {
        Section("Activity") {
            if events.isEmpty {
                Text("Nothing yet. Sessions, lid closes and stops show up here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(events.reversed()) { event in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.at.formatted(date: .omitted, time: .shortened))
                        if let day = Self.day(event.at) { Text(day) }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 72, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: 12.5, weight: .medium))
                        if !event.detail.isEmpty {
                            Text(event.detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Nothing for today. The log keeps 30 events, which can reach back days.
    private static func day(_ date: Date) -> String? {
        if Calendar.current.isDateInToday(date) { return nil }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// An ordinary titled window. Shown in front even though the app has no Dock
/// icon, which otherwise leaves new windows behind the frontmost app.
@MainActor
final class SettingsWindow {
    private let controller: Controller
    private let lidEffect: LidEffect
    private var window: NSWindow?

    init(controller: Controller, lidEffect: LidEffect) {
        self.controller = controller
        self.lidEffect = lidEffect
    }

    func show() {
        let window = self.window ?? make()
        self.window = window
        // In front first: activating an app with no window on screen makes
        // SwiftUI open its own, empty Settings scene.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func make() -> NSWindow {
        // A fixed size: the form scrolls inside it, and letting the window
        // follow the form's own size sends layout round in a loop.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: SettingsView(controller: controller, lidEffect: lidEffect))
        window.title = "NoSleep Settings"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
