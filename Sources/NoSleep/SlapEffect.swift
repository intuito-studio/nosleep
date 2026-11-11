import AppKit
import NoSleepCore
import Observation
import QuartzCore
import SwiftUI

/// While NoSleep is on, a slap on the MacBook gets the cat's paw: it comes up
/// from below the screen the pointer is on and swats at the pointer. Slapped
/// again within a few seconds, the cat gets impatient instead: its tail
/// lashes up from a bottom corner and a 💢 goes up along the top.
///
/// The accelerometer streams at about 800 Hz, so it runs only while NoSleep
/// is on and the screens are awake: with NoSleep off, or the lid shut and the
/// screen dark, the sensor is off and left as it was found.
@MainActor
final class SlapEffect {
    /// False on a Mac without the accelerometer; the feature is then absent.
    static let isSupported = Accelerometer.open() != nil

    private let sensor = Accelerometer.open()
    private let detector = SlapDetector()
    private let samples = SampleCount()
    private var awake = false
    private var screensAsleep = false
    private var running = false
    private var watchdog: Timer?
    private var lastCheck: TimeInterval = 0
    private var swat: SwatOverlay?
    private var annoyed: AnnoyedOverlay?
    private var mood = SlapMood()
    /// `NOSLEEP_SLAP_LOG=1`: the rate and peak every two seconds, and each slap, on stdout.
    private var logs = ProcessInfo.processInfo.environment["NOSLEEP_SLAP_LOG"] == "1"

    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensAsleep = true; self?.update() }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensAsleep = false; self?.update() }
        }
    }

    /// NoSleep switched on or off.
    func setAwake(_ awake: Bool) {
        self.awake = awake
        update()
    }

    /// On quit: sensor off, paw gone.
    func stop() {
        awake = false
        update()
        swat?.close()
        swat = nil
        annoyed?.close()
        annoyed = nil
    }

    private func update() {
        let wanted = awake && !screensAsleep && sensor != nil
        guard wanted != running else { return }
        running = wanted
        if wanted {
            startSensor()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            watchdog = timer
        } else {
            watchdog?.invalidate()
            watchdog = nil
            sensor?.stop()
            log("sensor off")
        }
    }

    private func startSensor() {
        guard let sensor else { return }
        detector.reset()
        _ = samples.take()
        lastCheck = ProcessInfo.processInfo.systemUptime
        let detector = detector, samples = samples, logs = logs
        let opened = sensor.start { [weak self] x, y, z in
            samples.add(peak: logs ? abs((x * x + y * y + z * z).squareRoot() - 1) : 0)
            guard let slap = detector.process(x: x, y: y, z: z) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.slapped(slap) } }
        }
        log(opened ? "sensor on" : "sensor did not open")
    }

    /// Every two seconds while running: the detector learns the real rate,
    /// and a stream that stopped (an SPU reset, a wake) is opened again.
    private func check() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let (count, peak) = samples.take()
        let rate = Double(count) / max(now - lastCheck, 0.001)
        lastCheck = now
        log(String(format: "%.0f Hz, peak %.3f g", rate, peak))
        if count == 0 {
            log("no samples, reopening")
            startSensor()
        } else {
            detector.setRate(rate)
        }
    }

    private func slapped(_ slap: Slap) {
        log(String(format: "slap %.2f g, strength %.2f", slap.magnitude, slap.strength))
        guard running else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { return }
        switch mood.react(at: ProcessInfo.processInfo.systemUptime) {
        case .swat:
            guard swat == nil else { return }
            let overlay = SwatOverlay(screen: screen, pointer: pointer, strength: slap.strength)
            swat = overlay
            overlay.play { [weak self, weak overlay] in
                guard let self, self.swat === overlay else { return }
                self.swat = nil
            }
        case .annoyed:
            guard annoyed == nil else { return }
            let overlay = AnnoyedOverlay(screen: screen)
            annoyed = overlay
            overlay.play { [weak self, weak overlay] in
                guard let self, self.annoyed === overlay else { return }
                self.annoyed = nil
            }
        }
    }

    private func log(_ message: String) {
        if logs { print("[slap] \(message)") }
    }
}

