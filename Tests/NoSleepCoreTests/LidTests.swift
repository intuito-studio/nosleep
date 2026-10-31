import CoreGraphics
import Foundation
import Testing
@testable import NoSleepCore

@Suite("What the lid shows as it closes")
struct LidCurveTests {
    @Test("Nothing is shown in normal use, with the lid above 100°")
    func normalUse() {
        #expect(!LidCurves.isShown(at: 100))
        #expect(!LidCurves.isShown(at: 125))
        #expect(LidCurves.isShown(at: 99.9))
    }

    @Test("The cat starts rising below 98° and is fully up at 84°")
    func riseRange() {
        #expect(LidCurves.catRise(at: 110) == 0)
        #expect(LidCurves.catRise(at: 98) == 0)
        #expect(LidCurves.catRise(at: 97) > 0)
        #expect(abs(LidCurves.catRise(at: 84) - 1) < 1e-12)
        #expect(abs(LidCurves.catRise(at: 10) - 1) < 1e-12)
    }

    @Test("The cat overshoots a little on the way up, so it lands rather than stops")
    func riseOvershoot() {
        let peak = stride(from: 98.0, through: 84, by: -0.25).map(LidCurves.catRise(at:)).max()!
        #expect(peak > 1.02 && peak < 1.2)
    }

    @Test("The fold starts at 92° and reaches full strength 58° later")
    func foldRange() {
        #expect(LidCurves.foldProgress(at: 92) == 0)
        #expect(!LidCurves.isFolding(at: 92))
        #expect(LidCurves.isFolding(at: 91.9))
        #expect(abs(LidCurves.foldProgress(at: 63) - 0.5) < 1e-12)
        #expect(LidCurves.foldProgress(at: 34) == 1)
        #expect(LidCurves.foldProgress(at: 0) == 1)
    }

    @Test("Frost starts gently and darkening starts early, as in Mac Duo's Duo look")
    func foldShape() {
        let fold = LidCurves.fold
        #expect(abs(fold.blurStrength(progress: 0.5) - pow(0.5, 1.55)) < 1e-12)
        #expect(abs(fold.dimStrength(progress: 0.5) - pow(0.5, 0.75)) < 1e-12)
        #expect(fold.blurStrength(progress: 0.3) < 0.3)
        #expect(fold.dimStrength(progress: 0.3) > 0.3)
    }

    @Test("The screen goes dark only between 16° and 3°, the far edge first")
    func darkness() {
        #expect(LidCurves.darkness(at: 16) == 0)
        #expect(LidCurves.darkness(at: 3) == 1)
        #expect(LidCurves.darkness(at: 0) == 1)
        let d = LidCurves.darkness(at: 9)
        #expect(LidCurves.lightLeft(darkness: d, height: 1) < LidCurves.lightLeft(darkness: d, height: 0))
        #expect(LidCurves.lightLeft(darkness: 0, height: 1) == 1)
        #expect(LidCurves.lightLeft(darkness: 1, height: 0) == 0)
    }
}

@Suite("The light of the cat's eyes at the end")
struct LidFloodTests {
    /// The built-in display of a 14-inch MacBook Pro, and the home page's screen.
    let screens = [ScreenCatLayout(width: 1512, height: 982), ScreenCatLayout(width: 2560, height: 1663)]

