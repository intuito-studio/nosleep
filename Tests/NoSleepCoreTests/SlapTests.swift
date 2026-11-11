import CoreGraphics
import Foundation
import Testing
@testable import NoSleepCore

/// A ringing knock on one axis: a decaying sine from `start` seconds.
private struct Knock {
    var start: Double
    var g: Double
    var hz: Double
    var decay: Double
    var axis = 2

    func value(at t: Double) -> Double {
        let dt = t - start
        guard dt >= 0, dt < decay * 12 else { return 0 }
        return g * exp(-dt / decay) * sin(2 * .pi * hz * dt)
    }
}

/// Feeds `seconds` of a MacBook lying flat, with a little sensor noise and
/// `knocks` on top, through a detector, and returns when each slap was found.
/// With `assumed`, the detector starts at that rate and is then told the real one.
private func slaps(_ knocks: [Knock], seconds: Double, rate: Double = 805, assumed: Double? = nil) -> [(time: Double, slap: Slap)] {
    let detector = SlapDetector(rate: assumed ?? rate)
    if assumed != nil { detector.setRate(rate) }
    var seed: UInt64 = 42
    func noise() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.006
    }
    var found: [(Double, Slap)] = []
    for i in 0..<Int(seconds * rate) {
        let t = Double(i) / rate
        var axes = [noise(), noise(), -1 + noise()]
        for knock in knocks { axes[knock.axis] += knock.value(at: t) }
        if let slap = detector.process(x: axes[0], y: axes[1], z: axes[2]) { found.append((t, slap)) }
    }
    return found
}

/// Hard typing, a key every 110 ms: alternately the chassis rocking (up to
/// 0.12 g but slow) and the click itself (fast but tiny).
private func typing(from start: Double, to end: Double) -> [Knock] {
    stride(from: start, to: end, by: 0.11).enumerated().map { index, t in
        index.isMultiple(of: 2)
            ? Knock(start: t, g: 0.12, hz: 18, decay: 0.03, axis: index % 3)
            : Knock(start: t, g: 0.03, hz: 300, decay: 0.004)
    }
}

@Suite("Telling a slap from everything else")
struct SlapDetectorTests {
    @Test("A Mac lying still never counts as slapped")
    func stillness() {
        #expect(slaps([], seconds: 5).isEmpty)
    }

    @Test("Hard typing never counts as a slap")
    func typingIsNotASlap() {
        #expect(slaps(typing(from: 1, to: 6), seconds: 6.5).isEmpty)
    }

    @Test("A firm slap is found once, within a tenth of a second")
    func firmSlap() {
        let found = slaps([Knock(start: 1, g: 0.7, hz: 150, decay: 0.01)], seconds: 2)
        #expect(found.count == 1)
        #expect(found.first.map { $0.time >= 1 && $0.time < 1.1 } == true)
    }

    @Test("A slap that rings on for a long time is still one slap")
    func ringing() {
        #expect(slaps([Knock(start: 1, g: 1.5, hz: 120, decay: 0.05)], seconds: 2).count == 1)
    }

    @Test("Two slaps a third of a second apart are two slaps")
    func twoSlaps() {
        let knocks = [Knock(start: 1, g: 0.8, hz: 150, decay: 0.01), Knock(start: 1.33, g: 0.8, hz: 150, decay: 0.01)]
        #expect(slaps(knocks, seconds: 2).count == 2)
    }

    @Test("A harder slap is a stronger one, and a very hard one is full strength")
    func strength() throws {
        let strengths = try [0.5, 0.9, 1.4, 4].map { g in
            try #require(slaps([Knock(start: 1, g: g, hz: 160, decay: 0.01)], seconds: 2).first).slap.strength
        }
        #expect(strengths == strengths.sorted())
        #expect(Set(strengths).count == strengths.count)
        #expect(strengths.last! > 0.95)
    }

    @Test("A sensor idling at 100 Hz still finds a slap, and still ignores typing")
    func slowSensor() {
        #expect(slaps([Knock(start: 1, g: 1.2, hz: 40, decay: 0.02)], seconds: 2, rate: 100).count == 1)
        #expect(slaps(typing(from: 1, to: 6), seconds: 6.5, rate: 100).isEmpty)
    }

    @Test("Once told the sensor runs at 100 Hz, the quiet after a slap stays 0.14 s, not 1.1 s")
    func adoptsRate() {
        let knocks = [Knock(start: 1, g: 1.2, hz: 40, decay: 0.02), Knock(start: 1.4, g: 1.2, hz: 40, decay: 0.02)]
        #expect(slaps(knocks, seconds: 2.5, rate: 100, assumed: 805).count == 2)
    }
}

@Suite("The paw that swats at the pointer")
struct PawSwatTests {
    let screen = (width: 1512.0, height: 982.0)

    func swat(at pointer: CGPoint, strength: Double = 0.5) -> PawSwat {
        PawSwat(width: screen.width, height: screen.height, pointer: pointer, strength: strength)
    }

