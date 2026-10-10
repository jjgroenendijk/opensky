// An actor placed inside a road mesh stands on top of it. Synthetic records only.

@testable import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

struct CellSceneBuilderActorFloorTests {
    /// A road slab whose top is at z = 20, over x and y from -100 to 100.
    private static let road = StaticCollisionSet(
        location: nil,
        shapes: [StaticCollisionShape(
            reference: FormID(0x900),
            transform: MatrixMath.translation(SIMD3(0, 0, 10)),
            geometry: .box(halfExtents: SIMD3(100, 100, 10)),
            bounds: ModelBounds(min: SIMD3(-100, -100, 0), max: SIMD3(100, 100, 20))
        )],
        stats: StaticCollisionStats()
    )

    @Test func anActorInsideARoadRisesOntoIt() throws {
        let lifted = try CellSceneBuilder.standingOnFloors(
            [Self.actor(at: SIMD3(10, 10, 5))], collision: Self.road
        )
        #expect(lifted.first?.actor.placement.position == SIMD3(10, 10, 20))
    }

    @Test func anActorAboveOrBesideTheRoadKeepsItsHeight() throws {
        let actors = try [Self.actor(at: SIMD3(10, 10, 30)), Self.actor(at: SIMD3(300, 0, 5))]
        let kept = CellSceneBuilder.standingOnFloors(actors, collision: Self.road)
        let positions = kept.map(\.actor.placement.position)
        #expect(positions == [SIMD3(10, 10, 30), SIMD3(300, 0, 5)])
    }

    /// A floor far above the feet is a roof or a bridge, not the ground.
    @Test func anActorUnderABridgeStaysUnderIt() throws {
        let deep = SIMD3<Float>(10, 10, 20 - CellSceneBuilder.actorFloorReach - 10)
        let kept = try CellSceneBuilder.standingOnFloors(
            [Self.actor(at: deep)],
            collision: Self.road
        )
        #expect(kept.first?.actor.placement.position == deep)
    }

    private static func actor(at position: SIMD3<Float>) throws -> CollectedActor {
        var name = Data()
        name.appendUInt32(0x1000)
        let fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", Data(count: 24))
        let record = try PlacedActor(
            record: ESMFixture.parseRecord(ESMFixture.record("ACHR", formID: 0x2000, data: fields))
        )
        let placed = PlacedActor(
            copying: record,
            placement: PlacedReference.Placement(position: position, rotation: .zero),
            scale: 1
        )
        return CollectedActor(actor: placed, isPersistent: false)
    }
}
