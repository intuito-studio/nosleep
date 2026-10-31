import AppKit
import Metal
import ScreenCaptureKit
import NoSleepCore
import Observation
import QuartzCore

/// While NoSleep is on, follows the hinge as the lid comes down: the cat
/// comes up from below the screen, its eyes on the pointer, and, with the fold
/// switched on and Screen Recording granted, the desktop folds away under it
/// as Mac Duo does it. Above 100°, or with NoSleep off, there is nothing: no window,
/// no capture, the sensor read twice a second at most.
@MainActor @Observable
final class LidEffect {
    /// False on a Mac without a lid angle sensor; the feature is then absent.
    let isAvailable: Bool

    /// The Settings toggle. Off by default: it needs Screen Recording.
    var foldsScreen: Bool {
        didSet { defaults.set(foldsScreen, forKey: Self.foldKey) }
    }

    private(set) var hasScreenRecording = CGPreflightScreenCaptureAccess()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var readAngle: () -> Double?
    @ObservationIgnored private var awake = false
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var pollInterval: TimeInterval = 0
    @ObservationIgnored private var target = 120.0
    @ObservationIgnored private var spring = DampedSpring(value: 120, frequency: 14)
    /// Where the pointer was at the last reading, global coordinates; nil
    /// while the eyes rest ahead.
    @ObservationIgnored private var pointer: CGPoint?
    /// Slower than the hinge's: an eye glides after the pointer, as on the site.
    @ObservationIgnored private var lookX = DampedSpring(value: 0, frequency: 8)
    @ObservationIgnored private var lookY = DampedSpring(value: 0, frequency: 8)
    @ObservationIgnored private var overlay: LidOverlay?
    @ObservationIgnored private var renderer: FoldRenderer?
    @ObservationIgnored private var flood: FloodRenderer?
    @ObservationIgnored private var stream: ScreenStream?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastFrame: CFTimeInterval = 0
    @ObservationIgnored private var debugPicture: CGImage?
    /// Decided as the overlay comes up: the permission check is a round trip to TCC.
    @ObservationIgnored private var folds = false

