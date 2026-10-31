import AppKit
import NoSleepCore
import Observation
import SwiftUI

/// The window over the built-in display while the lid comes down: the fold
/// underneath, the cat on top, and at the very end the light of its eyes
/// over all of it, with the eyes themselves on top again. It never takes focus or clicks, sits above
/// everything including full-screen apps, and is only ever up while NoSleep
/// is on with the lid below 100°.
@MainActor
final class LidOverlay {
    let window: NSWindow
    private let foldView: NSView
    /// Stands in for the fold near the end, when the picture has been let go
    /// or a fresh one is still on its way, so the desktop never flashes up.
    private let blackout: NSView
    private let cat = CatState()
    private let renderer: FoldRenderer?
    private let floodView: NSView
    private let flood: FloodRenderer?
    /// What the flood was last drawn with; nothing is redrawn until it changes.
    private var floodDrawn: (amount: Double, rise: Double)?

    var hasPicture: Bool { renderer?.hasPicture ?? false }
    var device: MTLDevice? { renderer?.device }

    init(screen: NSScreen, renderer: FoldRenderer?, flood: FloodRenderer?) {
        self.renderer = renderer
        self.flood = flood
        let frame = screen.frame
        window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        // Above the menu bar, the Dock and full-screen apps, as a screen saver is.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        foldView = NSView(frame: content.bounds)
        foldView.autoresizingMask = [.width, .height]
        foldView.wantsLayer = true
        if let renderer {
            renderer.layer.contentsScale = screen.backingScaleFactor
            foldView.layer = renderer.layer
            foldView.wantsLayer = true
        }
        foldView.isHidden = true
        content.addSubview(foldView)
        blackout = NSView(frame: content.bounds)
        blackout.autoresizingMask = [.width, .height]
        blackout.wantsLayer = true
        blackout.layer?.backgroundColor = .black
        blackout.isHidden = true
        content.addSubview(blackout)

        cat.layout = ScreenCatLayout(width: frame.width, height: frame.height)
        let host = NSHostingView(rootView: CatView(state: cat))
        host.frame = content.bounds
        host.autoresizingMask = [.width, .height]
        content.addSubview(host)

        floodView = NSView(frame: content.bounds)
        floodView.autoresizingMask = [.width, .height]
        if let flood {
            flood.layer.contentsScale = screen.backingScaleFactor
            floodView.layer = flood.layer
            floodView.wantsLayer = true
        }
        floodView.isHidden = true
        content.addSubview(floodView)
        let eyes = NSHostingView(rootView: FloodEyesView(state: cat))
        eyes.frame = content.bounds
        eyes.autoresizingMask = [.width, .height]
        content.addSubview(eyes)
        window.contentView = content
        window.setFrame(frame, display: false)
    }

    func show() {
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
        window.close()
        renderer?.release()
    }

    /// Moves to the built-in display's current frame, after a resolution change.
    func follow(_ screen: NSScreen) {
        guard window.frame != screen.frame else { return }
        window.setFrame(screen.frame, display: true)
        cat.layout = ScreenCatLayout(width: screen.frame.width, height: screen.frame.height)
        renderer?.layer.contentsScale = screen.backingScaleFactor
        flood?.layer.contentsScale = screen.backingScaleFactor
        floodDrawn = nil
    }

    /// Where the cat would look, with the lid at `angle`, for the pointer at
    /// `location` in global screen coordinates (y up).
    func look(at location: CGPoint, angle: Double) -> CatLook {
        let frame = window.frame
        let point = CGPoint(x: location.x - frame.minX, y: frame.maxY - location.y)
        return cat.layout.look(at: point, rise: LidCurves.catRise(at: angle))
    }

