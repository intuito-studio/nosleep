import AppKit
import Observation
import SwiftUI

/// The menu bar item and the panel it opens, built by hand rather than with
/// MenuBarExtra.
///
/// MenuBarExtra's window has a backdrop the window server draws, with a corner
/// of about 7 pt that the app cannot change. Around 18 pt glass tiles that
/// breaks the rule for nested corners (outer radius = inner radius + the gap
/// between them). This panel is clear, so the outer sheet `PanelView` draws is
/// the only shape there is.
@MainActor
final class StatusPanel: NSObject {
    private let controller: Controller
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = Panel()
    private let settings: SettingsWindow
    private var outsideClicks: Any?
    /// Where the panel's top edge sits, kept while its content grows or shrinks.
    private var top: CGFloat = 0

    init(controller: Controller, updater: Updater, lidEffect: LidEffect) {
        self.controller = controller
        settings = SettingsWindow(controller: controller, lidEffect: lidEffect, updater: updater)
        super.init()
        panel.show(PanelView(controller: controller, updater: updater) { [weak self] in
            self?.close()
            self?.settings.show()
        })
        panel.onCancel = { [weak self] in self?.close() }
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResized), name: NSWindow.didResizeNotification, object: panel
        )
        followController()
    }

    @objc func toggle() {
        panel.isVisible ? close() : open()
    }

    func open() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        top = anchor.minY - 4
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                // The menu bar can report a click on our own item as outside;
                // closing here would let the item's action open the panel again.
                guard let self, !self.pointerIsOnItem else { return }
                self.close()
            }
        }
    }

    private var pointerIsOnItem: Bool {
        guard let button = item.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }

    func close() {
        panel.orderOut(nil)
        item.button?.highlight(false)
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }

    /// A problem line or the access row changes the panel's height; keep its
    /// top under the menu bar rather than its bottom where it was.
    @objc private func panelResized() {
        guard panel.isVisible, abs(panel.frame.maxY - top) > 0.5 else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
        panel.invalidateShadow()
    }

    // MARK: - The item itself

    /// Redraws the item whenever something it shows changes.
    private func followController() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.followController() }
        }
    }

    private func render() {
        guard let button = item.button else { return }
        let awake = controller.isAwake
        button.image = (awake ? CatGlyph.awake : .asleep).menuBarImage()
        if awake, let until = controller.until {
            let left = until.timeIntervalSince(controller.now)
            button.title = " " + Format.compact(left)
            button.setAccessibilityLabel("NoSleep: awake, \(Format.remaining(left)) left")
        } else {
            button.title = ""
            button.setAccessibilityLabel(awake ? "NoSleep: awake" : "NoSleep: normal sleep")
        }
    }

    /// Clear and borderless, its shape and shadow set by `SheetController`.
    private final class Panel: NSPanel {
        init() {
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered, defer: true)
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            level = .popUpMenu
            collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            isReleasedWhenClosed = false
            hidesOnDeactivate = false
        }

        func show(_ view: PanelView) {
            // A controller, so the window follows the panel's size as it changes.
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            contentViewController = SheetController(host, cornerRadius: PanelView.sheetRadius)
        }

        // Key, so Esc closes it and ⌘, and ⌘Q reach its buttons.
        override var canBecomeKey: Bool { true }

        /// Esc goes through the same close as a click, so the item's highlight
        /// and the outside-click monitor go with the panel.
        var onCancel: (() -> Void)?

        override func cancelOperation(_ sender: Any?) {
            if let onCancel { onCancel() } else { orderOut(nil) }
        }
    }

    /// Gives the window server the sheet's rounded outline. Traced from what a
    /// clear window last drew, the shadow kept a stale square outline, seen
    /// as a grey frame round the corners. AppKit's documented way to shape a
    /// borderless window and its shadow is an `NSVisualEffectView` content
    /// view with a `maskImage`: "If the visual effect view is the content view
    /// of a window, the mask is applied in an appropriate way to the window's
    /// shadow." The SwiftUI glass sheet draws over it, inside the same outline.
    private final class SheetController: NSViewController {
        private let host: NSViewController
        private let cornerRadius: CGFloat

        init(_ host: NSViewController, cornerRadius: CGFloat) {
            self.host = host
            self.cornerRadius = cornerRadius
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func loadView() {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.mask(cornerRadius: cornerRadius)
            addChild(host)
            host.view.frame = effect.bounds
            host.view.autoresizingMask = [.width, .height]
            effect.addSubview(host.view)
            view = effect
            preferredContentSize = host.preferredContentSize
        }

        // The window follows this controller's size, so pass the panel's on.
        override func preferredContentSizeDidChange(for viewController: NSViewController) {
            super.preferredContentSizeDidChange(for: viewController)
            preferredContentSize = viewController.preferredContentSize
        }

        /// The sheet's own continuous-corner rectangle, stretched between its
        /// corners. A continuous corner runs about 1.53 radii along each edge,
        /// so the caps are cut wider than the radius.
        private static func mask(cornerRadius radius: CGFloat) -> NSImage {
            let cap = (radius * 1.6).rounded(.up)
            let edge = cap * 2 + 1
            let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.addPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath)
                context.setFillColor(.black)
                context.fillPath()
                return true
            }
            image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
            image.resizingMode = .stretch
            return image
        }
    }

    #if DEBUG
    /// `NOSLEEP_PANEL_PROBE=<dir>` opens the real panel at launch, then the
    /// Settings window, and writes a capture of each there, glass and all.
    func probe(to directory: URL) {
        // The status item has no window of its own until the menu bar lays it out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.open() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [panel] in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let image = Snapshots.captureOwnWindow(panel) {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("panel.png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.close(); self.settings.show() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard let window = NSApp.windows.first(where: { $0.title == "NoSleep Settings" }),
                  let image = Snapshots.captureOwnWindow(window) else { return }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("settings.png"))
        }
    }
    #endif
}
