// Session wiring for the combat loop (issue #374, roadmap item 15.7): builds the
// runtime over the provider's combat GMSTs, advances it on the same paused-aware
// world delta everything else takes, and holds the reaction clips the dev target
// plays.
//
// AppKit stays in this controller satellite; the hostility component, the derived
// combat state, the attack clock, the transient caps and the readout lines are all
// engine types that build into `openskycli` and are testable without a window.
//
// Ordering, which matters here more than usual: the loop is advanced *after*
// melee, archery and the ragdolls, because it reads what those three did this
// frame — who was hit, what is in the air, which corpses are simulating — and a
// loop that ran first would be one frame behind the fight it is describing.

import AppKit
import simd

/// Combat-loop state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct CombatBridgeState {
    /// The loop runtime, built by `wireCombat` when the provider can supply
    /// combat settings. Nil without game data, and then the panel reports
    /// itself unavailable rather than showing a convincing zero.
    var runtime: CombatLoopRuntime?
    /// Reaction clips, decoded once per skeleton and kind. A room of Nords
    /// shares one, so the cache key is the skeleton path and the clip rather
    /// than the actor.
    var clips: [String: ActorAnimationClip] = [:]
    /// Cache keys that produced no clip, so a rig whose animation is missing is
    /// not re-decoded once per attack.
    var unresolvableClips: Set<String> = []
}

extension GameViewController {
    /// Builds the combat loop over the provider's combat GMSTs.
    ///
    /// A provider with no combat settings — every synthetic scene — leaves the
    /// runtime nil, exactly as it leaves the melee runtime nil, and then no
    /// fight can start rather than one starting with invented numbers.
    func wireCombat(provider: any CellSceneProvider, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.combatSettings else {
            return
        }
        let runtime = CombatLoopRuntime(settings: settings)
        combat.runtime = runtime
        runtime.attach(world: self)
        // Chained onto whatever already advances the world, exactly as the
        // actor-value runtime and the ragdolls chain: all of them must see the
        // same simulated delta, in wiring order, and none may silently unhook
        // another. The renderer gates that delta through its own `FrameSimClock`,
        // so a menu-paused frame delivers zero and a fight stops with the rest of
        // the world.
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advanceWorld?(delta)
            self?.combat.runtime?.advance(by: delta)
        }
    }

    /// Feeds the loop what one frame of melee landed: every target the player's
    /// swing connected with becomes hostile, and the dev target's own attack is
    /// interrupted.
    func noteCombatHits(_ records: [MeleeHitRecord]) {
        guard !records.isEmpty, let runtime = combat.runtime else { return }
        runtime.notePlayerHits(records.map(\.target))
    }

    /// The same, for a projectile that struck an actor.
    ///
    /// Filtered on the trace's own `provokes` rather than on "hit an actor"
    /// (issue #471): every arrow provokes, and a spell only when its effects
    /// are hostile, so healing a follower at range does not start a fight with
    /// them.
    func noteCombatProjectileHits(_ traces: [ProjectileTrace]) {
        guard let runtime = combat.runtime else { return }
        let struck = traces.filter(\.provokes).compactMap(\.target)
        guard !struck.isEmpty else { return }
        runtime.notePlayerHits(struck)
    }

    /// Plays one reaction clip on a resident actor, decoding it the first time
    /// that skeleton needs it.
    ///
    /// - Returns: false when the actor has no playback attached or its rig
    ///   carries no such animation, which the readout reports rather than
    ///   claiming a reaction the player cannot see.
    @discardableResult
    func playCombatReaction(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        guard
            let renderer,
            let playback = actorPlayback(for: key),
            let loaded = combatClip(clip, skeletonMeshPath: playback.clip.skeletonMeshPath)
        else { return false }
        playback.play(
            loaded,
            startingAt: renderer.animationTime,
            forSeconds: ActorAnimationClipLoader.holdSeconds(for: clip)
        )
        return true
    }

    /// One decoded reaction clip, cached per skeleton and kind.
    private func combatClip(
        _ clip: CombatActorClip,
        skeletonMeshPath: String
    ) -> ActorAnimationClip? {
        let cacheKey = "\(skeletonMeshPath)#\(clip.rawValue)"
        guard !combat.unresolvableClips.contains(cacheKey) else { return nil }
        if let cached = combat.clips[cacheKey] {
            return cached
        }
        guard
            let fileSystem = audioFileSystem,
            let loaded = try? ActorAnimationClipLoader.clip(
                skeletonMeshPath: skeletonMeshPath,
                animationPath: ActorAnimationClipLoader.animationPath(for: clip),
                readHKX: { path in try HKXFile(data: fileSystem.contents(forPath: path)) }
            )
        else {
            combat.unresolvableClips.insert(cacheKey)
            return nil
        }
        combat.clips[cacheKey] = loaded
        return loaded
    }
}