/// Samples counted on the sensor's thread, read on the main one.
private final class SampleCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var peak = 0.0

    func add(peak value: Double) {
        lock.lock(); count += 1; peak = max(peak, value); lock.unlock()
    }

    func take() -> (Int, Double) {
        lock.lock(); defer { count = 0; peak = 0; lock.unlock() }
        return (count, peak)
    }
}

// MARK: - The paw

/// One swat, in its own window over one screen: never key, never clicked,
/// above everything as the lid overlay is, and gone when the paw is.
@MainActor
final class SwatOverlay {
    let window: NSWindow
    private let state: SwatState
    private var displayLink: CADisplayLink?
    private var started: CFTimeInterval = 0
    private var finished: (() -> Void)?
    private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// `pointer` in global coordinates, y up.
    init(screen: NSScreen, pointer: CGPoint, strength: Double) {
        let frame = screen.frame
        let local = CGPoint(x: pointer.x - frame.minX, y: frame.maxY - pointer.y)
        let swat = PawSwat(width: frame.width, height: frame.height, pointer: local, strength: strength)
        state = SwatState(shapes: PawShapes(swat))
        window = OverlayWindow.passThrough(over: frame)
        let host = NSHostingView(rootView: PawView(state: state))
        host.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = host
        window.setFrame(frame, display: false)
    }

    func play(then finished: @escaping () -> Void) {
        self.finished = finished
        pose(at: 0)
        window.orderFrontRegardless()
        let link = window.contentView!.displayLink(target: SwatLinkTarget { [weak self] in self?.frame() },
                                                   selector: #selector(SwatLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Holds the paw still at `time` seconds into the swat, for the probe.
    func show(at time: Double) {
        pose(at: time)
        window.orderFrontRegardless()
    }

    func close() {
        displayLink?.invalidate()
        displayLink = nil
        window.orderOut(nil)
        window.close()
    }

    private func frame() {
        let now = CACurrentMediaTime()
        if started == 0 { started = now }
        let time = now - started
        guard time < state.shapes.swat.duration else {
            close()
            finished?()
            finished = nil
            return
        }
        pose(at: time)
    }

    private func pose(at time: Double) {
        let swat = state.shapes.swat
        state.reach = still ? 1 : swat.reach(at: time)
        state.opacity = still ? swat.opacity(at: time) : 1
    }
}

@MainActor @Observable
private final class SwatState {
    let shapes: PawShapes
    var reach = 0.0
    var opacity = 1.0

    init(shapes: PawShapes) { self.shapes = shapes }
}

/// The paw's shapes, built once per swat: the boolean operations are too slow for every frame.
private struct PawShapes {
    let swat: PawSwat
    let silhouette: CGPath
    let rim: CGPath
    let toeGaps: CGPath
    let bounds: CGRect

    init(_ swat: PawSwat) {
        self.swat = swat
        silhouette = swat.silhouette
        var down = CGAffineTransform(translationX: 0, y: swat.unit * 0.035)
        rim = silhouette.subtracting(silhouette.copy(using: &down) ?? silhouette)
        toeGaps = swat.toeGaps
        bounds = silhouette.boundingBoxOfPath
    }
}

/// The paw in the lid cat's Liquid Glass: a soft shadow, the glass, the
/// smoky brown, a white rim on the edges that face up, the lines between the
/// toes. Drawn once where it reaches; a frame only slides it.
private struct PawView: View {
    let state: SwatState

    var body: some View {
        let shapes = state.shapes
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in Self.drawShadow(shapes, in: context) }
            CatGlass(shape: PathShape(path: Path(shapes.silhouette)))
            Canvas { context, _ in Self.drawCoat(shapes, in: context) }
        }
        // Drawn taller than the screen: a canvas cuts off at its own edge,
        // and on the overshoot that edge would come up into view.
        .frame(width: shapes.swat.width, height: shapes.swat.height * (1 + PawSwat.overdraw), alignment: .topLeading)
        .modifier(Slide(state: state))
        .frame(width: shapes.swat.width, height: shapes.swat.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Only this reads the reach, so a frame is a move, not a redraw.
    private struct Slide: ViewModifier {
        let state: SwatState

        func body(content: Content) -> some View {
            content
                .offset(state.shapes.swat.offset(reach: state.reach, bounds: state.shapes.bounds))
                .opacity(state.opacity)
        }
    }

    private static func drawShadow(_ shapes: PawShapes, in context: GraphicsContext) {
        let unit = shapes.swat.unit
        let shape = Path(shapes.silhouette)
        context.drawLayer { layer in
            layer.drawLayer { shadow in
                shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: unit * 0.25, x: 0, y: unit * 0.12, options: .shadowOnly))
                shadow.fill(shape, with: .color(.black))
            }
            layer.blendMode = .destinationOut
            layer.fill(shape, with: .color(.black))
        }
    }

