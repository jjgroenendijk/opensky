// The registry around the solver (issue #193): residency lifecycle, the
// resting transforms it hands to persistence, the player's shove, and the
// panel's freeze and reset controls.

@testable import opensky
import simd
import Testing

struct DynamicBodyWorldTests {
    private static let cell = CellSceneLocation.interior(FormID(0x10))
    private static let other = CellSceneLocation.exterior(CellCoordinate(x: 1, y: 2))

    private static func placement(
        key: ReferenceKey,
        at position: SIMD3<Float>
    ) -> DynamicBodyPlacement {
        let volume = DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: 10))
            ?? .radial(first: .zero, second: .zero, radius: 10)
        return DynamicBodyPlacement(
            key: key,
            reference: FormID(0x200),
            definition: DynamicBodyDefinition(volumes: [volume], mass: 20),
            originPosition: position,
            orientation: .identityRotation
        )
    }

    private static var floorWorld: DynamicStepWorld {
        DynamicStepWorld(staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()]))
    }

    @Test
    func bodiesAreOrderedByKeyWhateverOrderTheyArriveIn() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(9), at: SIMD3(0, 0, 40)),
            Self.placement(key: .generated(2), at: SIMD3(40, 0, 40)),
            Self.placement(key: .plugin(name: "skyrim.esm", objectID: 7), at: SIMD3(80, 0, 40))
        ])

        #expect(world.bodies.map(\.key) == [
            .plugin(name: "skyrim.esm", objectID: 7), .generated(2), .generated(9)
        ])
    }

    @Test
    func aCellLeavingResidencyTakesItsBodiesWithIt() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [Self.placement(key: .generated(1), at: .zero)])
        world.setCell(Self.other, placements: [Self.placement(key: .generated(2), at: .zero)])
        #expect(world.bodyCount == 2)

        world.removeCell(Self.cell)

        #expect(world.bodies.map(\.key) == [.generated(2)])
    }

    @Test
    func aBodyRebinsAcrossAnExteriorBoundaryAndFollowsOccupiedResidency() throws {
        let placing = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))
        let occupied = CellSceneLocation.exterior(CellCoordinate(x: 1, y: 0))
        var world = DynamicBodyWorld()
        world.setCell(placing, placements: [
            Self.placement(key: .generated(1), at: SIMD3(4090, 0, 100))
        ])
        world.setCell(occupied, placements: [])
        let center = try #require(world.body(for: .generated(1))?.position)
        world.applyImpulse(SIMD3(4000, 0, 0), at: center, to: .generated(1))

        world.advance(by: 0.1, world: DynamicStepWorld(staticCandidates: { _ in [] }))

        #expect(world.body(for: .generated(1))?.placingCell == placing)
        #expect(world.body(for: .generated(1))?.occupiedCell == occupied)
        #expect(world.instanceDeltas[0x200] != nil)
        let crossed = try #require(world.body(for: .generated(1))?.position.x)

        world.removeCell(placing)
        world.advance(by: 0.1, world: DynamicStepWorld(staticCandidates: { _ in [] }))

        #expect(world.body(for: .generated(1))?.position.x ?? 0 > crossed)
        world.retainBodies(occupying: [placing])
        #expect(world.bodyCount == 0)
    }

    @Test
    func aRebinnedBodyPersistsInItsPlacingCellsWorldFrame() throws {
        let placing = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))
        var world = DynamicBodyWorld()
        world.setCell(placing, placements: [
            Self.placement(key: .generated(1), at: SIMD3(4100, 0, 60))
        ])
        let wideFloor = DynamicStepWorld(staticCandidates: DynamicBodyScene.query([
            DynamicBodyScene.floor(extent: 5000)
        ]))
        for _ in 0 ..< 60 {
            world.advance(by: 1.0 / 60, world: wideFloor)
        }

        let settled = try #require(world.drainSettledTransforms().first)
        #expect(settled.placingCell == placing)
        #expect(abs(settled.transform.position.x - 4100) < 0.1)
    }

    /// A rebuild of a cell the player never left must not teleport a body that
    /// has already rolled somewhere: the live pose wins over the placed one.
    @Test
    func aRebuiltCellKeepsTheLivePoseOfABodyItAlreadyPlaced() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: SIMD3(0, 0, 200))
        ])
        world.advance(by: 0.5, world: Self.floorWorld)
        let fallen = world.body(for: .generated(1))?.position.z ?? 0
        #expect(fallen < 200)

        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: SIMD3(0, 0, 200))
        ])

        #expect(world.body(for: .generated(1))?.position.z == fallen)
    }

    @Test
    func aSettledBodyIsHandedOverOnceForPersistence() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: SIMD3(0, 0, 60))
        ])
        for _ in 0 ..< 60 {
            world.advance(by: 1.0 / 60, world: Self.floorWorld)
        }

        let drained = world.drainSettledTransforms()
        #expect(drained.count == 1)
        #expect(drained.first?.key == .generated(1))
        let resting = try? #require(drained.first?.transform.position.z)
        #expect((resting ?? 0) > 9)
        #expect((resting ?? 0) < 13)
        // Draining is destructive: a body that stays asleep is not re-reported.
        world.advance(by: 1.0 / 60, world: Self.floorWorld)
        #expect(world.drainSettledTransforms().isEmpty)
    }

    @Test
    func freezingSuspendsIntegrationWithoutLosingTheBodies() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: SIMD3(0, 0, 200))
        ])
        world.isFrozen = true

        for _ in 0 ..< 30 {
            world.advance(by: 1.0 / 60, world: Self.floorWorld)
        }

        #expect(world.bodyCount == 1)
        #expect(world.body(for: .generated(1))?.position.z == 200)
        #expect(world.statsSnapshot.isFrozen)
    }

    @Test
    func resetReturnsEveryBodyToWhereItsCellPlacedIt() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: SIMD3(0, 0, 200))
        ])
        for _ in 0 ..< 60 {
            world.advance(by: 1.0 / 60, world: Self.floorWorld)
        }
        #expect(world.body(for: .generated(1))?.position.z != 200)

        world.reset()

        #expect(world.body(for: .generated(1))?.position.z == 200)
        #expect(world.body(for: .generated(1))?.linearVelocity == .zero)
        #expect(world.activeBodyCount == 1)
    }

    @Test
    func aWalkingPlayerShovesTheClutterItWalksInto() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: SIMD3(30, 0, 11))
        ])
        let before = world.body(for: .generated(1))?.linearVelocity.x ?? 0

        world.push(
            capsule: .standard,
            feetPosition: SIMD3(10, 0, 0),
            velocity: SIMD3(300, 0, 0)
        )

        let after = try? #require(world.body(for: .generated(1))?.linearVelocity.x)
        #expect((after ?? 0) > before)
        #expect(world.body(for: .generated(1))?.isSleeping == false)
    }

    @Test
    func walkingAwayFromClutterDoesNotDragIt() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: SIMD3(30, 0, 11))
        ])

        world.push(
            capsule: .standard,
            feetPosition: SIMD3(10, 0, 0),
            velocity: SIMD3(-300, 0, 0)
        )

        #expect(world.body(for: .generated(1))?.linearVelocity == .zero)
    }

    /// A moving body's shapes are ordinary placed collision shapes, which is
    /// what lets the player capsule and the interaction ray see it.
    @Test
    func aBodyPresentsItsShapesToTheOrdinaryCollisionQuery() {
        var world = DynamicBodyWorld()
        let volume = DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: 10))
            ?? .radial(first: .zero, second: .zero, radius: 10)
        world.add(
            DynamicBodyPlacement(
                key: .generated(1),
                reference: FormID(0x333),
                definition: DynamicBodyDefinition(
                    volumes: [volume],
                    mass: 20,
                    colliderShapes: [DynamicBodyColliderShape(
                        transform: matrix_identity_float4x4,
                        geometry: .box(halfExtents: SIMD3(repeating: 10)),
                        material: nil
                    )]
                ),
                originPosition: SIMD3(0, 0, 50),
                orientation: .identityRotation
            ),
            in: Self.cell
        )

        let near = world.placedShapes(
            overlapping: ModelBounds(min: SIMD3(-20, -20, 30), max: SIMD3(20, 20, 70))
        )
        #expect(near.count == 1)
        #expect(near.first?.reference == FormID(0x333))
        let far = world.placedShapes(
            overlapping: ModelBounds(min: SIMD3(400, 400, 400), max: SIMD3(500, 500, 500))
        )
        #expect(far.isEmpty)
    }
}
