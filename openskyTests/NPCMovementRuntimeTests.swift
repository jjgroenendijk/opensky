// Deterministic NPC corridor following, door handoff, trigger occupancy,
// bounded recovery, sparse persistence, and crowd cap (issue #423).

@testable import opensky
import simd
import Testing

@MainActor
struct NPCMovementRuntimeTests {
    private let actor = ReferenceKey.plugin(name: "movement.esm", objectID: 1)
    private let trigger = ReferenceKey.plugin(name: "movement.esm", objectID: 2)

    @Test
    func followsDoorCorridorFiresActorTriggerAndPersistsSettlePoints() throws {
        let path = Self.path(
            waypoints: [SIMD3(0, 0, 0), SIMD3(40, 0, 0), SIMD3(100, 0, 0), SIMD3(140, 0, 0)],
            target: SIMD3(140, 0, 0),
            door: NavigationDoorCrossing(door: FormID(0xA00), waypointIndex: 1)
        )
        var runtime = NPCMovementRuntime()
        var persistence: [NPCMovementPersistence] = []
        var triggers: [TriggerTransitionEvent] = []
        var doors: [FormID] = []
        runtime.onPersist = { persistence.append($0) }
        runtime.onTriggerTransition = { triggers.append($0) }
        runtime.onDoorCrossing = { _, door in doors.append(door) }
        let started = runtime.start(Self.start(actor: actor, path: path))
        #expect(started)

        let world = Self.world(
            cellAt: { position in
                position.x < 80
                    ? .exterior(CellCoordinate(x: 0, y: 0))
                    : .interior(FormID(0x200))
            },
            triggersAt: { state in
                (12 ... 32).contains(state.feetPosition.x) ? [trigger] : []
            }
        )
        for _ in 0 ..< 30 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 0.1, world: world)
        }

        let readout = try #require(runtime.readouts().first)
        #expect(readout.state == .arrived)
        #expect(simd_distance(readout.feetPosition, path.target) <= NPCMovementRuntime
            .waypointTolerance)
        #expect(doors == [FormID(0xA00)])
        #expect(triggers.map(\.phase) == [.enter, .leave])
        #expect(triggers.allSatisfy { $0.actor == actor })
        #expect(persistence.map(\.reason) == [.cellHandoff, .arrival])
        #expect(persistence.map(\.cell) == [
            .interior(FormID(0x200)), .interior(FormID(0x200))
        ])
    }

    @Test
    func stuckMoverRepathsOnceThenGivesUpAndSaveWritesOnce() throws {
        let path = Self.path(
            waypoints: [SIMD3(0, 0, 0), SIMD3(100, 0, 0)],
            target: SIMD3(100, 0, 0)
        )
        var repaths = 0
        var persistence: [NPCMovementPersistence] = []
        var runtime = NPCMovementRuntime()
        runtime.onPersist = { persistence.append($0) }
        let started = runtime.start(Self.start(actor: actor, path: path))
        #expect(started)
        runtime.persistForSave()

        let blockingWorld = Self.world(
            repath: { _ in
                repaths += 1
                return .path(path)
            },
            collisionQuery: { _ in [Self.wall] }
        )
        for _ in 0 ..< 60 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 0.1, world: blockingWorld)
        }

        let readout = try #require(runtime.readouts().first)
        #expect(readout.state == .gaveUp)
        #expect(readout.repathCount == 1)
        #expect(repaths == 1)
        #expect(persistence.map(\.reason) == [.save, .giveUp])
    }

    @Test
    func simultaneousMoverCapRejectsOnlyTheNinthActor() {
        var runtime = NPCMovementRuntime()
        let path = Self.path(
            waypoints: [SIMD3(0, 0, 0), SIMD3(100, 0, 0)],
            target: SIMD3(100, 0, 0)
        )
        for index in 0 ..< NPCMovementRuntime.maximumSimultaneousMovers {
            let key = ReferenceKey.plugin(name: "movement.esm", objectID: UInt32(index + 1))
            let started = runtime.start(Self.start(actor: key, path: path))
            #expect(started)
        }
        let ninthStarted = runtime.start(Self.start(
            actor: .plugin(name: "movement.esm", objectID: 99),
            path: path
        ))
        #expect(!ninthStarted)
        #expect(runtime.activeMoverCount == NPCMovementRuntime.maximumSimultaneousMovers)
    }

    /// A conversation's hold: the walk stops, the actor turns on the spot, and
    /// the draw path is told about the rotation (issue #427).
    @Test
    func facingStopsTheMoverTurnsInPlaceAndPublishesTheRotation() throws {
        var runtime = NPCMovementRuntime()
        var drives: [NPCLocomotionDriveUpdate] = []
        var persistence: [NPCMovementPersistence] = []
        runtime.onDrive = { drives.append($0) }
        runtime.onPersist = { persistence.append($0) }
        let walking = runtime.start(Self.start(
            actor: actor,
            path: Self.path(waypoints: [SIMD3(200, 0, 0)], target: SIMD3(200, 0, 0))
        ))
        #expect(walking)
        runtime.advance(by: 0.1, world: Self.world())
        #expect(runtime.activeMoverCount == 1)

        runtime.face(Self.face(actor: actor, target: SIMD3(0, 200, 0)))
        #expect(runtime.activeMoverCount == 0)
        #expect(runtime.activeFacingCount == 1)
        #expect(persistence.map(\.reason).contains(.halt))
        let standing = try #require(runtime.transform(for: actor)).position

        for _ in 0 ..< 60 {
            runtime.advance(by: 1 / 60, world: Self.world())
        }
        let hold = try #require(runtime.facing(for: actor))
        #expect(hold.isSettled)
        #expect(abs(hold.yaw - hold.targetYaw) < 0.01)
        #expect(hold.targetYaw > 0)
        #expect(runtime.transform(for: actor)?.position == standing)
        #expect(runtime.readouts().count == 1)
        #expect(runtime.readouts().first?.state == .facing)
        #expect(runtime.instanceDeltas()[UInt32(1)] != nil)
        #expect(drives.suffix(10).allSatisfy { $0.intent == .still })

        let released = runtime.releaseFacing(actor)
        #expect(released)
        #expect(runtime.activeFacingCount == 0)
        #expect(persistence.last?.reason == .turn)
        // Released where it stands, still pointing where it turned to.
        #expect(runtime.transform(for: actor)?.position == standing)
        #expect(abs((runtime.readouts().first?.yaw ?? 0) - hold.targetYaw) < 0.01)
    }

    /// A walk requested during a hold takes the yaw back, so the two owners of
    /// a facing cannot both be live.
    @Test
    func walkingAgainEndsTheFacingHold() {
        var runtime = NPCMovementRuntime()
        runtime.face(Self.face(actor: actor, target: SIMD3(0, 200, 0)))
        #expect(runtime.activeFacingCount == 1)
        let started = runtime.start(Self.start(
            actor: actor,
            path: Self.path(waypoints: [SIMD3(200, 0, 0)], target: SIMD3(200, 0, 0))
        ))
        #expect(started)
        #expect(runtime.activeFacingCount == 0)
        #expect(runtime.facing(for: actor) == nil)
        #expect(runtime.activeMoverCount == 1)
    }

    private static func face(actor: ReferenceKey, target: SIMD3<Float>) -> NPCFaceStart {
        NPCFaceStart(
            actor: actor,
            formID: FormID(1),
            placement: PlacedReference.Placement(position: .zero, rotation: .zero),
            scale: 1,
            target: target
        )
    }

    private static func start(actor: ReferenceKey, path: NavigationPath) -> NPCMoveStart {
        NPCMoveStart(
            actor: actor,
            formID: FormID(1),
            placement: PlacedReference.Placement(position: .zero, rotation: .zero),
            scale: 1,
            capsule: .standard,
            configuration: .synthetic,
            path: path
        )
    }

    private static func path(
        waypoints: [SIMD3<Float>],
        target: SIMD3<Float>,
        door: NavigationDoorCrossing? = nil
    ) -> NavigationPath {
        NavigationPath(
            waypoints: waypoints,
            doorCrossings: door.map { [$0] } ?? [],
            stats: NavigationPathStats(nodesExpanded: 1, corridorTriangleCount: 1),
            corridor: [],
            cellSequences: [:],
            target: target
        )
    }

    private static func world(
        cellAt: @escaping (SIMD3<Float>) -> CellSceneLocation? = { _ in
            .exterior(CellCoordinate(x: 0, y: 0))
        },
        triggersAt: @escaping (PlayerCapsuleState) -> Set<ReferenceKey> = { _ in [] },
        repath: @escaping (NavigationPathQuery) -> NavigationPathResult = { _ in
            .miss(.disconnected)
        },
        collisionQuery: @escaping WalkController.CollisionQuery = { _ in [] }
    ) -> NPCMovementWorld {
        NPCMovementWorld(
            sampleGround: { _ in
                TerrainGroundSample(height: 0, normal: SIMD3(0, 0, 1))
            },
            collisionQuery: collisionQuery,
            repath: repath,
            cellAt: cellAt,
            triggersAt: triggersAt
        )
    }

    private static let wall = StaticCollisionShape(
        reference: FormID(0x900),
        transform: MatrixMath.translation(SIMD3(30, 0, 64)),
        geometry: .box(halfExtents: SIMD3(4, 200, 128)),
        bounds: ModelBounds(
            min: SIMD3(26, -200, -64),
            max: SIMD3(34, 200, 192)
        )
    )
}
