// The M16 gate's session (issue #203): one guard, one two-cell navmesh with a
// door between them, and the four real runtimes the milestone built, wired
// together in the order the app advances them.
//
// The gate statement is a chain, so the harness is one too. The package runtime
// picks a package off the clock; the procedure it selects names a destination;
// the navigation graph turns that destination into a corridor; the movement
// runtime walks the corridor and crosses the door; the perception pass reads
// where the guard ended up and decides whether it can see the player; the combat
// loop reads that awareness and fights, breaks off, searches, and hands the
// guard back to its package. Each link is the shipping type, not a stand-in, so
// a break anywhere along it fails the gate rather than being papered over by a
// fake in the middle.
//
// The one deliberate simplification against the app: there is no `CellStreamer`
// and no renderer. Residency, cell building and drawing are M2 and M3 concerns
// that `CellStreamerTests` and `NavigationRuntimeTests` already cover, and
// carrying them here would make the gate a streaming test with an AI in it.
// What is real is every runtime M16 added and every seam between them.
//
// Everything is invented. No packfile bytes, no extracted records, no positions
// from the install (AGENTS.md "Legal & IP boundary"). The vanilla half of the
// gate is `M16AcceptanceRealDataTests`, which is env-gated.

import Foundation
@testable import opensky
import simd

@MainActor
final class M16AcceptanceChain {
    // MARK: - The world

