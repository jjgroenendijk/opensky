// Session wiring for death and ragdoll (issue #197, roadmap item 15.6): builds
// the runtime, sweeps resident actors for zero health, feeds the runtime the
// graph events the fixed steps fired, and publishes the simulated pose into the
// render scene.
//
// AppKit stays in this controller satellite; the definition builder, the joint
// solver, the instance and the runtime are all engine types that build into
// `openskycli` and are testable without a window.
//
// The frame hook shares `Renderer.onFrame` with melee and archery, and reads the
// same `LocomotionGraphEventQueue` through its own cursor, which is what item
// 15.4 promoted the queue to allow.

import AppKit
import simd

/// Ragdoll state the controller owns. Extensions cannot add stored properties,
/// so it lives as one value on `GameViewController`.
struct RagdollBridgeState {
    /// The ragdoll runtime, built by `wireRagdoll`. Nil without a renderer, and
    /// then the panel reports itself unavailable rather than showing a
    /// convincing zero.
    var runtime: RagdollRuntime?
    /// One definition per skeleton `.nif` and scale, because every Nord in a
    /// room shares one and decoding eighteen bodies and seventeen joints per
    /// corpse would be the same work over again. The scale is part of the key
    /// rather than applied afterwards: a definition bakes it into every pivot
    /// and every inertia, so a giant and a Nord cannot share one.
    var definitions: [String: RagdollDefinition] = [:]
    /// Cache keys that produced no ragdoll, so a creature whose skeleton
    /// carries no bodies is not re-decoded once per frame.
    var unresolvableSkeletons: Set<String> = []
    /// The skeleton `.nif` reader, built from the session's own file system.
    /// Nil without game data, and then nothing can ragdoll.
    var collisionModels: NIFCollisionLibrary?
    /// Human-readable result of the last panel action.
    var lastActionText = "Nothing has died yet."
}