    private static func drawCoat(_ shapes: PawShapes, in context: GraphicsContext) {
        let bounds = shapes.bounds
        let top = CGPoint(x: 0, y: bounds.minY), bottom = CGPoint(x: 0, y: bounds.maxY)
        let fur = Gradient(colors: [Color(hex: 0x4a3726), Color(hex: 0x24190f)])
        context.drawLayer { smoke in
            smoke.opacity = 0.5
            smoke.fill(Path(shapes.silhouette), with: .linearGradient(fur, startPoint: top, endPoint: bottom))
        }
        let light = Gradient(colors: [.white.opacity(0.85), .white.opacity(0.25)])
        context.fill(Path(shapes.rim), with: .linearGradient(light, startPoint: top, endPoint: bottom))
        context.stroke(Path(shapes.toeGaps), with: .color(.black.opacity(0.4)),
                       style: StrokeStyle(lineWidth: shapes.swat.toeGapWidth, lineCap: .round))
    }
}

extension OverlayWindow {
    /// Over the whole of `frame` and everything on it, full-screen apps and
    /// the menu bar too, as the lid overlay is: clear, never key, never clicked.
    static func passThrough(over frame: NSRect) -> OverlayWindow {
        let window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.setFrame(frame, display: false)
        return window
    }
}

// MARK: - The tail and the 💢

/// The impatient cat, in its own window over one screen: the tail lashing
/// up from a bottom corner, the 💢 along the top, both gone together.
@MainActor
final class AnnoyedOverlay {
    let window: NSWindow
    private let state: AnnoyedState
    private var displayLink: CADisplayLink?
    private var started: CFTimeInterval = 0
    private var finished: (() -> Void)?
    private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    init(screen: NSScreen) {
        let frame = screen.frame
        var random = SystemRandomNumberGenerator()
        let tail = TailSwish(width: frame.width, height: frame.height, fromLeft: Bool.random(), along: .random(in: 0...1))
        let mark = AngerMark(width: frame.width, height: frame.height, using: &random)
        state = AnnoyedState(tail: TailShapes(tail), mark: mark)
        window = OverlayWindow.passThrough(over: frame)
        let host = NSHostingView(rootView: AnnoyedView(state: state))
        host.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = host
    }