    @Test("The paw starts and ends out of sight, below the bottom edge")
    func outOfSight() {
        for pointer in [CGPoint(x: 100, y: 80), CGPoint(x: 756, y: 500), CGPoint(x: 1450, y: 950)] {
            let paw = swat(at: pointer)
            let bounds = paw.silhouette.boundingBoxOfPath
            for time in [0, paw.duration, paw.duration + 1] {
                let offset = paw.offset(reach: paw.reach(at: time), bounds: bounds)
                #expect(bounds.minY + offset.height >= screen.height, "showing at \(time) s for \(pointer)")
            }
        }
    }

    @Test("At full reach the toes are on the pointer")
    func toesOnPointer() {
        let pointer = CGPoint(x: 500, y: 300)
        let paw = swat(at: pointer)
        let toes = CGPoint(x: 0, y: -PawSwat.toeTop).applying(paw.transform)
        #expect(hypot(toes.x - pointer.x, toes.y - pointer.y) < 0.5)
    }

    @Test("Its foreleg runs off the bottom of the screen even at the top of the overshoot")
    func legReachesBottom() {
        let paw = swat(at: CGPoint(x: 756, y: 40))
        let peak = stride(from: 0.0, to: paw.duration, by: 0.002).map(paw.reach(at:)).max()!
        #expect(peak > 1)
        let bounds = paw.silhouette.boundingBoxOfPath
        let offset = paw.offset(reach: peak, bounds: bounds)
        #expect(bounds.maxY + offset.height > screen.height)
    }

    @Test("The paw leans in from the middle: up and to the left for a pointer on the left")
    func leansFromMiddle() {
        #expect(swat(at: CGPoint(x: 100, y: 300)).angle < 0)
        #expect(swat(at: CGPoint(x: 1400, y: 300)).angle > 0)
        #expect(abs(swat(at: CGPoint(x: 756, y: 300)).angle) < 1e-9)
    }

    @Test("A harder slap gets a quicker swat")
    func harderIsQuicker() {
        #expect(swat(at: CGPoint(x: 500, y: 300), strength: 1).duration < swat(at: CGPoint(x: 500, y: 300), strength: 0).duration)
    }

    @Test("A pointer at the very edge is kept far enough in for the whole paw to show")
    func edgePointer() {
        let paw = swat(at: CGPoint(x: 0, y: 0))
        #expect(paw.target.x >= paw.unit * 0.6 && paw.target.y >= paw.unit * 0.5)
    }

    @Test("With Reduce Motion the paw fades in and out rather than moving")
    func fades() {
        let paw = swat(at: CGPoint(x: 500, y: 300))
        #expect(paw.opacity(at: 0) == 0)
        #expect(paw.opacity(at: paw.duration / 2) == 1)
        #expect(paw.opacity(at: paw.duration) == 0)
    }
}

@Suite("The cat losing patience")
struct AnnoyedTests {
    let screen = (width: 1512.0, height: 982.0)

    @Test("The first slap gets a swat; another within four seconds gets the tail and the 💢")
    func escalates() {
        var mood = SlapMood()
        #expect(mood.react(at: 100) == .swat)
        #expect(mood.react(at: 102) == .annoyed)
        #expect(mood.react(at: 105.5) == .annoyed)
    }

    @Test("Left alone for four seconds, the cat calms down and swats again")
    func calmsDown() {
        var mood = SlapMood()
        _ = mood.react(at: 100)
        #expect(mood.react(at: 104.5) == .swat)
    }

    @Test("The tail starts and ends out of sight, below the bottom edge")
    func tailOutOfSight() {
        for left in [true, false] {
            let tail = TailSwish(width: screen.width, height: screen.height, fromLeft: left, along: 0.5)
            let bounds = tail.silhouette.boundingBoxOfPath
            for time in [0, TailSwish.duration, TailSwish.duration + 1] {
                #expect(bounds.minY + tail.drop(rise: tail.rise(at: time), bounds: bounds) >= screen.height)
            }
        }
    }

    @Test("Standing, the tail comes up about half the screen from its bottom corner")
    func tailHeight() {
        let tail = TailSwish(width: screen.width, height: screen.height, fromLeft: true, along: 0)
        let bounds = tail.silhouette.boundingBoxOfPath
        #expect(bounds.minY > screen.height * 0.4 && bounds.minY < screen.height * 0.6)
        #expect(tail.base.x < screen.width * 0.25)
        #expect(bounds.maxY > screen.height)
    }