extension GameViewController {
    /// Builds the ragdoll runtime and starts the per-frame sweep.
    func wireRagdoll(renderer: Renderer) {
        ragdoll.collisionModels = audioFileSystem.map(NIFCollisionLibrary.init(fileSystem:))
        let runtime = RagdollRuntime()
        ragdoll.runtime = runtime
        runtime.attach(seam: self)
        // Chained onto whatever already advances the world, exactly as the
        // actor-value runtime chains: both must see the same simulated delta,
        // in wiring order, and neither may silently unhook the other. The
        // renderer gates that delta through its own `FrameSimClock`, so a
        // menu-paused frame delivers zero and a corpse stops mid-fall with the
        // rest of the world.
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self, weak renderer] delta in
            advanceWorld?(delta)
            self?.advanceRagdoll(renderer: renderer, delta: delta)
        }
        // The pose reaches the scene on the drawn frame rather than the
        // simulated one, so a paused corpse is still drawn where it was rather
        // than snapping back to its animated pose.
        renderer.onFrame.add { [weak self, weak renderer] _ in
            self?.publishRagdollPoses(renderer: renderer)
        }
    }

    /// One frame of death and ragdoll: zero-health actors die, drained graph
    /// events hand off, live ragdolls step, and the simulated poses reach the
    /// scene.
    ///
    /// The events are drained unconditionally, even outside walk mode, for the
    /// same reason melee's are: the cursor must not accumulate a backlog from a
    /// mode where nothing acts on it and then resolve all of it at once.
    func advanceRagdoll(renderer: Renderer?, delta: Float) {
        guard let renderer, let runtime = ragdoll.runtime else { return }
        let events = renderer.locomotion.graphEvents.drain(
            renderer.locomotion.ragdollEventConsumer
        )
        killZeroHealthActors(runtime: runtime)
        for key in runtime.pendingHandOffs.sorted() {
            runtime.handleGraphEvents(events, on: key)
        }
        runtime.blendDuration = renderer.locomotion.ragdollBlendDuration
            ?? HKBRigidBodyRagdollControlsModifier.vanillaBlendDuration
        runtime.advance(by: delta)
    }

    /// Every resident actor whose health has reached zero dies.
    ///
    /// A sweep rather than a hook on the damage call, because health reaches
    /// zero from more than one place — a swing, an arrow, a sidebar control,
    /// and later a script — and each of those would otherwise need its own
    /// death check. `noteZeroHealth(of:)` is idempotent, which is what makes a
    /// sweep the cheap option rather than the sloppy one.
    private func killZeroHealthActors(runtime: RagdollRuntime) {
        guard let streamer, let values = actorValues.runtime else { return }
        for entry in streamer.residentActorEntries() {
            guard let actor = entry.placedActor else { continue }
            let holder = ActorValueHolder(
                key: entry.key,
                subject: .actor(base: actor.base),
                cell: streamer.cellLocation(of: entry.key)
            )
            guard values.hasZeroHealth(holder) else { continue }
            // The return says this call is what killed the actor, so the murder
            // is reported exactly once (issue #504). Hostility is read before
            // the death is written, because a corpse's stored hostility is
            // whatever the fight left behind. The sweep does not know who
            // emptied the health, which is why the crime layer attributes the
            // death from the actors this player struck rather than from here.
            let wasHostile = combatHostility(of: entry.key) == .hostile
            guard runtime.noteZeroHealth(of: entry.key) else { continue }
            reportPlayerMurder(of: entry.key, wasHostile: wasHostile)
        }
    }

    /// Hands every live ragdoll's pose to the render scene, keyed by the ACHR
    /// it stands for.
    ///
    /// The map is rebuilt each frame rather than mutated, so a corpse whose cell
    /// unloaded stops being drawn as a ragdoll the moment its instance is gone.
    /// An empty map costs the renderer one dictionary lookup miss per actor.
    private func publishRagdollPoses(renderer: Renderer?) {
        guard let renderer, let runtime = ragdoll.runtime else { return }
        guard !runtime.world.ragdolls.isEmpty || !renderer.scene.ragdollPoses.isEmpty else {
            return
        }
        var poses: [UInt32: [String: float4x4]] = [:]
        for entry in runtime.world.ragdolls {
            guard
                let actor = ragdollActor(for: entry.key),
                let animated = animatedPose(for: entry.key)
            else { continue }
            poses[actor.reference.rawValue] = entry.instance.blendedBoneMatrices(
                animated: animated, worldToActor: actor.actorToWorld.inverse
            )
        }
        renderer.scene.ragdollPoses = poses
    }

    /// The animated pose one actor's clip currently holds, keyed by bone name.
    /// Nil where the actor has no playback attached, which is a static actor the
    /// animation layer could not resolve a rig for.
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]? {
        guard let renderer, let playback = actorPlayback(for: key) else { return nil }
        return playback.clip.namedWorldTransforms(at: renderer.animationTime)
    }

    /// The playback object drawing one resident actor, matched by the ACHR it
    /// was built for.
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback? {
        guard
            let renderer,
            let entry = streamer?.referenceEntry(key: key),
            let actor = entry.placedActor
        else { return nil }
        return renderer.scene.animations.lazy
            .compactMap { $0 as? ActorAnimationPlayback }
            .first { $0.actor == actor.formID }
    }

    /// The ragdoll one skeleton `.nif` carries, decoded once and cached.
    ///
    /// Nil for a skeleton with no simulable bodies at all — a creature this
    /// engine has not seen, or a rig whose bodies name no bone of its own
    /// animation skeleton. The path is remembered as unresolvable so the decode
    /// is not retried every frame.
    func ragdollDefinition(for clip: ActorAnimationClip, scale: Float) -> RagdollDefinition? {
        let path = clip.skeletonMeshPath
        guard !path.isEmpty else { return nil }
        let cacheKey = "\(path)@\(scale)"
        guard !ragdoll.unresolvableSkeletons.contains(cacheKey) else { return nil }
        if let cached = ragdoll.definitions[cacheKey] {
            return cached
        }
        guard
            let library = ragdoll.collisionModels,
            let model = try? library.model(path: path),
            let definition = RagdollDefinition(
                model: model,
                boneNames: clip.skeleton.boneNames,
                bindMatrices: clip.bindWorldMatrices,
                scale: scale
            )
        else {
            ragdoll.unresolvableSkeletons.insert(cacheKey)
            return nil
        }
        ragdoll.definitions[cacheKey] = definition
        return definition
    }
}
