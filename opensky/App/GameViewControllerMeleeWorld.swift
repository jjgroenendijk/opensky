// `MeleeCombatWorld` conformance (issue #195, roadmap item 15.4): the eight
// answers the melee runtime needs from the session around it.
//
// Every one is a plain read off something that already exists — the walk
// controller's capsule pose, the streamer's resident actors, the ground
// contact's material, the actor-value runtime, the world audio engine, the
// locomotion bridge's graph. Nothing here invents an accounting of its own,
// which is what keeps the runtime's behaviour the same under test as it is in
// the app.
//
// Two answers are honest non-answers and are worth stating rather than
// papering over:
//
// * `meleeMaterial(at:)` reports the ground material under the player, not the
//   material of the body part that was struck. Actors carry no per-body-part
//   Havok material in this engine, so the alternative is inventing one.
// * `raiseCombatEvent(_:on:)` can only reach the player's graph. Item 14.6
//   attached a behavior graph to the player and to nobody else, so a stagger
//   raised on an NPC answers false and the trace records it as not staggered,
//   which is the truth rather than a silent no-op.

import AppKit
import simd

extension GameViewController: MeleeCombatWorld {
    var meleeAttacker: MeleeAttacker {
        guard let renderer else {
            return MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
        }
        return MeleeAttacker(
            key: .player,
            feet: renderer.walkController.feetPosition,
            capsule: renderer.walkController.capsule,
            facing: renderer.freeFlyCamera.yaw
        )
    }

    func meleeTargets() -> [MeleeTarget] {
        guard let streamer else { return [] }
        return streamer.residentActorEntries().compactMap { entry in
            guard let actor = entry.placedActor else { return nil }
            return MeleeTarget(key: entry.key, feet: actor.placement.position)
        }
    }

    func meleeMaterial(at position: SIMD3<Float>) -> FormID? {
        renderer?.walkController.groundMaterial
    }

    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        // Only the player has a graph to raise `blockStart` on, so only the
        // player can be blocking. An NPC that blocks back is item 15.7's.
        guard target == .player, melee.runtime?.state.isBlocking == true else { return nil }
        return .weapon
    }

    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        guard
            amount > 0,
            let runtime = actorValues.runtime,
            let holder = actorValueHolder(for: target)
        else { return false }
        runtime.damage(.health, by: amount, on: holder)
        return true
    }

    /// One landed blow reaches the scripts attached to its target (issue #375).
    ///
    /// Implemented once here and inherited by the archery and combat-loop
    /// conformances, which are the same controller: all three seams refine
    /// `ScriptHitReporting`, so a hit from any of them takes this one path into
    /// the VM. A session with no VM queues nothing and says so.
    @discardableResult
    func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        papyrus?.queueOnHit(hit) ?? 0
    }

    func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        guard
            let engine = renderer?.worldAudio, engine.isRunning,
            let sounds = (streamerCellProvider as? AudioDataProviding)?.soundStore,
            let sound = try? sounds.resolveAny(impact.sound),
            let path = sound.filePaths.first,
            let data = try? audioFileSystem?.contents(forPath: path)
        else { return }
        // A playback failure is logged by the engine and leaves the hit
        // silent; there is nothing this layer could do about it that would be
        // better than a silent hit.
        _ = try? engine.playPositional(
            fileData: data,
            request: AudioPlayRequest(
                name: path,
                category: sound.audioCategory ?? .footsteps,
                worldPosition: position
            )
        )
    }

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard let renderer else { return false }
        guard target == nil || target == .player else { return false }
        renderer.locomotion.raise(name)
        // `raisedEvents` holds the names the graph declared a home for and
        // `missingEvents` the ones it did not, so membership after the raise
        // is the graph's own answer rather than an assumption about it.
        return renderer.locomotion.status.raisedEvents.contains(name)
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        renderer?.locomotion.write(value, to: name)
    }

    /// The actor-value holder for a hit target: the player, or a resident ACHR
    /// resolved through the streamer. Nil when nothing resident answers to the
    /// key, which is a hit on an actor that was evicted mid-swing.
    private func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        if key == .player {
            return .player
        }
        guard
            let streamer,
            let entry = streamer.referenceEntry(key: key),
            let actor = entry.placedActor
        else { return nil }
        return ActorValueHolder(
            key: key,
            subject: .actor(base: actor.base),
            cell: streamer.cellLocation(of: key)
        )
    }
}
