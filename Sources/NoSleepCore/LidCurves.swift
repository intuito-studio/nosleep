import Foundation

/// What NoSleep shows on the way down, by hinge angle, while it is on. The
/// cat comes up from below the screen once the lid passes upright; from 92° the picture is held
/// still in the room while the lid folds around it (Mac Duo's "Duo" look);
/// it goes dark only at the very end, before macOS turns the display off.
/// Everything is a function of the angle, so opening runs it backwards.
/// The home page draws the same curves (site/lib/laptop-scene.ts).
public enum LidCurves {
    /// Above this the overlay is gone: the lid is where it is in normal use.
    public static let showBelow = 100.0
    public static let catFrom = 98.0
    public static let catUp = 84.0
    public static let fold = FoldCurve(startAngle: 92, span: 58)
    public static let darkFrom = 16.0
    public static let darkAt = 3.0
    public static let floodFrom = 22.0
    public static let floodFull = 10.0

    public static func isShown(at angle: Double) -> Bool { angle < showBelow }

    /// 0 hidden below the bezel, 1 up. Overshoots a little on the way, so the
    /// cat lands rather than stops.
    public static func catRise(at angle: Double) -> Double {
        backOut(clamp01((catFrom - angle) / (catFrom - catUp)))
    }

    public static func foldProgress(at angle: Double) -> Double { fold.progress(at: angle) }

    /// Whether the fold has anything to do: at its start angle it is the screen itself.
    public static func isFolding(at angle: Double) -> Bool { angle < fold.startAngle }

    /// 0 until the lid is nearly shut, 1 when it is.
    public static func darkness(at angle: Double) -> Double {
        clamp01((darkFrom - angle) / (darkFrom - darkAt))
    }

    /// How much of the light is left `height` up the glass (0 hinge, 1 top):
    /// the far edge goes first.
    public static func lightLeft(darkness: Double, height: Double) -> Double {
        1 - smoothstep(0, 1, darkness * (1.3 + (height - 0.5) * 0.6))
    }

    /// 0 until 22°, 1 from 10°: the light of the cat's eyes spreading over
    /// the whole screen. The dark never reaches it, so the screen ends warm
    /// and its light leaks from the gap until the lid is shut.
    public static func flood(at angle: Double) -> Double {
        smoothstep(0, 1, clamp01((floodFrom - angle) / (floodFrom - floodFull)))
    }

    /// How much of the flood covers a point `distance` screen heights from
    /// the nearer eye: solid out to 45% of its reach, a soft front beyond.
    /// Only meaningful while `flood(at:)` is above 0; at 0 nothing is drawn.
    public static func floodCover(distance: Double, flood: Double) -> Double {
        let reach = 0.05 + (2.3 - 0.05) * flood
        return 1 - smoothstep(reach * 0.45, reach, distance)
    }

    /// The flood's colour in linear light: amber at the eyes, a deeper
    /// orange towards the edges.
    public static func floodColour(distance: Double) -> SIMD3<Double> {
        let t = smoothstep(0, 1.4, distance)
        return SIMD3(1, 0.46, 0.03) + (SIMD3(1, 0.14, 0) - SIMD3(1, 0.46, 0.03)) * t
    }

    /// How strongly the eyes are drawn again over the flood: in by the time
    /// it is a third of the way, so they never drown in their own light.
    public static func eyesOverFlood(_ flood: Double) -> Double {
        smoothstep(0, 0.3, flood)
    }

    public static func backOut(_ t: Double) -> Double {
        1 + 2.4 * pow(t - 1, 3) + 1.4 * pow(t - 1, 2)
    }

    static func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamp01((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }
}