    /// One frame with the lid at `angle`. `folding` is false while there is
    /// no picture to fold, or no permission to take one. Values are only set
    /// when they change: each set redraws whatever reads it.
    func draw(angle: Double, folding: Bool, look: CatLook) {
        let rise = LidCurves.catRise(at: angle)
        if cat.rise != rise { cat.rise = rise }
        // The cat sits low on the glass, so it goes dark late, with its bottom.
        let light = LidCurves.lightLeft(darkness: LidCurves.darkness(at: angle), height: 0.25)
        if cat.light != light { cat.light = light }
        if cat.look != look { cat.look = look }

        let showFold = folding && LidCurves.isFolding(at: angle)
        if showFold, let renderer, renderer.hasPicture {
            foldView.isHidden = false
            renderer.render(angle: angle, size: window.frame.size, scale: window.backingScaleFactor)
        } else {
            foldView.isHidden = true
        }
        blackout.isHidden = !(showFold && !hasPicture && LidCurves.darkness(at: angle) > 0)

        // Over all of that, and never darkened: the screen ends lit by the eyes.
        let amount = LidCurves.flood(at: angle)
        if cat.flood != amount { cat.flood = amount }
        if amount > 0, let flood {
            floodView.isHidden = false
            if floodDrawn?.amount != amount || floodDrawn?.rise != rise {
                let drop = cat.layout.drop(rise: rise)
                let eyes = (0..<cat.layout.eyeCount).map { index in
                    var centre = cat.layout.eyeCentre(index)
                    centre.y += drop
                    return centre
                }
                flood.render(flood: amount, eyes: eyes, size: window.frame.size, scale: window.backingScaleFactor)
                floodDrawn = (amount, rise)
            }
        } else {
            floodView.isHidden = true
            floodDrawn = nil
        }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor @Observable
private final class CatState {
    var layout = ScreenCatLayout(width: 0, height: 0)
    var rise = 0.0
    var light = 1.0
    var look = CatLook.ahead
    var flood = 0.0
}

/// The whole cat in Liquid Glass, rising from below the bottom edge with its
/// eyes lit and its paws hooked over the edge: a soft shadow under it, the
/// glass, a smoky brown tint, a white rim along the edges that face up, then
/// the eyes. It is drawn once where it sits when up and slid as a whole, so
/// only the pupils are redrawn when the pointer moves.
private struct CatView: View {
    let state: CatState

    var body: some View {
        let shapes = CatShapes.shared(for: state.layout)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in Self.drawShadow(shapes, in: context) }
            CatGlass(shape: PathShape(path: Path(shapes.silhouette)))
            Canvas { context, _ in Self.drawCoat(shapes, in: context) }
            Pupils(state: state, shapes: shapes)
        }
        // Taller than the screen, so the chin and paws are still there when
        // the cat overshoots on its way up.
        .frame(width: shapes.layout.width, height: shapes.layout.height * 1.3, alignment: .topLeading)
        .modifier(Rise(state: state))
        .frame(width: shapes.layout.width, height: shapes.layout.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Slides and dims the cat without drawing it again: only this reads the
    /// rise and the light, so a frame of the lid moving is a move, not a redraw.
    private struct Rise: ViewModifier {
        let state: CatState

        func body(content: Content) -> some View {
            if state.rise > 0.001 {
                content
                    .offset(y: state.layout.drop(rise: state.rise))
                    .opacity(state.light)
            }
        }
    }

    /// The shadow alone, with the cat cut back out of it, since the glass goes there.
    private static func drawShadow(_ shapes: CatShapes, in context: GraphicsContext) {
        let unit = shapes.layout.pawUnit
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

    /// Everything that stays put on the glass: the smoke, the rim, the lit
    /// irises and the toes.
    private static func drawCoat(_ shapes: CatShapes, in context: GraphicsContext) {
        let layout = shapes.layout
        let unit = layout.pawUnit
        let top = CGPoint(x: 0, y: layout.top), bottom = CGPoint(x: 0, y: layout.height)
        // Smoky brown glass, the hero cat's colour, the desktop still showing.
        let fur = Gradient(colors: [Color(hex: 0x4a3726), Color(hex: 0x24190f)])
        context.drawLayer { smoke in
            smoke.opacity = 0.5
            smoke.fill(Path(shapes.head), with: .linearGradient(fur, startPoint: top, endPoint: bottom))
        }
        // The paws lie over the head, so they cast onto it and are a shade deeper.
        context.drawLayer { paws in
            paws.opacity = 0.55
            paws.addFilter(.shadow(color: .black.opacity(0.45), radius: unit * 0.15, x: 0, y: unit * 0.08))
            paws.fill(Path(shapes.paws), with: .color(Color(hex: 0x2a1d12)))
        }
        // Bright at the ears, faint by the chin.
        let light = Gradient(colors: [.white.opacity(0.85), .white.opacity(0.25)])
        for rim in [shapes.headRim, shapes.pawRim] {
            context.fill(Path(rim), with: .linearGradient(light, startPoint: top, endPoint: bottom))
        }
        drawIrises(layout, in: context)
        // Between the toes.
        for gaps in shapes.toeGaps {
            context.stroke(Path(gaps), with: .color(.black.opacity(0.4)),
                           style: StrokeStyle(lineWidth: layout.toeGapWidth, lineCap: .round))
        }
    }

    /// The irises, glowing.
    static func drawIrises(_ layout: ScreenCatLayout, in context: GraphicsContext) {
        let iris = Gradient(stops: [
            .init(color: Color(hex: 0xffe68a), location: 0),
            .init(color: Color(hex: 0xffd13d), location: 0.7),
            .init(color: Color(hex: 0xd99a00), location: 1),
        ])
        context.drawLayer { eyes in
            eyes.addFilter(.shadow(color: Color(hex: 0xffd13d).opacity(0.55), radius: glowRadius(layout)))
            for index in 0..<layout.eyeCount {
                // The site's iris is lit from a little above centre; one centre, nudged up, comes close.
                var centre = layout.eyeCentre(index)
                centre.y -= 5 * layout.scale
                eyes.fill(Path(layout.eye(index)), with: .radialGradient(
                    iris, center: centre, startRadius: 4 * layout.scale, endRadius: 45 * layout.scale))
            }
        }
    }

    /// The glow around the irises, in points.
    static func glowRadius(_ layout: ScreenCatLayout) -> Double { 15 * layout.scale }
}

/// The eyes alone, over the flood: the irises with their glow, the pupils
/// still on the pointer, the glints. Not in the view at all until the flood
/// starts, and never dimmed with the cat.
private struct FloodEyesView: View {
    let state: CatState

    var body: some View {
        let shapes = CatShapes.shared(for: state.layout)
        let layout = shapes.layout
        // Room for the glow, which a canvas would otherwise cut off.
        let bounds = layout.eyesBounds.insetBy(dx: -3 * CatView.glowRadius(layout), dy: -3 * CatView.glowRadius(layout))
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.translateBy(x: -bounds.minX, y: -bounds.minY)
                CatView.drawIrises(layout, in: context)
            }
            .frame(width: bounds.width, height: bounds.height)
            .offset(x: bounds.minX, y: bounds.minY)
            Pupils(state: state, shapes: shapes)
        }
        .frame(width: layout.width, height: layout.height * 1.3, alignment: .topLeading)
        .modifier(Lit(state: state))
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Only this reads the flood, so its frames move and fade the eyes
    /// without drawing them again.
    private struct Lit: ViewModifier {
        let state: CatState

        func body(content: Content) -> some View {
            if state.flood > 0 {
                content
                    .offset(y: state.layout.drop(rise: state.rise))
                    .opacity(LidCurves.eyesOverFlood(state.flood))
            }
        }
    }
}

/// The slit pupils and their glints, in a canvas no bigger than the eyes, so
/// a pointer moving redraws two small shapes and nothing else.
private struct Pupils: View {
    let state: CatState
    let shapes: CatShapes

    var body: some View {
        let layout = shapes.layout
        let bounds = layout.eyesBounds.insetBy(dx: -2, dy: -2)
        let look = state.look
        Canvas { context, _ in
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            for index in 0..<layout.eyeCount {
                context.fill(Path(layout.pupil(index, look: look)), with: .color(Color(hex: 0x120c07)))
                context.fill(Path(shapes.glints[index]), with: .color(.white.opacity(0.6)))
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .offset(x: bounds.minX, y: bounds.minY)
    }
}

/// The shapes that only change with the screen's size, built once: the
/// boolean operations are too slow to run every frame.
@MainActor
private final class CatShapes {
    let layout: ScreenCatLayout
    let head: CGPath
    let paws: CGPath
    let silhouette: CGPath
    let headRim: CGPath
    let pawRim: CGPath
    let toeGaps: [CGPath]
    let glints: [CGPath]

    private init(_ layout: ScreenCatLayout) {
        self.layout = layout
        head = layout.head
        paws = layout.paws
        silhouette = head.union(paws)
        headRim = layout.rim(of: head)
        pawRim = layout.rim(of: paws)
        toeGaps = ScreenCatLayout.Side.allCases.map(layout.toeGaps)
        glints = (0..<layout.eyeCount).map(layout.glint)
    }

    private static var last: CatShapes?

    static func shared(for layout: ScreenCatLayout) -> CatShapes {
        if let last, last.layout.width == layout.width, last.layout.height == layout.height { return last }
        let shapes = CatShapes(layout)
        last = shapes
        return shapes
    }
}

/// The cat's body: real Liquid Glass over whatever is behind, on macOS 26.
private struct CatGlass: View {
    let shape: PathShape

    var body: some View {
        if #available(macOS 26, *), !Self.forcesFallback {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            Color.clear.background(.ultraThinMaterial, in: shape)
        }
    }

    #if DEBUG
    /// `NOSLEEP_CAT_FALLBACK=1` draws the macOS 14 cat on a newer system.
    static let forcesFallback = ProcessInfo.processInfo.environment["NOSLEEP_CAT_FALLBACK"] == "1"
    #else
    static let forcesFallback = false
    #endif
}

private struct PathShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path { path }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}