    @Test("The tail lashes both ways, several times, and is still before and after")
    func lashes() {
        let tail = TailSwish(width: screen.width, height: screen.height, fromLeft: false, along: 0.3)
        let angles = stride(from: 0.0, to: TailSwish.duration, by: 0.01).map { tail.angle(at: $0) }
        let crossings = zip(angles, angles.dropFirst()).filter { ($0 < 0) != ($1 < 0) && $0 != 0 && $1 != 0 }.count
        #expect(crossings >= 5)
        #expect(angles.map(abs).max()! > 0.25)
        #expect(tail.angle(at: 0) == 0 && tail.angle(at: TailSwish.duration) == 0)
        #expect(tail.angle(at: 0.6, still: true) == 0)
    }

    @Test("The 💢 lands along the top of the screen, never off it")
    func markPlace() {
        var random = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let mark = AngerMark(width: screen.width, height: screen.height, using: &random)
            #expect(mark.centre.y < screen.height * 0.3)
            #expect(mark.centre.x - mark.size / 2 > 0 && mark.centre.x + mark.size / 2 < screen.width)
            #expect(mark.centre.y - mark.size / 2 > 0)
        }
    }

    @Test("The 💢 is drawn, not typed: four crescents, one per corner, inside its size")
    func markIsDrawn() {
        var starts = 0
        AngerMark.symbol.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { starts += 1 }
        }
        #expect(starts == 4)
        var random = SystemRandomNumberGenerator()
        let mark = AngerMark(width: screen.width, height: screen.height, using: &random)
        let bounds = mark.path.boundingBoxOfPath
        // Turned, its corners can reach a little past `size`, never past √2 of it.
        #expect(bounds.width <= mark.size * 1.42 && bounds.height <= mark.size * 1.42)
        #expect(abs(bounds.midX - mark.centre.x) < 1 && abs(bounds.midY - mark.centre.y) < 1)
    }

    @Test("Each 💢 is turned its own way, within 30° either side, never as far as an X")
    func markTilt() {
        var random = SystemRandomNumberGenerator()
        let tilts = (0..<200).map { _ in AngerMark(width: screen.width, height: screen.height, using: &random).tilt }
        #expect(tilts.allSatisfy { abs($0) <= .pi / 6 + 1e-9 })
        #expect(Set(tilts).count > 150)
        #expect(tilts.contains { $0 < -0.2 } && tilts.contains { $0 > 0.2 })
    }

    @Test("The 💢 pops up, throbs, and is gone by the time the tail is")
    func markMotion() {
        var random = SystemRandomNumberGenerator()
        let mark = AngerMark(width: screen.width, height: screen.height, using: &random)
        #expect(mark.scale(at: 0) == 0)
        #expect(stride(from: 0.05, to: 0.25, by: 0.005).map { mark.scale(at: $0) }.max()! > 1.05)
        #expect(mark.scale(at: 0.74) > 1.1)
        #expect(mark.opacity(at: TailSwish.duration) == 0)
    }
}

@Suite("What is drawn below the bottom edge")
struct OverdrawTests {
    let screen = (width: 1512.0, height: 982.0)

    @Test("At the top of their overshoot, the paw and the tail rise less than what is drawn below the screen")
    func overshootStaysHidden() {
        let below = screen.height * PawSwat.overdraw
        for pointer in [CGPoint(x: 756, y: 40), CGPoint(x: 100, y: 500)] {
            let paw = PawSwat(width: screen.width, height: screen.height, pointer: pointer, strength: 1)
            let bounds = paw.silhouette.boundingBoxOfPath
            let peak = stride(from: 0.0, to: paw.duration, by: 0.002).map(paw.reach(at:)).max()!
            #expect(-paw.offset(reach: peak, bounds: bounds).height < below * 0.5)
        }
        for left in [true, false] {
            let tail = TailSwish(width: screen.width, height: screen.height, fromLeft: left, along: 1)
            let bounds = tail.silhouette.boundingBoxOfPath
            let peak = stride(from: 0.0, to: TailSwish.duration, by: 0.002).map(tail.rise(at:)).max()!
            #expect(peak > 1)
            #expect(-tail.drop(rise: peak, bounds: bounds) < below * 0.5)
        }
    }

    @Test("However far the tail lashes, its lower end stays below the bottom edge")
    func tailEndHidden() {
        for left in [true, false] {
            let tail = TailSwish(width: screen.width, height: screen.height, fromLeft: left, along: 0.5)
            let bounds = tail.silhouette.boundingBoxOfPath
            let peak = stride(from: 0.0, to: TailSwish.duration, by: 0.002).map(tail.rise(at:)).max()!
            let lift = -tail.drop(rise: peak, bounds: bounds)
            // The spine's lower end, the stroke's half-width around it, turned the furthest it goes.
            let end = CGPoint(x: tail.base.x, y: tail.base.y + 0.6 * tail.unit)
            let reach = stride(from: 0.0, to: TailSwish.duration, by: 0.002).map { abs(tail.angle(at: $0)) }.max()!
            let lowest = tail.base.y + (end.y - tail.base.y) * cos(reach) - tail.thickness / 2 * sin(reach)
            #expect(lowest - lift > screen.height)
        }
    }
}
