// The convex collider a dynamic body presents (issue #193): what each decoded
// geometry becomes, and the two queries the solver asks of it.

@testable import opensky
import simd
import Testing

struct DynamicCollisionVolumeTests {
    @Test
    func aBoxBecomesAHullWithSixOutwardPlanes() throws {
        let volume = try #require(
            DynamicCollisionVolume.make(from: .box(halfExtents: SIMD3(2, 3, 4)))
        )
        guard case let .hull(points, planes) = volume else {
            Issue.record("a box should decode to a hull")
            return
        }
        #expect(points.count == 8)
        #expect(planes.count == 6)
        // Every plane faces out: the centre is strictly inside all of them.
        #expect(planes.allSatisfy { simd_dot($0.normal, SIMD3<Float>.zero) < $0.offset })
        #expect(volume.localBounds.min == SIMD3(-2, -3, -4))
        #expect(volume.localBounds.max == SIMD3(2, 3, 4))
    }

    @Test
    func aHullReportsTheLeastSeparatedFace() throws {
        let volume = try #require(
            DynamicCollisionVolume.make(from: .box(halfExtents: SIMD3(repeating: 10)))
        )
        // Just outside the +Z face, within a two-unit probe radius.
        let hit = try #require(volume.penetration(of: SIMD3(0, 0, 11), radius: 2))
        #expect(hit.normal == SIMD3(0, 0, 1))
        #expect(abs(hit.depth - 1) < 1e-4)
        // Well clear of every face.
        #expect(volume.penetration(of: SIMD3(0, 0, 40), radius: 2) == nil)
        // Deep inside: the nearest face still decides the push direction.
        let inside = try #require(volume.penetration(of: SIMD3(0, 0, 9), radius: 0))
        #expect(inside.normal == SIMD3(0, 0, 1))
        #expect(abs(inside.depth - 1) < 1e-4)
    }

    @Test
    func aSphereAndACapsuleBothBecomeOneRadialCase() throws {
        let sphere = try #require(DynamicCollisionVolume.make(from: .sphere(radius: 5)))
        guard case let .radial(first, second, radius) = sphere else {
            Issue.record("a sphere should decode to a radial volume")
            return
        }
        #expect(first == second)
        #expect(radius == 5)
        #expect(sphere.contactSamples(position: .zero, orientation: .identityRotation).count == 1)

        let capsule = try #require(DynamicCollisionVolume.make(
            from: .capsule(first: SIMD3(0, 0, -4), second: SIMD3(0, 0, 4), radius: 2)
        ))
        #expect(capsule.contactSamples(position: .zero, orientation: .identityRotation).count == 2)
        // One unit off the axis, inside the two-unit skin.
        let hit = try #require(capsule.penetration(of: SIMD3(1, 0, 0), radius: 0))
        #expect(hit.normal == SIMD3(1, 0, 0))
        #expect(abs(hit.depth - 1) < 1e-4)
        // Three units off it, outside.
        #expect(capsule.penetration(of: SIMD3(3, 0, 0), radius: 0) == nil)
    }

    /// A concave soup cannot be simulated as authored, so it degrades to its own
    /// box rather than to nothing. That is the one lossy conversion in this
    /// layer and it is asserted rather than left implicit.
    @Test
    func aTriangleSoupDegradesToItsOwnBox() throws {
        let vertices = [
            SIMD3<Float>(-4, -6, 0), SIMD3<Float>(4, -6, 0),
            SIMD3<Float>(4, 6, 10), SIMD3<Float>(-4, 6, 10)
        ]
        let volume = try #require(DynamicCollisionVolume.make(
            from: .triangleSoup(vertices: vertices, indices: [0, 1, 2, 0, 2, 3])
        ))
        #expect(volume.localBounds.min == SIMD3(-4, -6, 0))
        #expect(volume.localBounds.max == SIMD3(4, 6, 10))
    }

    @Test
    func aDegenerateShapeProducesNoVolume() {
        #expect(DynamicCollisionVolume.make(from: .sphere(radius: 0)) == nil)
        #expect(DynamicCollisionVolume.make(from: .box(halfExtents: SIMD3(1, 0, 1))) == nil)
        // Three points cannot bound a volume, so no hull is built from them.
        #expect(DynamicCollisionVolume.hull(
            points: [.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            indices: [0, 1, 2]
        ) == nil)
    }

    @Test
    func translationMovesPointsAndPlanesTogether() throws {
        let volume = try #require(
            DynamicCollisionVolume.make(from: .box(halfExtents: SIMD3(repeating: 5)))
        )
        let moved = volume.translated(by: SIMD3(0, 0, 20))
        #expect(moved.localBounds.min == SIMD3(-5, -5, 15))
        // A point that was outside the original box is inside the moved one.
        #expect(moved.penetration(of: SIMD3(0, 0, 20), radius: 0) != nil)
        #expect(moved.penetration(of: SIMD3(0, 0, 0), radius: 0) == nil)
    }

    @Test
    func aRotatedHullKeepsItsOutwardFaces() throws {
        let volume = try #require(
            DynamicCollisionVolume.make(from: .box(halfExtents: SIMD3(2, 2, 20)))
        )
        let rotated = try #require(
            volume.transformed(by: MatrixMath.rotationY(radians: .pi / 2))
        )
        // The long axis is now X, so a point 10 out along X is inside and one
        // 10 out along Z is not.
        #expect(rotated.penetration(of: SIMD3(10, 0, 0), radius: 0) != nil)
        #expect(rotated.penetration(of: SIMD3(0, 0, 10), radius: 0) == nil)
    }
}
