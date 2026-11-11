import CoreGraphics
import Foundation

/// How the cat takes a slap. The first one, it swats back at the pointer.
/// Slapped again before it has calmed down, it gets impatient: its tail
/// swishes and a 💢 goes up.
public struct SlapMood: Sendable {
    public enum Reaction: Sendable, Equatable {
        case swat
        case annoyed
    }

    /// How long after a slap the cat still minds the next one, in seconds.
    public static let memory = 4.0

    private var last: Double?

    public init() {}

    /// The reaction to a slap at `time` seconds, on any steady clock.
    public mutating func react(at time: Double) -> Reaction {
        defer { last = time }
        guard let last, time - last < Self.memory else { return .swat }
        return .annoyed
    }
}

/// The cat's tail coming up from below one bottom corner of a screen `width`
/// × `height` points, y down, swishing back and forth, then going down again.
/// It is drawn once standing at rest; a frame only turns it about its base
/// and slides it.
public struct TailSwish: Sendable {
    public let width: Double
    public let height: Double
    /// Where it comes up from the bottom edge.
    public let base: CGPoint
    /// +1 from the left, leaning and curling towards the middle; −1 from the right.
    public let side: Double
    /// Tail units to points: the tail stands about half the screen tall.
    public let unit: Double

    /// `along` is 0 to 1 across the corner it comes up in, 0 nearest the edge.
    public init(width: Double, height: Double, fromLeft: Bool, along: Double) {
        self.width = width
        self.height = height
        side = fromLeft ? 1 : -1
        let inset = width * (0.1 + 0.12 * min(max(along, 0), 1))
        base = CGPoint(x: fromLeft ? inset : width - inset, y: height)
        unit = height * 0.5 / 3.1
    }

    /// From below the bottom edge up through a gentle bend, the tip hooked
    /// back over, the way a cat holds a tail it is about to lash.
    public var spine: CGPath {
        let t = CGAffineTransform(translationX: base.x, y: base.y).scaledBy(x: side * unit, y: unit)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0.6), transform: t)
        path.addCurve(to: CGPoint(x: 0.45, y: -2.5), control1: CGPoint(x: -0.1, y: -1.1),
                      control2: CGPoint(x: 0.55, y: -1.7), transform: t)
        path.addCurve(to: CGPoint(x: -0.05, y: -3.0), control1: CGPoint(x: 0.4, y: -2.95),
                      control2: CGPoint(x: 0.15, y: -3.1), transform: t)
        return path
    }

    public var thickness: Double { unit * 0.42 }

    /// The tail's outline: the spine stroked thick, with a round tip.
    public var silhouette: CGPath {
        let outline = spine.copy(strokingWithWidth: thickness, lineCap: .round, lineJoin: .round, miterLimit: 1)
        return outline.union(outline)
    }

    // MARK: - Motion

    public static let duration = 2.1

    /// How far up it is: 0 out of sight, 1 standing; it overshoots a touch
    /// coming up and drops quickly at the end.
    public func rise(at t: Double) -> Double {
        switch t {
        case ..<0: return 0
        case ..<0.3:
            let p = t / 0.3 - 1, c = 1.0
            return 1 + (c + 1) * p * p * p + c * p * p
        case ..<1.75: return 1
        case ..<Self.duration:
            let p = (t - 1.75) / (Self.duration - 1.75)
            return 1 - p * p
        default: return 0
        }
    }

    /// Turned about its base, in radians, positive clockwise: quick lashes
    /// from side to side, out to their full sweep in a moment and dying
    /// down as it sinks. With `still`, it only stands.
    public func angle(at t: Double, still: Bool = false) -> Double {
        guard !still, t > 0.1, t < Self.duration else { return 0 }
        let swell = min((t - 0.1) / 0.25, 1) * min(max((Self.duration - t) / 0.45, 0), 1)
        return side * 0.34 * swell * sin(2 * .pi * 2.4 * (t - 0.1))
    }

    /// How far down from standing it is at `rise`, so that at 0 none of it shows.
    public func drop(rise: Double, bounds: CGRect) -> Double {
        (1 - rise) * (height - bounds.minY + 2)
    }

    /// With Reduce Motion it fades in standing and fades out again.
    public func opacity(at t: Double) -> Double {
        min(max(min(t / 0.2, (Self.duration - t) / 0.3), 0), 1)
    }
}

