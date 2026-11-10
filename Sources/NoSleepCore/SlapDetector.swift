// Ported from MacSlapApp (github.com/AbdullahFID/MacSlapApp).
// Copyright (c) 2026 Abdullah Khan. MIT License; see THIRD-PARTY-NOTICES.md.

import Foundation

/// One slap on the MacBook.
public struct Slap: Sendable, Equatable {
    /// Peak acceleration of the impact with gravity taken out, in g.
    public let magnitude: Double
    /// 0 for the softest slap that counts, 1 from about 1.8 g up, on a log
    /// curve so a firm slap already feels like most of the way.
    public let strength: Double
}

/// Finds slaps in the accelerometer's stream.
///
/// Typing and slaps separate cleanly on two measures at once, as MacSlapApp
/// found on real captures: hard typing reaches about 0.12 g, but its strong
/// moments are slow (the chassis rocking) and its fast moments are tiny (the
/// key click). A slap is strong and fast in the same instant. So a slap is
/// amplitude over `amplitude` with jerk over `jerk`, or amplitude over
/// `bigHit` on its own. The noise floor adapts, the peak is held briefly so
/// the strength is the true peak, and the ringing afterwards is ignored.
///
/// Every window is in seconds and converted at the measured rate: the sensor
/// usually streams at about 800 Hz but has been seen idling at 100 Hz.
public final class SlapDetector: @unchecked Sendable {
    public struct Thresholds: Sendable {
        public var amplitude: Double
        /// Σ|Δa|/Δt across the three axes, in g/s.
        public var jerk: Double
        public var bigHit: Double

        /// MacSlapApp's "Medium": firm slaps count, typing and a bumped desk don't.
        public static let standard = Thresholds(amplitude: 0.40, jerk: 30, bigHit: 0.90)
    }

    public static let nominalRate = 805.0
    public static let plausibleRates = 25.0...4000.0

    private static let gravityTimeConstant = 0.5
    private static let noiseTimeConstant = 1.25
    private static let warmup = 0.3
    private static let refractory = 0.14
    private static let peakHold = 0.05
    private static let sigmas = 7.0
    private static let softest = 0.15, hardest = 1.8

    private let thresholds: Thresholds
    private let lock = NSLock()
    private var rate: Double

    private var gravityAlpha = 0.0, noiseAlpha = 0.0
    private var warmupSamples = 0, refractorySamples = 0, peakHoldSamples = 1

    private var gravity: (x: Double, y: Double, z: Double)?
    private var previous: (x: Double, y: Double, z: Double)?
    private var noiseFloor: Double?
    private var noiseSpread = 0.01
    private var warmed = 0
    private var quiet = 0
    /// Samples into an impact, and its peak so far; nil between impacts.
    private var impact: (samples: Int, peak: Double)?

    public init(thresholds: Thresholds = .standard, rate: Double = SlapDetector.nominalRate) {
        self.thresholds = thresholds
        self.rate = Self.plausibleRates.contains(rate) ? rate : Self.nominalRate
        derive()
    }

    /// Adopts a measured rate; changes under 10% are jitter in the measurement.
    public func setRate(_ hz: Double) {
        guard hz.isFinite, Self.plausibleRates.contains(hz) else { return }
        lock.lock(); defer { lock.unlock() }
        guard abs(hz - rate) / rate >= 0.1 else { return }
        rate = hz
        derive()
    }

    /// After a gap in the stream, so a gravity estimate from before it can't read as a hit.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        gravity = nil
        previous = nil
        noiseFloor = nil
        noiseSpread = 0.01
        warmed = 0
        quiet = 0
        impact = nil
    }

    /// One sample, in g. Returns the slap this sample completed, if any.
    public func process(x: Double, y: Double, z: Double) -> Slap? {
        lock.lock(); defer { lock.unlock() }
        return step(x: x, y: y, z: z)
    }

    private func derive() {
        let dt = 1 / rate
        gravityAlpha = exp(-dt / Self.gravityTimeConstant)
        noiseAlpha = exp(-dt / Self.noiseTimeConstant)
        warmupSamples = Int((Self.warmup * rate).rounded())
        refractorySamples = Int((Self.refractory * rate).rounded())
        peakHoldSamples = max(1, Int((Self.peakHold * rate).rounded()))
    }

    private func step(x: Double, y: Double, z: Double) -> Slap? {
        let a = gravityAlpha
        var g = gravity ?? (x, y, z)
        g = (a * g.x + (1 - a) * x, a * g.y + (1 - a) * y, a * g.z + (1 - a) * z)
        gravity = g
        let linear = (x: x - g.x, y: y - g.y, z: z - g.z)
        let amplitude = (linear.x * linear.x + linear.y * linear.y + linear.z * linear.z).squareRoot()
        let jerk = previous.map { (abs(linear.x - $0.x) + abs(linear.y - $0.y) + abs(linear.z - $0.z)) * rate } ?? 0
        previous = linear

        if warmed < warmupSamples { warmed += 1; return nil }

        // Frozen while the signal is up, so a slap can't raise its own bar.
        if let floor = noiseFloor {
            if amplitude <= floor + 4 * noiseSpread + 0.02 {
                noiseFloor = noiseAlpha * floor + (1 - noiseAlpha) * amplitude
                noiseSpread = noiseAlpha * noiseSpread + (1 - noiseAlpha) * abs(amplitude - noiseFloor!)
            }
        } else {
            noiseFloor = amplitude
        }
        let bar = max(thresholds.amplitude, noiseFloor! + Self.sigmas * noiseSpread)

        if quiet > 0 { quiet -= 1; return nil }

        guard var current = impact else {
            if (amplitude >= bar && jerk >= thresholds.jerk) || amplitude >= thresholds.bigHit {
                impact = (0, amplitude)
            }
            return nil
        }
        current.samples += 1
        current.peak = max(current.peak, amplitude)
        guard amplitude < bar / 2 || current.samples >= peakHoldSamples else {
            impact = current
            return nil
        }
        impact = nil
        quiet = refractorySamples
        let t = min(max((current.peak - Self.softest) / (Self.hardest - Self.softest), 0), 1)
        return Slap(magnitude: current.peak, strength: log(1 + t * 99) / log(100))
    }
}
