// The AI & Navigation panel shell over a fake session: the actor order, the
// selection fallback, the crosshair pick, and each action's outcome line.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
@testable import OpenSkyWorldInterface
import simd
import Testing

@MainActor
private final class FakeAINavigationWorld: AINavigationWorld {
    var isStreaming = true
    var camera: AICameraPose? = AICameraPose(position: .zero, forward: SIMD3(1, 0, 0))
    var actors: [AIActorCandidate] = []
    var shapes: [StaticCollisionShape] = []
    var placed: [FormID: ReferenceKey] = [:]
    var moveResult = NPCMoveCommandResult.started
    var hasMover = false
    var hostile: Set<ReferenceKey> = []
    private(set) var collisionQueries = 0
    private(set) var moves: [(ReferenceKey, SIMD3<Float>)] = []

    var activeMoverCount: Int {
        hasMover ? 1 : 0
    }

    func actorCandidates() -> [AIActorCandidate] {
        actors
    }

    func collisionCandidates(overlapping _: ModelBounds) -> [StaticCollisionShape] {
        collisionQueries += 1
        return shapes
    }

    func residentActor(for reference: FormID) -> ReferenceKey? {
        placed[reference]
    }

    func movementReadout(for _: ReferenceKey) -> NPCMovementReadout? {
        nil
    }

    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult {
        moves.append((actor, point))
        return moveResult
    }

    func stopActor(_: ReferenceKey) -> Bool {
        hasMover
    }

    func isHostile(_ actor: ReferenceKey) -> Bool {
        hostile.contains(actor)
    }

    func setHostile(_ isHostile: Bool, actor: ReferenceKey) {
        if isHostile {
            hostile.insert(actor)
        } else {
            hostile.remove(actor)
        }
    }
}

@MainActor
struct AINavigationCoordinatorTests {
    private static let near = ReferenceKey.plugin(name: "ai.esm", objectID: 1)
    private static let far = ReferenceKey.plugin(name: "ai.esm", objectID: 2)

    @Test func optionsAreNearestFirstAndTheSelectionFallsBackToTheNearest() {
        let options = AINavigationCore.options([
            AIActorCandidate(key: Self.far, name: "Far", feet: SIMD3(300, 0, 0), isDead: false),
            AIActorCandidate(key: Self.near, name: "Near", feet: SIMD3(0, 40, 0), isDead: true)
        ], eye: .zero)
        #expect(options.map(\.key) == [Self.near, Self.far])
        #expect(options.first?.distance == 40)

        #expect(AINavigationCore.resolve(Self.far, in: options) == Self.far)
        let gone = ReferenceKey.plugin(name: "ai.esm", objectID: 9)
        #expect(AINavigationCore.resolve(gone, in: options) == Self.near)
        #expect(AINavigationCore.resolve(nil, in: []) == nil)
        #expect(AINavigationCore.name(of: nil, in: options) == "—")
        #expect(AINavigationCore.name(of: Self.far, in: options) == "Far")
    }

    @Test func theSnapshotIsUnavailableWithoutAStreamedCell() {
        let (coordinator, world) = Self.coordinator()
        world.isStreaming = false
        #expect(coordinator.aiNavigationSnapshot == .unavailable)
    }

    @Test func selectingAndHostilityActOnTheChosenActor() {
        let (coordinator, world) = Self.coordinator()
        coordinator.selectedAIActor = Self.far
        #expect(coordinator.lastActionText == "Selected Far.")

        coordinator.selectedAIActorIsHostile = true
        #expect(world.hostile == [Self.far])
        #expect(coordinator.lastActionText == "Far is now hostile.")

        let snapshot = coordinator.aiNavigationSnapshot
        #expect(snapshot.selectedActor == Self.far)
        #expect(snapshot.selectedActorIsHostile)
        #expect(snapshot.actors.map(\.key) == [Self.near, Self.far])
    }

    @Test func theCrosshairPicksOnceForAStillCameraAndSelectsTheActorItHits() {
        let (coordinator, world) = Self.coordinator()
        world.shapes = [Self.wall(reference: 7, atX: 50)]
        world.placed = [FormID(7): Self.far]

        coordinator.selectAIActorFromCrosshair()
        #expect(coordinator.selectedAIActor == Self.far)
        #expect(coordinator.aiNavigationSnapshot.crosshairPoint?.x == 50)
        #expect(world.collisionQueries == 1)

        world.placed = [:]
        coordinator.selectAIActorFromCrosshair()
        #expect(coordinator.lastActionText.hasSuffix("under the crosshair is not an actor."))
    }

    @Test func moveAndStopReportWhatTheMoverAnswered() {
        let (coordinator, world) = Self.coordinator()
        coordinator.moveSelectedAIActorToCrosshair()
        #expect(coordinator.lastActionText == "Cannot move: the crosshair is not on anything.")

        world.camera = AICameraPose(position: SIMD3(0, 0, 1), forward: SIMD3(1, 0, 0))
        world.shapes = [Self.wall(reference: 7, atX: 50)]
        coordinator.moveSelectedAIActorToCrosshair()
        #expect(world.moves.first?.0 == Self.near)
        #expect(coordinator.lastActionText == "Move: Near is pathing to the crosshair point.")

        coordinator.stopSelectedAIActor()
        #expect(coordinator.lastActionText == "Near had no mover to stop.")
        world.hasMover = true
        coordinator.stopSelectedAIActor()
        #expect(coordinator.lastActionText == "Stopped Near where it stands.")
    }

    @Test func reevaluateNeedsARegisteredPackageStack() {
        let (coordinator, world) = Self.coordinator()
        coordinator.reevaluateSelectedAIActorPackage()
        #expect(coordinator.lastActionText == "Near has no package stack registered.")

        world.actors = []
        coordinator.reevaluateSelectedAIActorPackage()
        #expect(coordinator.lastActionText == "Cannot reevaluate: no resident actor to act on.")
    }

    private static func coordinator() -> (AINavigationCoordinator, FakeAINavigationWorld) {
        let world = FakeAINavigationWorld()
        world.actors = [
            AIActorCandidate(key: far, name: "Far", feet: SIMD3(0, 900, 0), isDead: false),
            AIActorCandidate(key: near, name: "Near", feet: SIMD3(0, 100, 0), isDead: false)
        ]
        let coordinator = AINavigationCoordinator(packages: PackageCoordinator())
        coordinator.attach(world: world)
        return (coordinator, world)
    }

    /// A triangle across the +X axis at `x`.
    private static func wall(reference: UInt32, atX x: Float) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: FormID(reference),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(
                vertices: [SIMD3(x, -100, -100), SIMD3(x, 100, -100), SIMD3(x, 0, 100)],
                indices: [0, 1, 2]
            ),
            bounds: ModelBounds(min: SIMD3(repeating: -10000), max: SIMD3(repeating: 10000))
        )
    }
}