    func play(then finished: @escaping () -> Void) {
        self.finished = finished
        pose(at: 0)
        window.orderFrontRegardless()
        let link = window.contentView!.displayLink(target: SwatLinkTarget { [weak self] in self?.frame() },
                                                   selector: #selector(SwatLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Holds it still at `time` seconds in, for the probe.
    func show(at time: Double) {
        pose(at: time)
        window.orderFrontRegardless()
    }

    func close() {
        displayLink?.invalidate()
        displayLink = nil
        window.orderOut(nil)
        window.close()
    }

    private func frame() {
        let now = CACurrentMediaTime()
        if started == 0 { started = now }
        let time = now - started
        guard time < TailSwish.duration else {
            close()
            finished?()
            finished = nil
            return
        }
        pose(at: time)
    }

    private func pose(at time: Double) {
        let tail = state.tail.swish
        state.rise = still ? 1 : tail.rise(at: time)
        state.angle = tail.angle(at: time, still: still)
        state.tailOpacity = still ? tail.opacity(at: time) : 1
        state.markScale = state.mark.scale(at: time, still: still)
        state.markOpacity = state.mark.opacity(at: time, still: still)
    }
}

@MainActor @Observable
private final class AnnoyedState {
    let tail: TailShapes
    let mark: AngerMark
    var rise = 0.0
    var angle = 0.0
    var tailOpacity = 1.0
    var markScale = 0.0
    var markOpacity = 0.0

    init(tail: TailShapes, mark: AngerMark) {
        self.tail = tail
        self.mark = mark
    }
}

private struct TailShapes {
    let swish: TailSwish
    let silhouette: CGPath
    let rim: CGPath
    let bounds: CGRect

    init(_ swish: TailSwish) {
        self.swish = swish
        silhouette = swish.silhouette
        var down = CGAffineTransform(translationX: 0, y: swish.unit * 0.08)
        rim = silhouette.subtracting(silhouette.copy(using: &down) ?? silhouette)
        bounds = silhouette.boundingBoxOfPath
    }

    private init(swish: TailSwish, silhouette: CGPath, rim: CGPath, bounds: CGRect) {
        self.swish = swish
        self.silhouette = silhouette
        self.rim = rim
        self.bounds = bounds
    }

    /// Turned `angle` radians about the base; the rim turns with it, close
    /// enough to the edge facing up for a lash this quick.
    func turned(by angle: Double) -> TailShapes {
        guard angle != 0 else { return self }
        let b = swish.base
        var t = CGAffineTransform(translationX: b.x, y: b.y).rotated(by: angle).translatedBy(x: -b.x, y: -b.y)
        return TailShapes(swish: swish, silhouette: silhouette.copy(using: &t) ?? silhouette,
                          rim: rim.copy(using: &t) ?? rim, bounds: bounds)
    }
}

/// The tail in the same glass and smoky brown as the paw and the lid cat,
/// with the 💢 over it.
private struct AnnoyedView: View {
    let state: AnnoyedState

    var body: some View {
        let swish = state.tail.swish
        ZStack(alignment: .topLeading) {
            Tail(state: state)
                .frame(width: swish.width, height: swish.height * (1 + PawSwat.overdraw), alignment: .topLeading)
                .modifier(Rise(state: state))
            Mark(state: state)
        }
        .frame(width: swish.width, height: swish.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Turned by turning its paths, not the view: glass under a
    /// `rotationEffect` is drawn away from the shape it belongs to. Turning a
    /// path is a matrix; only the boolean operations are too slow per frame.
    private struct Tail: View {
        let state: AnnoyedState

        var body: some View {
            let shapes = state.tail.turned(by: state.angle)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in AnnoyedView.drawShadow(shapes, in: context) }
                CatGlass(shape: PathShape(path: Path(shapes.silhouette)))
                Canvas { context, _ in AnnoyedView.drawCoat(shapes, in: context) }
            }
        }
    }

    /// Slides and fades it without drawing it again.
    private struct Rise: ViewModifier {
        let state: AnnoyedState

        func body(content: Content) -> some View {
            content
                .offset(y: state.tail.swish.drop(rise: state.rise, bounds: state.tail.bounds))
                .opacity(state.tailOpacity)
        }
    }

    private struct Mark: View {
        let state: AnnoyedState

        var body: some View {
            let mark = state.mark
            // Its own canvas, just big enough, so a throb scales a small picture.
            let box = CGRect(x: mark.centre.x - mark.size, y: mark.centre.y - mark.size,
                             width: mark.size * 2, height: mark.size * 2)
            Canvas { context, _ in
                context.translateBy(x: -box.minX, y: -box.minY)
                let shape = Path(mark.path)
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.3), radius: mark.size * 0.06, y: mark.size * 0.03))
                    // A thin dark-red edge, then the red, its horns rounded off.
                    layer.stroke(shape, with: .color(Color(hex: 0x6e140c)),
                                 style: StrokeStyle(lineWidth: mark.softening + mark.size * 0.025, lineCap: .round, lineJoin: .round))
                    layer.fill(shape, with: .color(Color(hex: 0xd3301f)))
                    layer.stroke(shape, with: .color(Color(hex: 0xd3301f)),
                                 style: StrokeStyle(lineWidth: mark.softening, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: box.width, height: box.height)
            .scaleEffect(state.markScale)
            .opacity(state.markOpacity)
            .position(mark.centre)
        }
    }

    private static func drawShadow(_ shapes: TailShapes, in context: GraphicsContext) {
        let unit = shapes.swish.unit
        let shape = Path(shapes.silhouette)
        context.drawLayer { layer in
            layer.drawLayer { shadow in
                shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: unit * 0.3, x: 0, y: unit * 0.12, options: .shadowOnly))
                shadow.fill(shape, with: .color(.black))
            }
            layer.blendMode = .destinationOut
            layer.fill(shape, with: .color(.black))
        }
    }

    private static func drawCoat(_ shapes: TailShapes, in context: GraphicsContext) {
        let bounds = shapes.bounds
        let top = CGPoint(x: 0, y: bounds.minY), bottom = CGPoint(x: 0, y: bounds.maxY)
        let fur = Gradient(colors: [Color(hex: 0x4a3726), Color(hex: 0x24190f)])
        context.drawLayer { smoke in
            smoke.opacity = 0.5
            smoke.fill(Path(shapes.silhouette), with: .linearGradient(fur, startPoint: top, endPoint: bottom))
        }
        let light = Gradient(colors: [.white.opacity(0.85), .white.opacity(0.25)])
        context.fill(Path(shapes.rim), with: .linearGradient(light, startPoint: top, endPoint: bottom))
    }
}