    func corners(of layout: ScreenCatLayout) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: layout.width, y: 0),
         CGPoint(x: 0, y: layout.height), CGPoint(x: layout.width, y: layout.height)]
    }

    @Test("The screen is untouched by the flood above 22°")
    func untouchedAbove() {
        for angle in [22.0, 30, 60, 98] {
            #expect(LidCurves.flood(at: angle) == 0)
        }
        #expect(LidCurves.flood(at: 21.9) > 0)
    }

    @Test("The flood starts as a glow at the eyes and spreads outwards as the lid comes down")
    func spreads() {
        let layout = screens[0]
        let corner = layout.floodDistance(to: .zero, rise: 1)
        let early = LidCurves.flood(at: 20)
        #expect(LidCurves.floodCover(distance: 0, flood: early) == 1)
        #expect(LidCurves.floodCover(distance: corner, flood: early) == 0)
        let covers = stride(from: 22.0, through: 10, by: -1).map {
            LidCurves.floodCover(distance: 0.5, flood: LidCurves.flood(at: $0))
        }
        #expect(zip(covers, covers.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("By 10° the flood covers every corner of the screen")
    func coversByTen() {
        #expect(LidCurves.flood(at: 10) == 1)
        for layout in screens {
            for corner in corners(of: layout) {
                #expect(LidCurves.floodCover(distance: layout.floodDistance(to: corner, rise: 1), flood: 1) == 1)
            }
        }
    }

    @Test("The flood is not put out by the dark: shut, the screen is still all orange")
    func staysLit() {
        let layout = screens[0]
        for angle in [4.0, 3, 0] {
            let flood = LidCurves.flood(at: angle)
            #expect(flood == 1)
            for corner in corners(of: layout) {
                #expect(LidCurves.floodCover(distance: layout.floodDistance(to: corner, rise: 1), flood: flood) == 1)
            }
        }
    }

    @Test("The flood is amber at the eyes and a deeper orange at the edges")
    func colour() {
        let eyes = LidCurves.floodColour(distance: 0), edge = LidCurves.floodColour(distance: 1.4)
        #expect(eyes == SIMD3(1, 0.46, 0.03))
        #expect(abs(edge.y - 0.14) < 1e-12 && edge.z == 0)
        #expect(LidCurves.floodColour(distance: 0.7).y < eyes.y)
    }

    @Test("The eyes stay visible over the flood")
    func eyesOnTop() {
        #expect(LidCurves.eyesOverFlood(0) == 0)
        #expect(LidCurves.eyesOverFlood(0.3) == 1)
        for angle in stride(from: 14.0, through: 0, by: -1) {
            #expect(LidCurves.eyesOverFlood(LidCurves.flood(at: angle)) == 1)
        }
    }

    @Test("The flood is measured from the nearer eye, in screen heights, following the cat as it rises")
    func distance() {
        let layout = screens[0]
        #expect(layout.floodDistance(to: layout.eyeCentre(0), rise: 1) == 0)
        #expect(layout.floodDistance(to: layout.eyeCentre(1), rise: 1) == 0)
        var below = layout.eyeCentre(0)
        below.y += layout.height * 0.1
        #expect(abs(layout.floodDistance(to: below, rise: 1) - 0.1) < 1e-9)
        #expect(abs(layout.floodDistance(to: below, rise: 0.9)) < 1e-9)
    }
}

@Suite("Where the frozen picture lands on the glass")
struct FoldGeometryTests {
    let geometry = FoldGeometry(screenWidth: 1512, screenHeight: 982, startAngle: 92)

    @Test("The fold is the identity at its start angle, so there is no seam when it begins")
    func identityAtStart() {
        let corners = geometry.corners(at: 92)
        let screen = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: 1512, y: 0), ScreenPoint(x: 1512, y: 982), ScreenPoint(x: 0, y: 982)]
        for (corner, expected) in zip(corners, screen) {
            #expect(abs(corner.x - expected.x) < 1e-6 && abs(corner.y - expected.y) < 1e-6)
        }
    }

    @Test("As the lid folds, the picture's far edge climbs past the top of the glass and its sides draw in")
    func recedes() {
        let corners = geometry.corners(at: 50)
        #expect(corners[2].y > 982 && corners[3].y > 982)
        #expect(corners[3].x > 0 && corners[2].x < 1512)
        // The hinge stays put: the bottom edge is where it was.
        #expect(abs(corners[0].y) < 1e-6 && abs(corners[1].y) < 1e-6)
    }

    @Test("The homography carries the picture's corners onto the quad, and back")
    func homography() {
        let corners = geometry.corners(at: 60)
        let forward = Homography.matrix(width: 1512, height: 982, to: corners)
        let picture = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: 1512, y: 0), ScreenPoint(x: 1512, y: 982), ScreenPoint(x: 0, y: 982)]
        for (p, corner) in zip(picture, corners) {
            let mapped = Homography.apply(forward, to: p)
            #expect(abs(mapped.x - corner.x) < 1e-6 && abs(mapped.y - corner.y) < 1e-6)
            let back = Homography.apply(forward.inverse, to: corner)
            #expect(abs(back.x - p.x) < 1e-6 && abs(back.y - p.y) < 1e-6)
        }
    }
}

@Suite("Smoothing the sensor's ten steps a second")
struct DampedSpringTests {
    @Test("The spring reaches a new reading without overshooting it")
    func noOvershoot() {
        var spring = DampedSpring(value: 110, frequency: 14)
        var lowest = 110.0
        for _ in 0..<120 {
            spring.advance(toward: 60, dt: 1.0 / 60)
            lowest = min(lowest, spring.value)
        }
        #expect(lowest >= 60 - 0.01)
        #expect(spring.isSettled(at: 60, tolerance: 0.05))
    }

