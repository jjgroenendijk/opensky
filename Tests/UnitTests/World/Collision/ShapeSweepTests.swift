// Sphere and capsule casts against placed collision geometry (issue #193).
// The properties that matter to 15.4 and 15.5 are the ones asserted: a clear
// sweep reports nothing, a blocked one reports a distance short of the
// obstacle, an already-overlapping start says so, and equidistant shapes break
// the tie the same way `InteractionRaycaster` does.

@testable import opensky
import simd
import Testing

struct ShapeSweepTests {
    @Test
    func aClearSweepReportsNoHit() {
        let query = ShapeSweepQuery.sphere(
            center: SIMD3(0, 0, 100),
            radius: 4,
            direction: SIMD3(1, 0, 0),
            maximumDistance: 50
        )
        #expect(ShapeSweeper.firstHit(query: query, shapes: [DynamicBodyScene.floor()]) == nil)
    }

    @Test
    func aSphereCastStopsShortOfAWallByItsRadius() throws {
        let query = ShapeSweepQuery.sphere(
            center: SIMD3(0, 0, 50),
            radius: 6,
            direction: SIMD3(1, 0, 0),
            maximumDistance: 200
        )
        let hit = try #require(ShapeSweeper.firstHit(
            query: query, shapes: [DynamicBodyScene.wall(at: 100)]
        ))
        #expect(!hit.startsOverlapping)
        // The sphere's centre starts at x = 0 and its surface touches the wall
        // at x = 94, so the travel is 94 give or take the bisection's last step.
        #expect(abs(hit.distance - 94) < 1.5)
        #expect(hit.normal.x < -0.9)
        #expect(hit.reference == FormID(1))
    }

    @Test
    func aCapsuleCastIsBlockedByGeometryOnlyItsFarEndReaches() throws {
        // The segment runs up the Z axis; only its top end is level with the
        // wall panel, which sits above z = 100.
        let query = ShapeSweepQuery.capsule(
            first: SIMD3(0, 0, 10),
            second: SIMD3(0, 0, 130),
            radius: 4,
            direction: SIMD3(1, 0, 0),
            maximumDistance: 200
        )
        let panel = DynamicBodyScene.quad(
            SIMD3(100, -50, 100), SIMD3(100, -50, 200),
            SIMD3(100, 50, 200), SIMD3(100, 50, 100),
            reference: FormID(7)
        )
        let hit = try #require(ShapeSweeper.firstHit(query: query, shapes: [panel]))
        #expect(hit.reference == FormID(7))
        #expect(abs(hit.distance - 96) < 1.5)
    }

    @Test
    func aSweepStartingInsideGeometrySaysSo() throws {
        let query = ShapeSweepQuery.sphere(
            center: SIMD3(0, 0, 2),
            radius: 6,
            direction: SIMD3(1, 0, 0),
            maximumDistance: 100
        )
        let hit = try #require(ShapeSweeper.firstHit(
            query: query, shapes: [DynamicBodyScene.floor()]
        ))
        #expect(hit.startsOverlapping)
        #expect(hit.distance == 0)
    }

    /// Two coincident walls, the same distance away: the lower FormID wins,
    /// which is exactly `InteractionRaycaster`'s rule.
    @Test
    func coincidentShapesBreakTheTieOnTheLowerReference() throws {
        var high = DynamicBodyScene.wall(at: 100)
        high = StaticCollisionShape(
            reference: FormID(0x50),
            transform: high.transform,
            geometry: high.geometry,
            bounds: high.bounds
        )
        let low = StaticCollisionShape(
            reference: FormID(0x10),
            transform: high.transform,
            geometry: high.geometry,
            bounds: high.bounds
        )
        let query = ShapeSweepQuery.sphere(
            center: SIMD3(0, 0, 50),
            radius: 6,
            direction: SIMD3(1, 0, 0),
            maximumDistance: 200
        )
        let hit = try #require(ShapeSweeper.firstHit(query: query, shapes: [high, low]))
        #expect(hit.reference == FormID(0x10))
    }

    @Test
    func anImplausibleQueryIsRejectedRatherThanGuessedAt() {
        let shapes = [DynamicBodyScene.wall(at: 100)]
        let zeroLength = ShapeSweepQuery.sphere(
            center: .zero, radius: 4, direction: SIMD3(1, 0, 0), maximumDistance: 0
        )
        #expect(ShapeSweeper.firstHit(query: zeroLength, shapes: shapes) == nil)
        let notFinite = ShapeSweepQuery.sphere(
            center: SIMD3(.nan, 0, 0),
            radius: 4,
            direction: SIMD3(1, 0, 0),
            maximumDistance: 200
        )
        #expect(ShapeSweeper.firstHit(query: notFinite, shapes: shapes) == nil)
    }
}