/// The 💢, somewhere along the top of the screen, usually in a corner.
/// Drawn as paths, never from the emoji font, so it looks the same on every
/// macOS and never falls back to a missing-glyph box.
public struct AngerMark: Sendable {
    /// Its centre, points from the top-left.
    public let centre: CGPoint
    /// Points across.
    public let size: Double
    /// Turned a little, either way, so no two look stamped from one die.
    public let tilt: Double

    public init(width: Double, height: Double, using random: inout some RandomNumberGenerator) {
        size = ScreenCatLayout(width: width, height: height).pawUnit * 0.6
        // Short of 45°, where it would read as an X.
        tilt = Double.random(in: -30...30, using: &random) * .pi / 180
        let corner = Double.random(in: 0..<1, using: &random) < 2.0 / 3
        let x: Double
        if corner {
            let left = Bool.random(using: &random)
            let into = Double.random(in: 0.06...0.22, using: &random)
            x = left ? into : 1 - into
        } else {
            x = Double.random(in: 0.25...0.75, using: &random)
        }
        let y = Double.random(in: 0.06...(corner ? 0.26 : 0.18), using: &random)
        // Kept a whole mark in from the edges, throb and all.
        let margin = size * 0.75
        centre = CGPoint(x: min(max(x * width, margin), width - margin), y: max(y * height, margin))
    }

    /// The mark on a 2 × 2 grid centred on the origin, y down: four
    /// crescents, one on each side, bowed in towards the centre with their
    /// horns pointing out to the corners, as the 💢 emoji is drawn.
    public static let symbol: CGPath = {
        let path = CGMutablePath()
        for quarter in 0..<4 {
            let t = CGAffineTransform(rotationAngle: Double(quarter) * .pi / 2)
            path.move(to: CGPoint(x: -0.65, y: -0.98), transform: t)
            // The inner edge dips to -0.48 at the middle, the outer to -0.75.
            path.addCurve(to: CGPoint(x: 0.65, y: -0.98), control1: CGPoint(x: -0.38, y: -0.31),
                          control2: CGPoint(x: 0.38, y: -0.31), transform: t)
            path.addCurve(to: CGPoint(x: -0.65, y: -0.98), control1: CGPoint(x: 0.3, y: -0.67),
                          control2: CGPoint(x: -0.3, y: -0.67), transform: t)
            path.closeSubpath()
        }
        return path
    }()

    /// The mark in points, `size` across, on its centre.
    public var path: CGPath {
        var t = CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: tilt).scaledBy(x: size / 2, y: size / 2)
        return Self.symbol.copy(using: &t) ?? Self.symbol
    }

    /// The rounding on its points, in points: the crescents are stroked this wide too.
    public var softening: Double { size * 0.03 }

    /// Pops up past its size and settles, throbs twice like a vein, then
    /// fades, within the tail's time. With `still`, it only fades.
    public func scale(at t: Double, still: Bool = false) -> Double {
        if still { return 1 }
        switch t {
        case ..<0.05: return 0
        case ..<0.25:
            let p = (t - 0.05) / 0.2 - 1, c = 2.2
            return 1 + (c + 1) * p * p * p + c * p * p
        default:
            let throb = [0.65, 1.15].map { start -> Double in
                let p = (t - start) / 0.18
                return p > 0 && p < 1 ? 0.15 * sin(.pi * p) : 0
            }.reduce(0, +)
            return 1 + throb
        }
    }

    public func opacity(at t: Double, still: Bool = false) -> Double {
        let fadeIn = still ? min(max(t / 0.2, 0), 1) : (t < 0.05 ? 0 : 1)
        return min(fadeIn, min(max((TailSwish.duration - 0.05 - t) / 0.35, 0), 1))
    }
}
