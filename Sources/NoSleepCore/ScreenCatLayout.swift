import CoreGraphics

/// The cat on a screen `width` × `height` points, y down: the app's cat head,
/// big, its chin below the bottom edge, and two front paws hooked over that
/// edge at its cheeks. Everything here is where the cat sits once it is up;
/// `drop(rise:)` says how far below that it is on the way. The home page draws
/// the same cat (`drawPaws` in site/lib/screen.ts).
public struct ScreenCatLayout: Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public enum Side: Double, CaseIterable, Sendable {
        case left = -1, right = 1
    }

    /// Head grid units (230 × 200) to points: the head is 70% of the screen wide.
    public var scale: Double { width * 0.7 / 230 }
    /// The unit a paw is drawn in, the hero cat's paw width.
    public var pawUnit: Double { 56 * scale }
    /// Where the ear tips are once the cat is up.
    public var top: Double { height - pawUnit * 0.76 - 132 * scale }

    /// How far below its place the cat is. `rise` is `LidCurves.catRise`: at 0
    /// the cat is a whole screen lower, out of sight; past 1 it overshoots.
    public func drop(rise: Double) -> Double { (1 - rise) * height }

    // MARK: - The head

    public var headTransform: CGAffineTransform {
        CGAffineTransform(translationX: width / 2 - 115 * scale, y: top).scaledBy(x: scale, y: scale)
    }

    /// Ears up top, a wide round jaw, a small point at each cheek. The same
    /// outline as `CatGlyph.head` and `CAT_HEAD` in site/lib/cat.ts, which
    /// this module cannot import: change one, change all three.
    static let headOutline: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 120))
        path.addLine(to: CGPoint(x: 12, y: 116))
        path.addCurve(to: CGPoint(x: 42, y: 0), control1: CGPoint(x: 12, y: 70), control2: CGPoint(x: 28, y: 10))
        path.addCurve(to: CGPoint(x: 80, y: 46), control1: CGPoint(x: 54, y: 8), control2: CGPoint(x: 66, y: 36))
        path.addCurve(to: CGPoint(x: 150, y: 46), control1: CGPoint(x: 102, y: 36), control2: CGPoint(x: 128, y: 36))
        path.addCurve(to: CGPoint(x: 188, y: 0), control1: CGPoint(x: 164, y: 36), control2: CGPoint(x: 176, y: 8))
        path.addCurve(to: CGPoint(x: 218, y: 116), control1: CGPoint(x: 202, y: 10), control2: CGPoint(x: 218, y: 70))
        path.addLine(to: CGPoint(x: 230, y: 120))
        path.addCurve(to: CGPoint(x: 115, y: 200), control1: CGPoint(x: 226, y: 172), control2: CGPoint(x: 178, y: 200))
        path.addCurve(to: CGPoint(x: 0, y: 120), control1: CGPoint(x: 52, y: 200), control2: CGPoint(x: 4, y: 172))
        path.closeSubpath()
        return path
    }()

    public var head: CGPath {
        var t = headTransform
        return Self.headOutline.copy(using: &t) ?? Self.headOutline
    }

    // MARK: - The paws

    /// Out at the cheeks, gripping the bezel from outside: only their backs
    /// come over the bottom edge, the toes stay below it.
    public func pawTransform(_ side: Side) -> CGAffineTransform {
        CGAffineTransform(translationX: width / 2 + side.rawValue * width * 0.34, y: height - pawUnit * 0.2)
            .rotated(by: side.rawValue * 0.12)
            .scaledBy(x: pawUnit, y: pawUnit)
    }

    static let toeCentres = [-0.3, -0.1, 0.1, 0.3]
    static let toeY = 0.26

    /// The hero cat's mitt: a broad oval and four toes along its lower edge.
    public func paw(_ side: Side) -> CGPath {
        let t = pawTransform(side)
        let mitt = CGMutablePath()
        mitt.addEllipse(in: CGRect(x: -0.46, y: 0.06 - 0.3, width: 0.92, height: 0.6), transform: t)
        for x in Self.toeCentres {
            mitt.addEllipse(in: CGRect(x: x - 0.13, y: Self.toeY - 0.12, width: 0.26, height: 0.24), transform: t)
        }
        return mitt.union(mitt)
    }

    public var paws: CGPath {
        paw(.left).union(paw(.right))
    }

    /// The three dark lines between the toes, as segments to stroke `toeGapWidth` wide.
    public func toeGaps(_ side: Side) -> CGPath {
        let t = pawTransform(side)
        let path = CGMutablePath()
        for x in [-0.2, 0, 0.2] {
            path.move(to: CGPoint(x: x, y: 0.18), transform: t)
            path.addLine(to: CGPoint(x: x, y: 0.34), transform: t)
        }
        return path
    }

    public var toeGapWidth: Double { pawUnit * 0.035 }

    public func toes(_ side: Side) -> [CGPoint] {
        Self.toeCentres.map { CGPoint(x: $0, y: Self.toeY).applying(pawTransform(side)) }
    }

    // MARK: - Glass and light

    /// One outline for the glass: head and paws together.
    public var silhouette: CGPath { head.union(paws) }

    /// The edges that face up: the outline less itself moved down a touch.
    public func rim(of shape: CGPath) -> CGPath {
        var down = CGAffineTransform(translationX: 0, y: pawUnit * 0.035)
        return shape.subtracting(shape.copy(using: &down) ?? shape)
    }

    // MARK: - The eyes

    /// Centre and radii on the head grid, as `CatGlyph.eyes` and `CAT_EYES`.
    static let eyeCentres = [CGPoint(x: 70, y: 107), CGPoint(x: 160, y: 107)]
    static let eyeRadii = CGSize(width: 29, height: 45)
    /// How far a pupil moves for a full look, in grid units, as on the hero cat.
    public static let lookReach = CGSize(width: 13, height: 16)

    public var eyeCount: Int { Self.eyeCentres.count }

    public func eye(_ index: Int) -> CGPath {
        CGPath(ellipseIn: Self.eyeRect(index), transform: [headTransform])
    }

    /// The eye's centre in points.
    public func eyeCentre(_ index: Int) -> CGPoint { Self.eyeCentres[index].applying(headTransform) }

    /// Both eyes' bounds in points, with the glints and pupils inside.
    public var eyesBounds: CGRect {
        (0..<eyeCount).map { eye($0).boundingBoxOfPath }.reduce(CGRect.null) { $0.union($1) }
    }

    /// The slit pupil, its tips rounded, turned by `look` and cut to the eye,
    /// since at the far ends of a look its tips would poke past the lids.
    public func pupil(_ index: Int, look: CatLook) -> CGPath {
        let cx = Self.eyeCentres[index].x
        let top = 75.0, bottom = 139.0, mid = (top + bottom) / 2, w = 6.2
        let slit = CGMutablePath()
        slit.move(to: CGPoint(x: cx, y: top))
        slit.addCurve(to: CGPoint(x: cx + w, y: mid), control1: CGPoint(x: cx + 2.4, y: top), control2: CGPoint(x: cx + w, y: top + 20))
        slit.addCurve(to: CGPoint(x: cx, y: bottom), control1: CGPoint(x: cx + w, y: bottom - 20), control2: CGPoint(x: cx + 2.4, y: bottom))
        slit.addCurve(to: CGPoint(x: cx - w, y: mid), control1: CGPoint(x: cx - 2.4, y: bottom), control2: CGPoint(x: cx - w, y: bottom - 20))
        slit.addCurve(to: CGPoint(x: cx, y: top), control1: CGPoint(x: cx - w, y: top + 20), control2: CGPoint(x: cx - 2.4, y: top))
        slit.closeSubpath()
        var turn = CGAffineTransform(translationX: look.x * Self.lookReach.width, y: look.y * Self.lookReach.height)
            .concatenating(headTransform)
        let moved = slit.copy(using: &turn) ?? slit
        return moved.intersection(eye(index))
    }

    /// The glint: a small tilted oval high in the eye.
    public func glint(_ index: Int) -> CGPath {
        let c = Self.eyeCentres[index]
        let t = CGAffineTransform(translationX: c.x - 10, y: c.y - 22).rotated(by: -0.3).concatenating(headTransform)
        return CGPath(ellipseIn: CGRect(x: -5, y: -7, width: 10, height: 14), transform: [t])
    }

    static func eyeRect(_ index: Int) -> CGRect {
        let c = eyeCentres[index], r = eyeRadii
        return CGRect(x: c.x - r.width, y: c.y - r.height, width: 2 * r.width, height: 2 * r.height)
    }

    /// How far `point` (screen points, y down) is from the nearer eye, in
    /// screen heights, with the cat at `rise`: the flood's own measure.
    public func floodDistance(to point: CGPoint, rise: Double) -> Double {
        let drop = drop(rise: rise)
        return (0..<eyeCount).map { index in
            let centre = eyeCentre(index)
            return hypot(point.x - centre.x, point.y - centre.y - drop) / height
        }.min() ?? .infinity
    }

    /// Where the cat looks for a pointer at `point` (screen points, y down)
    /// with the cat at `rise`: towards it, from between its eyes, all the way
    /// once the pointer is about its own head's width away, as on the hero cat.
    public func look(at point: CGPoint, rise: Double) -> CatLook {
        let centre = CGPoint(x: 115, y: 107).applying(headTransform)
        let reach = scale * 220
        let dx = (point.x - centre.x) / reach
        let dy = (point.y - centre.y - drop(rise: rise)) / reach
        return CatLook(x: min(1, max(-1, dx)), y: min(1, max(-1, dy)))
    }
}

/// Which way the pupils point: −1 to 1 on each axis, 0 straight ahead.
public struct CatLook: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let ahead = CatLook(x: 0, y: 0)
}