    static let guardKey = ReferenceKey.plugin(name: "m16.esm", objectID: 0x10)
    static let guardBase = FormID(0x600)
    static let marketCell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))
    static let innCell = CellSceneLocation.interior(FormID(0x200))
    /// The market door, and its pair inside the inn.
    static let marketDoor = FormID(0xA00)
    static let innDoor = FormID(0xB00)
    /// Where the two navmesh sheets sit on +X. The door stands between them.
    static let marketOrigin: Float = 0
    static let innOrigin: Float = 400
    static let marketDoorPosition = SIMD3<Float>(180, 20, 0)
    static let innDoorPosition = SIMD3<Float>(420, 20, 0)
    /// Where the guard starts its day, and where its evening package sends it.
    static let postPosition = SIMD3<Float>(20, 20, 0)
    static let bedPosition = SIMD3<Float>(560, 20, 0)

    // MARK: - The runtimes

    var navigation = RuntimeNavigationGraph()
    var movement = NPCMovementRuntime()
    var packages: ActorPackageRuntime
    let perception: PerceptionRuntime
    let combat: CombatLoopRuntime

    /// The game clock the package schedule is read against. Advanced by the
    /// route, never by wall time.
    var clock = GameClock(hour: 8)
    /// Where the player is standing and how loudly it is moving, which is the
    /// whole of what the perception pass is told about it.
    var playerFeet = SIMD3<Float>(60, 20, 0)
    var playerGait: LocomotionGait? = .walk
    /// Segments this predicate answers true for are blocked, which is how the
    /// route breaks line of sight without building a wall.
    var sightBlocked: (SIMD3<Float>, SIMD3<Float>) -> Bool = { _, _ in false }

    /// Where the guard is standing. Written by the mover, read by perception and
    /// by combat, which is exactly the direction the app's data flows.
    var guardFeet = postPosition
    var guardIsDead = false
    var guardHealth: Float = 1
    /// Stored regard, written through the combat world seam exactly as the app
    /// writes it through `WorldStateStore`.
    var hostilityState: [ReferenceKey: ActorHostility] = [:]

    /// Everything the route wants to assert on afterwards, recorded as it
    /// happens rather than reconstructed from an end state.
    var doorCrossings: [FormID] = []
    var settlePoints: [NPCMovementPersistence] = []
    var packageSelections: [PackageActorReadout] = []
    var packageResumeLog: [ReferenceKey] = []
    var visitedPhases: Set<CombatBehaviorPhase> = []

    init() throws {
        let store = try M16AcceptanceFixture.packageStore()
        packages = ActorPackageRuntime(store: store)
        perception = PerceptionRuntime(settings: .synthetic)
        combat = CombatLoopRuntime(settings: .synthetic)
        combat.behaviorSettings = .quick

        try installNavigation()
        try packages.register(actor: Self.guardKey, base: Self.guardBase)
        packages.onSelectionChanged = { [weak self] readout in
            self?.packageSelections.append(readout)
        }
        movement.onDoorCrossing = { [weak self] _, door in
            self?.doorCrossings.append(door)
        }
        movement.onPersist = { [weak self] persistence in
            self?.settlePoints.append(persistence)
        }
        perception.attach(world: self)
        combat.attach(world: self)
    }

    // MARK: - Driving

    /// One frame, in the order `GameViewController` advances these systems:
    /// movement first, because everything after it reads where actors ended up;
    /// then packages, which may issue the next move; then combat, which reads
    /// awareness; then perception last, which describes the world as it now is.
    func frame(dt: Float = CombatLoopRuntime.fixedStepSeconds) {
        movement.advance(by: dt, world: movementWorld())
        guardFeet = movement.readouts().first { $0.actor == Self.guardKey }?.feetPosition
            ?? guardFeet
        packages.advance(clock: clock) { _ in ConditionContext(clock: self.clock) }
        combat.advance(by: dt)
        perception.advance(by: dt)
        if let phase = combat.phase(of: Self.guardKey) {
            visitedPhases.insert(phase)
        }
    }

    /// Runs up to `frames` frames, stopping as soon as `until` holds. Returns
    /// whether it stopped early, so a route step asserts on the condition rather
    /// than on a frame count nobody can check.
    @discardableResult
    func run(frames: Int, until: () -> Bool = { false }) -> Bool {
        for _ in 0 ..< frames {
            if until() {
                return true
            }
            frame()
        }
        return until()
    }

    /// Moves the clock forward without simulating the hours in between, which is
    /// what the Runtime State time controls do.
    func setHour(_ hour: Float) {
        clock = GameClock(hour: hour)
    }

    /// Starts the guard walking to `point` through the real graph, exactly as
    /// `CellStreamer.moveActor` does.
    @discardableResult
    func moveGuard(to point: SIMD3<Float>) -> NPCMoveCommandResult {
        let result = navigation.findPath(NavigationPathQuery(
            start: guardFeet,
            target: point,
            capsuleRadius: PlayerCapsule.standard.radius
        ))
        guard case let .path(path) = result else {
            guard case let .miss(reason) = result else { return .noPath(.disconnected) }
            return .noPath(reason)
        }
        let started = movement.start(NPCMoveStart(
            actor: Self.guardKey,
            formID: FormID(0x1000),
            placement: PlacedReference.Placement(position: guardFeet, rotation: .zero),
            scale: 1,
            capsule: .standard,
            configuration: .synthetic,
            path: path
        ))
        return started ? .started : .moverCapReached
    }

    func setGuardHostile(_ hostile: Bool) {
        combat.setHostility(hostile ? .hostile : .neutral, on: Self.guardKey)
    }

    /// Takes the guard down to `fraction` of its health, which is what makes it
    /// break off rather than fight to the end.
    func woundGuard(to fraction: Float) {
        guardHealth = fraction
    }

    var packageResumes: [ReferenceKey] {
        packageResumeLog
    }

    var guardMovement: NPCMovementReadout? {
        movement.readouts().first { $0.actor == Self.guardKey }
    }

    var guardPackage: PackageActorReadout? {
        packages.readouts().first { $0.actor == Self.guardKey }
    }

    var guardDetection: DetectionPairState {
        perception.state(observer: Self.guardKey, target: .player)
    }

    // MARK: - Wiring

    private func installNavigation() throws {
        try navigation.setCell(Self.marketCell, scene: NavigationRuntimeFixture.scene(
            location: Self.marketCell,
            navmeshes: [M16AcceptanceFixture.sheet(
                id: 0x100, origin: Self.marketOrigin, door: Self.marketDoor.rawValue
            )],
            doors: [NavigationRuntimeFixture.placedDoor(
                reference: Self.marketDoor.rawValue,
                destination: Self.innDoor.rawValue,
                position: Self.marketDoorPosition
            )],
            interactions: [Self.marketDoor: NavigationRuntimeFixture.doorInteraction(
                reference: Self.marketDoor.rawValue, position: Self.marketDoorPosition
            )]
        ))
        try navigation.setCell(Self.innCell, scene: NavigationRuntimeFixture.scene(
            location: Self.innCell,
            navmeshes: [M16AcceptanceFixture.sheet(
                id: 0x200, origin: Self.innOrigin, door: Self.innDoor.rawValue
            )],
            doors: [NavigationRuntimeFixture.placedDoor(
                reference: Self.innDoor.rawValue,
                destination: Self.marketDoor.rawValue,
                position: Self.innDoorPosition
            )],
            interactions: [Self.innDoor: NavigationRuntimeFixture.doorInteraction(
                reference: Self.innDoor.rawValue, position: Self.innDoorPosition
            )]
        ))
    }

    /// The world the mover walks in: flat ground, nothing in the way, the real
    /// graph for repaths, and a cell answer that flips at the door so the
    /// hand-off the gate asserts on is produced rather than announced.
    private func movementWorld() -> NPCMovementWorld {
        NPCMovementWorld(
            sampleGround: { _ in TerrainGroundSample(height: 0, normal: SIMD3(0, 0, 1)) },
            collisionQuery: { _ in [] },
            repath: { [weak self] query in
                self?.navigation.findPath(query) ?? .miss(.disconnected)
            },
            cellAt: { position in
                position.x < Self.innOrigin ? Self.marketCell : Self.innCell
            },
            triggersAt: { _ in [] }
        )
    }
}