    private static let foldKey = "foldsScreen"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        foldsScreen = defaults.bool(forKey: Self.foldKey)
        let sensor = LidAngleSensor.open()
        readAngle = { sensor?.read() }
        isAvailable = sensor != nil || Self.debugAngle != nil
        #if DEBUG
        if let debugAngle = Self.debugAngle { readAngle = debugAngle }
        if let path = ProcessInfo.processInfo.environment["NOSLEEP_FOLD_PICTURE"],
           let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            debugPicture = image
        }
        #endif
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    /// NoSleep switched on or off.
    func setAwake(_ awake: Bool) {
        guard isAvailable, awake != self.awake else { return }
        self.awake = awake
        if awake {
            schedulePoll(every: 0.5)
            read()
        } else {
            stop()
        }
    }

    /// On quit, and whenever NoSleep turns off: window out, capture stopped.
    func stop() {
        awake = false
        poll?.invalidate()
        poll = nil
        pollInterval = 0
        dismiss()
    }

    /// The toggle's click is the only place that may ask for Screen Recording:
    /// the fold itself runs unattended, often with the lid shut.
    func setFoldsScreen(_ on: Bool) {
        foldsScreen = on
        guard on else { return }
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        if !hasScreenRecording {
            // Shows the system prompt the first time; after that it only answers.
            hasScreenRecording = CGRequestScreenCaptureAccess()
        }
        // macOS also asks, separately, before an app reads the screen without
        // its window picker. Ask now, on the click, so that question never
        // lands halfway through a lid close.
        if hasScreenRecording {
            Task { _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        }
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!)
    }

    func refreshPermission() {
        hasScreenRecording = CGPreflightScreenCaptureAccess()
    }

    // MARK: - The sensor

    private func schedulePoll(every interval: TimeInterval) {
        guard interval != pollInterval else { return }
        pollInterval = interval
        poll?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    /// The sensor refreshes about ten times a second. Read at that rate only
    /// while the lid is low enough to matter; in normal use and shut, twice a second.
    private func read() {
        guard awake, let angle = readAngle() else { return }
        target = angle
        schedulePoll(every: angle > LidCurves.darkAt && angle < 105 ? 0.1 : 0.5)

        if overlay == nil {
            guard LidCurves.isShown(at: angle), let screen = NSScreen.builtIn else { return }
            spring.snap(to: angle)
            present(on: screen)
        }
        pointer = tracksPointer(at: angle) ? pointerLocation() : nil
        displayLink?.isPaused = false
    }

    /// The eyes follow the pointer while the cat is up and the screen lit,
    /// from the same readings as the hinge: the pointer's position is public,
    /// so no permission is involved, and a still pointer costs one call a
    /// tenth of a second, no drawing. With Reduce Motion on they stay ahead.
    private func tracksPointer(at angle: Double) -> Bool {
        LidCurves.catRise(at: angle) > 0 && angle > LidCurves.darkAt
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func pointerLocation() -> CGPoint {
        #if DEBUG
        if let debugPointer = Self.debugPointer, let frame = overlay?.window.frame {
            return CGPoint(x: frame.minX + debugPointer.x, y: frame.maxY - debugPointer.y)
        }
        #endif
        return NSEvent.mouseLocation
    }

    // MARK: - The overlay

    private func present(on screen: NSScreen) {
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        folds = debugPicture != nil || (foldsScreen && hasScreenRecording)
        if renderer == nil { renderer = FoldRenderer() }
        if flood == nil, let device = renderer?.device ?? MTLCreateSystemDefaultDevice() { flood = FloodRenderer(device: device) }
        let overlay = LidOverlay(screen: screen, renderer: renderer, flood: flood)
        overlay.show()
        self.overlay = overlay
        lastFrame = 0
        let link = overlay.window.contentView!.displayLink(target: DisplayLinkTarget { [weak self] in self?.frame() },
                                                          selector: #selector(DisplayLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
        frame()
    }

    private func dismiss() {
        pointer = nil
        lookX.snap(to: 0)
        lookY.snap(to: 0)
        displayLink?.invalidate()
        displayLink = nil
        stream?.stop()
        overlay?.close()
        overlay = nil
    }

    private func screensChanged() {
        guard let overlay else { return }
        if let screen = NSScreen.builtIn {
            overlay.follow(screen)
        } else {
            // Shut with an external display: the built-in one is gone.
            dismiss()
        }
    }

    /// One display frame: the spring moves towards the latest reading, and the
    /// overlay draws the angle it has reached.
    private func frame() {
        guard let overlay else { return }
        let now = CACurrentMediaTime()
        let dt = lastFrame == 0 ? 1.0 / 60 : now - lastFrame
        lastFrame = now
        spring.advance(toward: target, dt: dt)
        let angle = spring.value
        let gaze = pointer.map { overlay.look(at: $0, angle: angle) } ?? .ahead
        lookX.advance(toward: gaze.x, dt: dt)
        lookY.advance(toward: gaze.y, dt: dt)

        if !LidCurves.isShown(at: angle), !LidCurves.isShown(at: target) {
            dismiss()
            return
        }
        let folding = folds
        if folding { keepPicture(for: angle, in: overlay) } else { stream?.stop() }
        overlay.draw(angle: angle, folding: folding, look: CatLook(x: lookX.value, y: lookY.value))
        // Still, nothing to draw until the next reading, unless a frame to
        // freeze is on its way. Shut, the screen is black and wants nothing.
        let awaitingPicture = folding && LidCurves.isFolding(at: angle) && angle > LidCurves.darkAt && !overlay.hasPicture
        let eyesStill = lookX.isSettled(at: gaze.x, tolerance: 0.005) && lookY.isSettled(at: gaze.y, tolerance: 0.005)
        if spring.isSettled(at: target, tolerance: 0.02), eyesStill, !awaitingPicture {
            displayLink?.isPaused = true
        }
    }

    /// The picture is taken as the fold starts and held still while it runs.
    /// Above the start angle the stream keeps the newest frame ready; once
    /// it is frozen the stream stops, and with the screen fully dark the
    /// picture goes too, so a lid opened hours later folds back from a fresh one.
    private func keepPicture(for angle: Double, in overlay: LidOverlay) {
        guard let renderer else { return }
        let wanted = LidCurves.isShown(at: angle) && angle > LidCurves.darkAt
        if !LidCurves.isFolding(at: angle) || !wanted {
            renderer.release()
        }
        if wanted, !renderer.hasPicture, LidCurves.isFolding(at: angle) {
            if let debugPicture {
                let scale = overlay.window.backingScaleFactor
                renderer.freeze(debugPicture, pixelSize: CGSize(width: overlay.window.frame.width * scale,
                                                                height: overlay.window.frame.height * scale))
            } else if let frame = stream?.latestFrame {
                renderer.freeze(frame)
            }
        }
        let needsStream = wanted && !renderer.hasPicture && debugPicture == nil
        if needsStream, let id = NSScreen.builtIn?.displayID {
            if stream == nil { stream = ScreenStream(device: renderer.device) }
            stream?.start(display: id)
        } else {
            stream?.stop()
        }
    }
}

/// CADisplayLink wants an Objective-C target.
private final class DisplayLinkTarget: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func fire() {
        MainActor.assumeIsolated { action() }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The MacBook's own display, or nil when it is shut with an external one.
    static var builtIn: NSScreen? {
        screens.first { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
    }
}

#if DEBUG
extension LidEffect {
    /// `NOSLEEP_LID_ANGLE=60` holds the lid at 60°; `NOSLEEP_LID_SWEEP=1`
    /// closes it from 110° to 0° and opens it again, every 16 s.
    static var debugAngle: (() -> Double?)? {
        let environment = ProcessInfo.processInfo.environment
        if let fixed = environment["NOSLEEP_LID_ANGLE"].flatMap(Double.init) { return { fixed } }
        if environment["NOSLEEP_LID_SWEEP"] == "1" {
            let start = Date()
            return {
                let phase = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 16) / 16
                return 110 * abs(1 - 2 * phase)
            }
        }
        return nil
    }

    /// `NOSLEEP_LID_POINTER=200,300` holds the pointer at that point on the
    /// built-in display, in points from its top-left corner.
    static var debugPointer: CGPoint? {
        let parts = ProcessInfo.processInfo.environment["NOSLEEP_LID_POINTER"]?.split(separator: ",").compactMap { Double($0) }
        guard let parts, parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }
}
#else
extension LidEffect {
    static var debugAngle: (() -> Double?)? { nil }
}
#endif

#if DEBUG
extension LidEffect {
    /// `NOSLEEP_LID_PROBE=<dir>` holds the lid at each of `angles` in turn,
    /// as if NoSleep were on, and writes a capture of the overlay at each,
    /// composited over `NOSLEEP_FOLD_PICTURE` where the overlay is clear,
    /// then exits. Own-window captures need no Screen Recording.
    func probe(to directory: URL, angles: [Double] = [98, 84, 66, 40, 10]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var current = angles[0]
        readAngle = { current }
        setAwake(true)
        for (index, angle) in angles.enumerated() {
            let at = 1.0 + Double(index) * 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { current = angle }
            DispatchQueue.main.asyncAfter(deadline: .now() + at + 2) { [weak self] in
                self?.writeCapture(to: directory.appendingPathComponent("lid-\(Int(angle)).png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(angles.count) * 2.5) { exit(0) }
    }

    private func writeCapture(to url: URL) {
        guard let overlay, let shot = Snapshots.captureOwnWindow(overlay.window) else { return }
        let width = shot.width, height = shot.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let debugPicture { context.draw(debugPicture, in: bounds) }
        context.draw(shot, in: bounds)
        guard let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
