// The room/portal visibility walk and the room an instance belongs to.
// Rooms are 200-unit cubes in a row along +X; the camera stands in room A at the
// origin and looks along +X.

@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
import simd
import Testing

struct RoomPortalGraphTests {
    static func box(
        at center: SIMD3<Float>,
        half: SIMD3<Float> = SIMD3(repeating: 100)
    ) throws -> OrientedBox {
        try #require(OrientedBox(transform: MatrixMath.translation(center), halfExtents: half))
    }

    static func portal(
        _ first: Int32,
        _ second: Int32,
        at center: SIMD3<Float>,
        half: SIMD3<Float> = SIMD3(1, 50, 50)
    ) throws -> RoomPortalGraph.Portal {
        try RoomPortalGraph.Portal(box: box(at: center, half: half), rooms: SIMD2(first, second))
    }

    static var lookingEast: float4x4 {
        let view = MatrixMath.lookAt(eye: .zero, target: SIMD3(1, 0, 0), up: SIMD3(0, 0, 1))
        return MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65), aspectRatio: 1,
            nearZ: 1, farZ: 10000
        ) * view
    }

    /// A, B, C in a row east; D behind the camera to the west.
    static func row() throws -> RoomPortalGraph {
        try RoomPortalGraph(
            rooms: [
                box(at: .zero), box(at: SIMD3(200, 0, 0)), box(at: SIMD3(400, 0, 0)),
                box(at: SIMD3(-200, 0, 0))
            ],
            portals: [
                portal(0, 1, at: SIMD3(100, 0, 0)), portal(1, 2, at: SIMD3(300, 0, 0)),
                portal(0, 3, at: SIMD3(-100, 0, 0))
            ],
            links: []
        )
    }

    @Test func seesThroughPortalsAheadButNotBehind() throws {
        let visibility = try #require(
            Self.row().visibleRooms(eye: .zero, viewProjection: Self.lookingEast)
        )
        #expect(visibility.contains(room: 0))
        #expect(visibility.contains(room: 1))
        #expect(visibility.contains(room: 2))
        #expect(!visibility.contains(room: 3))
        #expect(visibility.visibleCount == 3)
        #expect(visibility.contains(room: RoomPortalGraph.noRoom))
    }

    @Test func aPortalOutsideTheNarrowedRectHidesItsRoom() throws {
        let graph = try RoomPortalGraph(
            rooms: [
                Self.box(at: .zero),
                Self.box(at: SIMD3(200, 0, 0)),
                Self.box(at: SIMD3(400, 0, 0))
            ],
            portals: [
                Self.portal(0, 1, at: SIMD3(100, 0, 0), half: SIMD3(1, 10, 10)),
                Self.portal(1, 2, at: SIMD3(300, 90, 0), half: SIMD3(1, 5, 5))
            ],
            links: []
        )
        let visibility = try #require(
            graph.visibleRooms(eye: .zero, viewProjection: Self.lookingEast)
        )
        #expect(visibility.contains(room: 1))
        #expect(!visibility.contains(room: 2))
    }

    @Test func linkedRoomsAreSeenTogether() throws {
        let graph = try RoomPortalGraph(
            rooms: [Self.box(at: .zero), Self.box(at: SIMD3(-200, 0, 0))],
            portals: [],
            links: [SIMD2(0, 1)]
        )
        let visibility = try #require(
            graph.visibleRooms(eye: .zero, viewProjection: Self.lookingEast)
        )
        #expect(visibility.contains(room: 1))
    }

    @Test func aCameraInNoRoomTurnsCullingOff() throws {
        #expect(
            try Self.row().visibleRooms(
                eye: SIMD3(0, 1000, 0), viewProjection: Self.lookingEast
            ) == nil
        )
    }

    @Test func aPortalCrossingTheNearPlaneKeepsTheRoomVisible() throws {
        let graph = try RoomPortalGraph(
            rooms: [Self.box(at: .zero), Self.box(at: SIMD3(0, 200, 0))],
            portals: [Self.portal(0, 1, at: SIMD3(0, 100, 0), half: SIMD3(50, 20, 50))],
            links: []
        )
        let visibility = try #require(
            graph.visibleRooms(eye: SIMD3(0, 40, 0), viewProjection: Self.lookingEast)
        )
        #expect(visibility.contains(room: 1))
    }

    @Test func anInstanceBelongsOnlyToTheOneRoomItTouches() throws {
        let graph = try Self.row()
        let inside = ModelBounds(min: SIMD3(-10, -10, -10), max: SIMD3(10, 10, 10))
        let straddling = ModelBounds(min: SIMD3(90, -10, -10), max: SIMD3(110, 10, 10))
        let outside = ModelBounds(min: SIMD3(0, 500, 0), max: SIMD3(10, 510, 10))
        #expect(graph.soleRoom(touching: inside) == 0)
        #expect(graph.soleRoom(touching: straddling) == RoomPortalGraph.noRoom)
        #expect(graph.soleRoom(touching: outside) == RoomPortalGraph.noRoom)
    }

    @Test func aTurnedRoomContainsPointsInItsOwnFrame() throws {
        let turned = try #require(OrientedBox(
            transform: MatrixMath.placement(
                position: .zero, rotation: SIMD3(0, 0, .pi / 4), scale: 2
            ),
            halfExtents: SIMD3(100, 10, 10)
        ))
        #expect(turned.contains(SIMD3(100, -100, 0)))
        #expect(!turned.contains(SIMD3(100, 100, 0)))
    }

    @Test func degenerateBoxesAndBadPortalsAreDropped() throws {
        #expect(OrientedBox(transform: matrix_identity_float4x4, halfExtents: .zero) == nil)
        let graph = try RoomPortalGraph(
            rooms: [Self.box(at: .zero)],
            portals: [Self.portal(0, 5, at: .zero), Self.portal(0, 0, at: .zero)],
            links: [SIMD2(0, 9)]
        )
        #expect(graph.portals.isEmpty)
        #expect(graph.links == [[]])
    }

    @Test func theBitsetCoversRoomsPastTheFirstWord() {
        var visible = [Bool](repeating: false, count: 40)
        visible[33] = true
        let visibility = RoomVisibility(visible: visible)
        #expect(visibility.words.count == 2)
        #expect(visibility.contains(room: 33))
        #expect(!visibility.contains(room: 32))
        #expect(!visibility.contains(room: 99))
    }
}
