// The shell of death and ragdoll: owns the runtime and the ragdoll definitions,
// sweeps resident actors for zero health, and publishes the simulated poses.
// The runtime resolves through this coordinator. See docs/engine/ragdoll.md.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyWorldState
import simd

/// Owns the ragdoll runtime and reads the world through `RagdollSessionWorld`.
public final class RagdollCoordinator {
    /// Decodes the ragdoll one skeleton `.nif` carries, at one scale.
    public typealias DefinitionLoader = (
        _ skeletonMeshPath: String, _ skeleton: HKASkeleton, _ scale: Float
    ) -> RagdollDefinition?

    /// Nil until `wire`. The panel then reports itself unavailable.
    public private(set) var runtime: RagdollRuntime?
    let world: any RagdollSessionWorld
    /// Whether the scene holds poses from this coordinator, so an empty frame clears them once.
    var hasPublishedPoses = false
    let store: WorldStateStore
    private var loadDefinition: DefinitionLoader?
    /// Keyed by path and scale: a definition bakes the scale into every pivot,
    /// so a giant and a Nord cannot share one.
    private var definitions: [String: RagdollDefinition] = [:]
    /// Keys that produced no ragdoll, so they are not decoded once per frame.
    private var unresolvableSkeletons: Set<String> = []

    public init(store: WorldStateStore, world: any RagdollSessionWorld) {
        self.store = store
        self.world = world
    }

    /// Without collision models nothing can ragdoll, but deaths still record.
    public func wire(collisionModels: NIFCollisionLibrary?) {
        wire(loadDefinition: collisionModels.map(Self.definitionLoader))
    }

    func wire(loadDefinition: DefinitionLoader?) {
        self.loadDefinition = loadDefinition
        runtime = RagdollRuntime(seam: self)
    }

    /// One frame: zero-health actors die, `events` hand off, live ragdolls step.
    /// The caller drains `events` every frame, so no backlog builds up.
    /// - Returns: a murder report for each actor that died.
    public func advance(
        events: [String], controls: RagdollGraphControls, delta: Float
    ) -> [RagdollCommand] {
        guard let runtime else { return [] }
        runtime.retainRagdolls(in: world.residentRagdollCells)
        let murders = killZeroHealthActors(runtime: runtime)
        for key in runtime.pendingHandOffs.sorted() {
            runtime.handleGraphEvents(events, on: key)
        }
        runtime.blendDuration = controls.blendDuration
            ?? HKBRigidBodyRagdollControlsModifier.vanillaBlendDuration
        runtime.motor = controls.powered.map(RagdollMotor.init)
        runtime.contactEvent = controls.contactEvent
        runtime.advance(by: delta)
        return murders
    }

    /// Rebuilt each frame, so a corpse whose cell unloaded stops being drawn as
    /// a ragdoll once its instance is gone.
    public func publishPoses() -> [RagdollCommand] {
        guard let runtime, !runtime.world.ragdolls.isEmpty || hasPublishedPoses else { return [] }
        var poses: [UInt32: [String: float4x4]] = [:]
        for entry in runtime.world.ragdolls {
            guard
                let actor = ragdollActor(for: entry.key),
                let animated = world.animatedPose(of: entry.key)
            else { continue }
            poses[actor.reference.rawValue] = entry.instance.blendedBoneMatrices(
                animated: animated, worldToActor: actor.actorToWorld.inverse
            )
        }
        hasPublishedPoses = !poses.isEmpty
        return [.publishPoses(poses)]
    }

    /// A sweep, not a hook, because health reaches zero from several places.
    /// `noteZeroHealth(of:)` is true only for the call that killed the actor,
    /// so each murder is reported once.
    private func killZeroHealthActors(runtime: RagdollRuntime) -> [RagdollCommand] {
        world.ragdollResidents.compactMap { resident in
            guard world.hasZeroHealth(resident.key), runtime.noteZeroHealth(of: resident.key)
            else { return nil }
            return .reportMurder(resident.key)
        }
    }

    func definition(for pose: RagdollActorPose) -> RagdollDefinition? {
        let path = pose.skeletonMeshPath
        guard !path.isEmpty else { return nil }
        let cacheKey = "\(path)@\(pose.scale)"
        guard !unresolvableSkeletons.contains(cacheKey) else { return nil }
        if let cached = definitions[cacheKey] {
            return cached
        }
        guard let definition = loadDefinition?(path, pose.skeleton, pose.scale) else {
            unresolvableSkeletons.insert(cacheKey)
            return nil
        }
        definitions[cacheKey] = definition
        return definition
    }

    private static func definitionLoader(_ library: NIFCollisionLibrary) -> DefinitionLoader {
        { path, skeleton, scale in
            guard
                let model = try? library.model(path: path),
                let bind = try? SkeletonPoseMath.worldMatrices(
                    skeleton: skeleton, localPoses: skeleton.referencePose
                )
            else { return nil }
            return RagdollDefinition(
                model: model, boneNames: skeleton.boneNames, bindMatrices: bind, scale: scale
            )
        }
    }
}

extension RagdollCoordinator: RagdollWorldSeam {
    public func ragdollActor(for key: ReferenceKey) -> RagdollActor? {
        guard
            let pose = world.ragdollPose(of: key),
            let definition = definition(for: pose)
        else { return nil }
        return RagdollActor(
            key: key,
            cell: pose.cell,
            reference: pose.reference,
            definition: definition,
            animatedBoneMatrices: pose.animatedBoneMatrices,
            actorToWorld: pose.actorToWorld
        )
    }

    /// Only the player has a graph, so every NPC death takes the fallback.
    @discardableResult
    public func raiseRagdollEvent(_ name: String, on key: ReferenceKey) -> Bool {
        guard key == .player else { return false }
        return world.raisePlayerGraphEvent(name)
    }

    public var ragdollStepWorld: DynamicStepWorld {
        world.ragdollStepWorld
    }

    public func writeDeathState(
        _ state: ActorDeathState,
        for key: ReferenceKey,
        in cell: CellSceneLocation
    ) {
        store.set(state, for: key, in: cell)
    }

    public func deathState(of key: ReferenceKey) -> ActorDeathState? {
        store.component(ActorDeathState.self, for: key)
    }

    @discardableResult
    public func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        world.queueActorDeathEvents(for: key, killer: killer)
    }

    public func unloadedActorHome(of key: ReferenceKey) -> CellSceneLocation? {
        world.unloadedActorHome(of: key)
    }
}
