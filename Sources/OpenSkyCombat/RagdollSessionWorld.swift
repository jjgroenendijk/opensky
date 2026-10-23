// The world side of death and ragdoll: what `RagdollCoordinator` reads from and
// does to the running session. The app answers it; a test passes a fake.
// See docs/engine/ragdoll.md and docs/engine/coordinators.md.

import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

/// One resident actor, as the death sweep and the corpse search see it.
nonisolated public struct RagdollResident: Equatable, Sendable {
    public let key: ReferenceKey
    public let position: SIMD3<Float>

    public init(key: ReferenceKey, position: SIMD3<Float>) {
        self.key = key
        self.position = position
    }
}

/// What one resident actor's animation holds right now.
nonisolated public struct RagdollActorPose: Sendable {
    public let reference: FormID
    public let cell: CellSceneLocation
    public let scale: Float
    public let actorToWorld: float4x4
    /// The skeleton `.nif` that carries the ragdoll bodies.
    public let skeletonMeshPath: String
    public let skeleton: HKASkeleton
    /// Skeleton-world matrices in bone order.
    public let animatedBoneMatrices: [float4x4]

    public init(
        reference: FormID,
        cell: CellSceneLocation,
        scale: Float,
        actorToWorld: float4x4,
        skeletonMeshPath: String,
        skeleton: HKASkeleton,
        animatedBoneMatrices: [float4x4]
    ) {
        self.reference = reference
        self.cell = cell
        self.scale = scale
        self.actorToWorld = actorToWorld
        self.skeletonMeshPath = skeletonMeshPath
        self.skeleton = skeleton
        self.animatedBoneMatrices = animatedBoneMatrices
    }
}

/// What `RagdollCoordinator` reads from the running world.
public protocol RagdollSessionWorld: AnyObject {
    /// Resident actors in streaming order.
    var ragdollResidents: [RagdollResident] { get }
    /// Every resident cell. A ragdoll in any other cell stops simulating.
    var residentRagdollCells: Set<CellSceneLocation> { get }
    func hasZeroHealth(_ key: ReferenceKey) -> Bool
    /// Nil where the actor has no animation playback.
    func ragdollPose(of key: ReferenceKey) -> RagdollActorPose?
    /// The animated pose by bone name, which a ragdoll blends from.
    func animatedPose(of key: ReferenceKey) -> [String: float4x4]?
    /// Only the player has a graph. True when the graph declared the name.
    func raisePlayerGraphEvent(_ name: String) -> Bool
    var ragdollStepWorld: DynamicStepWorld { get }
    /// - Returns: how many script events were queued; 0 without a script VM.
    func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int
    /// The crosshair actor, else the resident actor nearest the player.
    var selectedRagdollActor: ReferenceKey? { get }
    /// Nil without a renderer.
    var playerFeetPosition: SIMD3<Float>? { get }
    /// Points the container menu at a corpse. False when no inventory runs.
    func searchCorpse(_ key: ReferenceKey) -> Bool
    /// The plugin cell of an actor that no loaded cell holds, or nil.
    func unloadedActorHome(of key: ReferenceKey) -> CellSceneLocation?
    /// Moves the dead actor's weapon from its hand to the ground.
    /// - Returns: the skeleton nodes the weapon hung from, to hide; empty when none dropped.
    func dropWeapon(of key: ReferenceKey) -> [String]
    /// The node a decapitation cuts off, from the race's body part data; nil when
    /// the actor has no head part.
    func severableNode(of key: ReferenceKey) -> String?
    /// The blood and gore of a cut at `node`, at the node's world `position`.
    func showDismemberment(of key: ReferenceKey, node: String, at position: SIMD3<Float>)
    /// A body a quest still needs, which the excess-dead rule keeps.
    func isCorpseKept(_ key: ReferenceKey) -> Bool
    /// Removes a body from the world for good.
    func removeCorpse(_ key: ReferenceKey)
    /// Whether zero health kills the actor now, holds the death, or starts a bleedout.
    func zeroHealthOutcome(of key: ReferenceKey, killer: ReferenceKey?) -> ZeroHealthOutcome
    /// Current health over maximum health, or nil when unknown.
    func healthFraction(of key: ReferenceKey) -> Float?
    /// The class's bleedout ratio (CK "Class"), or nil when the class is unknown.
    func bleedoutThreshold(of key: ReferenceKey) -> Float?
    /// Papyrus `SetNoBleedoutRecovery(true)` keeps the actor kneeling.
    func blocksBleedoutRecovery(of key: ReferenceKey) -> Bool
}

extension RagdollSessionWorld {
    public func unloadedActorHome(of _: ReferenceKey) -> CellSceneLocation? {
        nil
    }

    public func dropWeapon(of _: ReferenceKey) -> [String] {
        []
    }

    public func severableNode(of _: ReferenceKey) -> String? {
        nil
    }

    public func showDismemberment(of _: ReferenceKey, node _: String, at _: SIMD3<Float>) {}

    /// A world that cannot tell keeps every body.
    public func isCorpseKept(_: ReferenceKey) -> Bool {
        true
    }

    public func removeCorpse(_: ReferenceKey) {}

    /// A world that cannot tell lets every actor die.
    public func zeroHealthOutcome(
        of _: ReferenceKey,
        killer _: ReferenceKey?
    ) -> ZeroHealthOutcome {
        .dies
    }

    public func healthFraction(of _: ReferenceKey) -> Float? {
        nil
    }

    public func bleedoutThreshold(of _: ReferenceKey) -> Float? {
        nil
    }

    public func blocksBleedoutRecovery(of _: ReferenceKey) -> Bool {
        false
    }
}