    @Test("The spring is mostly there within a sensor refresh or three")
    func quick() {
        var spring = DampedSpring(value: 100, frequency: 14)
        for _ in 0..<18 { spring.advance(toward: 90, dt: 1.0 / 60) }
        #expect(spring.value < 92)
    }
}

@Suite("Where the cat sits on the screen")
struct ScreenCatLayoutTests {
    let layout = ScreenCatLayout(width: 1512, height: 982)

    @Test("The cat is fully hidden above 98°, below the bottom edge")
    func hidden() {
        let rise = LidCurves.catRise(at: 98)
        #expect(layout.silhouette.boundingBoxOfPath.minY + layout.drop(rise: rise) >= 982)
    }

    @Test("Up, the head is centred, its ears high on the screen and its chin off the bottom")
    func head() {
        let head = layout.head.boundingBoxOfPath
        #expect(abs(head.midX - 1512 / 2) < 0.5)
        #expect(abs(head.width - 1512 * 0.7) < 0.5)
        #expect(head.minY > 0 && head.minY < 982 * 0.3)
        #expect(head.maxY > 982)
        #expect(layout.drop(rise: 1) == 0)
    }

    @Test("The paws hook over the bottom edge at the cheeks, their toes below it")
    func paws() {
        let left = layout.paw(.left).boundingBoxOfPath
        let right = layout.paw(.right).boundingBoxOfPath
        #expect(abs(left.midX - 1512 * 0.16) < 1512 * 0.02 && abs(right.midX - 1512 * 0.84) < 1512 * 0.02)
        #expect(left.minY < 982 && left.maxY > 982)
        for side in ScreenCatLayout.Side.allCases {
            #expect(layout.toes(side).allSatisfy { $0.y > 982 })
        }
    }

    @Test("The two paws are mirror images")
    func mirrored() {
        let left = layout.paw(.left).boundingBoxOfPath
        let right = layout.paw(.right).boundingBoxOfPath
        #expect(abs(left.minX - (1512 - right.maxX)) < 0.5)
        #expect(abs(left.minY - right.minY) < 0.5)
    }

    @Test("The rim is only the edges that face up")
    func rim() {
        let rim = layout.rim(of: layout.head).boundingBoxOfPath
        let head = layout.head.boundingBoxOfPath
        #expect(!rim.isEmpty)
        #expect(abs(rim.minY - head.minY) < 0.5)
        #expect(rim.maxY < head.maxY - 10)
    }

    @Test("Pupils never leave the eye, however far the pointer goes, and never vanish")
    func pupilsStayInside() {
        for index in 0..<layout.eyeCount {
            let eye = layout.eye(index).boundingBoxOfPath
            for x in [-1.0, 0, 1] {
                for y in [-1.0, 0, 1] {
                    let pupil = layout.pupil(index, look: CatLook(x: x, y: y))
                    // Every point of the outline is on or inside the eye's ellipse.
                    let outside = points(of: pupil.flattened(threshold: 0.1)).map { p in
                        pow((p.x - eye.midX) / (eye.width / 2), 2) + pow((p.y - eye.midY) / (eye.height / 2), 2)
                    }.max() ?? 0
                    #expect(outside < 1.01)
                    #expect(pupil.boundingBoxOfPath.height > 30 * layout.scale)
                }
            }
        }
    }

    private func points(of path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint {
                points.append(element.pointee.points[0])
            }
        }
        return points
    }

    @Test("The eyes look towards the pointer, and no further than all the way")
    func look() {
        let rise = 1.0
        let ahead = layout.look(at: CGPoint(x: 756, y: layout.eyeCentre(0).y), rise: rise)
        #expect(abs(ahead.x) < 1e-9 && abs(ahead.y) < 1e-9)
        let left = layout.look(at: CGPoint(x: -5000, y: 0), rise: rise)
        #expect(left.x == -1 && left.y < 0 && left.y >= -1)
        let right = layout.look(at: CGPoint(x: 1512, y: 982), rise: rise)
        #expect(right.x > 0.5 && right.y > 0)
        let leftPupil = layout.pupil(0, look: left).boundingBoxOfPath
        let rightPupil = layout.pupil(0, look: right).boundingBoxOfPath
        #expect(leftPupil.midX < layout.eyeCentre(0).x && rightPupil.midX > layout.eyeCentre(0).x)
    }

    @Test("A cat still rising looks from where it is, not where it will be")
    func lookWhileRising() {
        let pointer = CGPoint(x: 756, y: 900)
        #expect(layout.look(at: pointer, rise: 0.5).y < layout.look(at: pointer, rise: 1).y)
    }
}