/// CADisplayLink wants an Objective-C target.
private final class SwatLinkTarget: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func fire() {
        MainActor.assumeIsolated { action() }
    }
}

#if DEBUG
extension SlapEffect {
    /// `NOSLEEP_SLAP_PROBE=<seconds>` runs the sensor alone, as if NoSleep
    /// were on, logging as `NOSLEEP_SLAP_LOG` does, then stops it and exits.
    func probeSensor(for seconds: TimeInterval) {
        logs = true
        setAwake(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
            stop()
            exit(0)
        }
    }

    /// `NOSLEEP_SWAT_PROBE=<dir>` holds a full-strength swat still at a few
    /// moments on the main screen, writes `swat-<ms>.png` of each over
    /// `NOSLEEP_FOLD_PICTURE` where the paw is clear, and exits. The pointer
    /// is `NOSLEEP_LID_POINTER` (points from the top-left), or a third of the
    /// way in and up. Own-window captures need no Screen Recording.
    static func probe(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let screen = NSScreen.main else { exit(1) }
        let frame = screen.frame
        let point = LidEffect.debugPointer ?? CGPoint(x: frame.width / 3, y: frame.height / 3)
        let pointer = CGPoint(x: frame.minX + point.x, y: frame.maxY - point.y)
        let background = ProcessInfo.processInfo.environment["NOSLEEP_FOLD_PICTURE"]
            .flatMap { NSImage(contentsOfFile: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        let moments = [0.06, 0.12, 0.22, 0.33, 0.55]
        for (index, time) in moments.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(index)) {
                let overlay = SwatOverlay(screen: screen, pointer: pointer, strength: 1)
                overlay.show(at: time)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let name = "swat-\(Int((time * 1000).rounded())).png"
                    write(overlay.window, over: background, to: directory.appendingPathComponent(name))
                    overlay.close()
                }
            }
        }
        let annoyedMoments = [0.2, 0.35, 0.5, 0.7]
        for (index, time) in annoyedMoments.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(moments.count + index)) {
                let overlay = AnnoyedOverlay(screen: screen)
                overlay.show(at: time)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let name = "annoyed-\(Int((time * 1000).rounded())).png"
                    write(overlay.window, over: background, to: directory.appendingPathComponent(name))
                    overlay.close()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(moments.count + annoyedMoments.count)) { exit(0) }
    }

    private static func write(_ window: NSWindow, over background: CGImage?, to url: URL) {
        guard let shot = Snapshots.captureOwnWindow(window) else { return }
        let bounds = CGRect(x: 0, y: 0, width: shot.width, height: shot.height)
        guard let context = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        if let background { context.draw(background, in: bounds) }
        context.draw(shot, in: bounds)
        guard let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
