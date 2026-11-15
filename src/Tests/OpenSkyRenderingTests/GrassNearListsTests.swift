// The grass near list: the density test and the reach past the draw distance, and how
// far the camera may move before a group's list is built again.

@testable import OpenSkyRendering
import simd
import Testing

struct GrassNearListsTests {
    private static func instance(at x: Float, densityKey: Float) -> GrassDrawInstance {
        GrassDrawInstance(
            modelMatrix: matrix_identity_float4x4, normalMatrix: matrix_identity_float4x4,
            bounds: nil, position: SIMD3(x, 0, 0), color: SIMD3(repeating: 1),
            wavePeriod: 1, phase: 0, densityKey: densityKey
        )
    }

    /// Draw distance 1000 and a margin of 1024: an instance at 1500 is kept, one at 3000
    /// is not, and a density key at or over 0.5 is thinned out first.
    @Test func keepsDenseEnoughInstancesWithinTheReach() {
        let instances = [
            Self.instance(at: 100, densityKey: 0.1),
            Self.instance(at: 200, densityKey: 0.9),
            Self.instance(at: 1500, densityKey: 0.2),
            Self.instance(at: 3000, densityKey: 0.3)
        ]
        let list = GrassNearLists.build(
            instances, mesh: ObjectIdentifier(GrassNearListsTests.self),
            reach: GrassNearLists.Reach(viewer: .zero, density: 0.5, drawDistance: 1000)
        )
        #expect(list.indices == [0, 2])
        #expect(list.densityCulled == 1)
        #expect(list.outside == 1)
    }

    /// A list is kept while the camera stays near where it was built, and built again
    /// after the camera moves past the margin or the density changes.
    @Test func aListIsKeptUntilTheCameraMovesOrTheLimitsChange() {
        let instances = (0 ..< 4).map { Self.instance(at: Float($0) * 100, densityKey: 0.1) }
        let mesh = ObjectIdentifier(GrassNearListsTests.self)
        var lists = GrassNearLists()
        func reach(at x: Float, density: Float = 1) -> GrassNearLists.Reach {
            GrassNearLists.Reach(viewer: SIMD3(x, 0, 0), density: density, drawDistance: 1000)
        }
        lists.beginFrame(groupCount: 1)
        #expect(lists.list(of: instances, mesh: mesh, index: 0, reach: reach(at: 0)).indices
            .count == 4)
        #expect(lists.rebuiltLastFrame == 1)
        lists.beginFrame(groupCount: 1)
        _ = lists.list(of: instances, mesh: mesh, index: 0, reach: reach(at: 100))
        #expect(lists.rebuiltLastFrame == 0)
        lists.beginFrame(groupCount: 1)
        _ = lists.list(of: instances, mesh: mesh, index: 0, reach: reach(at: 5000))
        #expect(lists.rebuiltLastFrame == 1)
        lists.beginFrame(groupCount: 1)
        let thinned = lists.list(
            of: instances, mesh: mesh, index: 0, reach: reach(at: 5000, density: 0.05)
        )
        #expect(lists.rebuiltLastFrame == 1)
        #expect(thinned.densityCulled == 4)
        lists.beginFrame(groupCount: 0)
        lists.beginFrame(groupCount: 1)
        _ = lists.list(of: instances, mesh: mesh, index: 0, reach: reach(at: 5000, density: 0.05))
        #expect(lists.rebuiltLastFrame == 1)
    }

    @Test func aListIsReusedForAtMostTheMargin() {
        let distances = (0 ..< 16).map(GrassNearLists.reuseDistance(index:))
        #expect(distances.allSatisfy { $0 >= GrassNearLists.margin / 2 })
        #expect(distances.allSatisfy { $0 <= GrassNearLists.margin })
        #expect(Set(distances).count > 8)
    }
}
