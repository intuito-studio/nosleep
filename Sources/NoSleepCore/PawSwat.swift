import CoreGraphics
import Foundation

/// The cat's paw swatting at the pointer, on a screen `width` × `height`
/// points, y down. The cat sits below the bottom edge towards the middle, so
/// the paw comes up at a slant, toes first, pats the pointer once and goes
/// back down. Everything is drawn once where the paw is at full reach; a frame
/// only slides it back along its own line by `offset(at:)`.
public struct PawSwat: Sendable {
    public let width: Double
    public let height: Double
    /// Where the toes reach: the pointer, kept far enough in that the whole paw shows.
    public let target: CGPoint
    /// 0 to 1, from `Slap.strength`: a harder slap is a quicker swat.
    public let strength: Double
    /// How much of a screen's height the paw and the tail are drawn below
    /// the bottom edge, so the edge of what is drawn never comes up into
    /// view, even at the top of an overshoot.
    public static let overdraw = 0.3

    /// The hero cat's paw, so it is the same cat.
    public let unit: Double
    /// Turned from straight up towards the pointer, in radians.
    public let angle: Double

    public init(width: Double, height: Double, pointer: CGPoint, strength: Double) {
        self.width = width
        self.height = height
        self.strength = min(max(strength, 0), 1)
        unit = ScreenCatLayout(width: width, height: height).pawUnit
        target = CGPoint(x: min(max(pointer.x, unit * 0.6), width - unit * 0.6),
                         y: min(max(pointer.y, unit * 0.5), height - unit * 0.6))
        let shoulderX = target.x + (width / 2 - target.x) * 0.35
        angle = atan2(target.x - shoulderX, height + unit - target.y)
    }

    // MARK: - Shape

    /// Paw units to points at full reach: the toes' leading edge on the target.
    public var transform: CGAffineTransform {
        CGAffineTransform(translationX: target.x, y: target.y)
            .rotated(by: angle)
            .scaledBy(x: unit, y: unit)
            .translatedBy(x: 0, y: Self.toeTop)
    }

    static let toeCentres = [-0.3, -0.1, 0.1, 0.3]
    static let toeY = -0.26
    static let toeRadius = 0.13
    /// How far above the mitt's centre the middle toes reach.
    static let toeTop = 0.26 + 0.12

    /// Long enough that its far end stays below the bottom edge at full
    /// reach, and through the overshoot on the way up.
    var legLength: Double {
        (height - target.y) / cos(angle) / unit + 1
    }

    /// The hero cat's mitt turned toes up, on a foreleg that runs off the
    /// bottom of the screen and widens a little towards the cat.
    public var silhouette: CGPath {
        let t = transform
        let paw = CGMutablePath()
        paw.addEllipse(in: CGRect(x: -0.46, y: -0.3, width: 0.92, height: 0.6), transform: t)
        for x in Self.toeCentres {
            paw.addEllipse(in: CGRect(x: x - Self.toeRadius, y: Self.toeY - 0.12, width: 2 * Self.toeRadius, height: 0.24),
                           transform: t)
        }
        let leg = legLength
        paw.move(to: CGPoint(x: -0.37, y: 0), transform: t)
        paw.addLine(to: CGPoint(x: 0.37, y: 0), transform: t)
        paw.addLine(to: CGPoint(x: 0.44, y: leg), transform: t)
        paw.addLine(to: CGPoint(x: -0.44, y: leg), transform: t)
        paw.closeSubpath()
        return paw.union(paw)
    }

    /// The three dark lines between the toes.
    public var toeGaps: CGPath {
        let t = transform
        let path = CGMutablePath()
        for x in [-0.2, 0, 0.2] {
            path.move(to: CGPoint(x: x, y: -0.34), transform: t)
            path.addLine(to: CGPoint(x: x, y: -0.18), transform: t)
        }
        return path
    }

    public var toeGapWidth: Double { unit * 0.035 }

    // MARK: - Motion

    /// Seconds, start to gone.
    public var duration: Double { Self.length / speed }

    private var speed: Double { 1 + 0.35 * strength }
    private static let length = 0.8

    /// How far up the paw is at `time`: 0 out of sight, 1 toes on the pointer;
    /// it overshoots a little on the way up, then pats once.
    public func reach(at time: Double) -> Double {
        let t = time * speed
        switch t {
        case ..<0: return 0
        case ..<0.18:
            let p = t / 0.18 - 1, c = 1.2
            return 1 + (c + 1) * p * p * p + c * p * p
        case ..<0.26: return 1
        case ..<0.40: return 1 - 0.07 * sin(.pi * (t - 0.26) / 0.14)
        case ..<0.48: return 1
        case ..<Self.length:
            let p = (t - 0.48) / (Self.length - 0.48)
            return 1 - p * p * p
        default: return 0
        }
    }

    /// With Reduce Motion the paw doesn't move: it fades in at full reach and out again.
    public func opacity(at time: Double) -> Double {
        let t = time * speed
        return min(max(min(t / 0.15, (Self.length - t) / 0.2), 0), 1)
    }

    /// Down and back along the paw's own line from full reach, far enough at
    /// reach 0 that nothing of it shows above the bottom edge.
    public func offset(reach: Double, bounds: CGRect) -> CGSize {
        let hidden = (height - bounds.minY) / cos(angle) + 2
        let back = (1 - reach) * hidden
        return CGSize(width: -sin(angle) * back, height: cos(angle) * back)
    }
}
