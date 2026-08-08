// `CombatLoopWorld` conformance (issue #374, roadmap item 15.7): the twelve
// answers the combat loop needs from the session around it.
//
// Every one is a plain read off something that already exists — the walk
// controller's capsule pose, the streamer's resident actors, the world-state
// store's hostility and death components, the actor-value runtime, the melee
// runtime's guard state, the projectile and ragdoll registries, the music
// director. Nothing here invents an accounting of its own, which is what keeps
// the runtime's behaviour the same under test as it is in the app.
//
// Two answers are honest non-answers and are worth stating rather than papering
// over, both for the reason `GameViewControllerMeleeWorld.swift` gives:
//
// * `raiseCombatEvent(_:on:)` can only reach the player's graph. Item 14.6
//   attached a behavior graph to the player and to nobody else, so a reaction
//   raised on an NPC answers false and the readout records it as not played.
// * `combatBlock(of:)` can only answer for the player, because only the player
//   has a guard to raise. An NPC that blocks back needs the graph M16 brings.

import AppKit
import simd

extension GameViewController: CombatLoopWorld {
    var combatPlayer: MeleeAttacker {
        meleeAttacker
    }

    func combatActors() -> [CombatActorObservation] {
        guard let streamer else { return [] }
        return streamer.residentActorEntries().compactMap { entry in
            guard let actor = entry.placedActor else { return nil }
            return CombatActorObservation(
                key: entry.key,
                feet: actor.placement.position,
                facing: actor.placement.rotation.z,
                scale: actor.scale,
                isDead: worldState.component(ActorDeathState.self, for: entry.key)?.isDead
                    ?? false,
                name: "\(entry.key.description) (base \(actor.base))"
            )
        }
    }

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        worldState.component(ActorCombatState.self, for: key)?.hostility ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        worldState.set(
            ActorCombatState(hostility: hostility),
            for: key,
            in: streamer?.cellLocation(of: key)
        )
    }

    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        applyMeleeDamage(amount, to: key)
    }

    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        meleeBlock(of: key)
    }

    @discardableResult
    func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        playCombatReaction(clip, on: key)
    }

    var combatTransients: CombatTransientCounts {
        CombatTransientCounts(
            liveProjectiles: archery.runtime?.projectiles.live.count ?? 0,
            stuckProjectiles: archery.runtime?.projectiles.stuck.count ?? 0,
            activeRagdolls: ragdoll.runtime?.world.ragdollCount ?? 0,
            awakeBodies: streamer?.dynamicBodies.activeBodyCount ?? 0
        )
    }

    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        var removed = CombatTransientCounts()
        if let projectiles = archery.runtime?.projectiles {
            removed.liveProjectiles = projectiles.trimLive(to: limits.liveProjectiles)
            removed.stuckProjectiles = projectiles.trimStuck(to: limits.stuckProjectiles)
        }
        removed.activeRagdolls = ragdoll.runtime?.trim(to: limits.activeRagdolls) ?? 0
        removed.awakeBodies = streamer?.dynamicBodies.sleepExcessBodies(
            over: limits.awakeBodies
        ) ?? 0
        return removed
    }

    func despawnCombatTransients() {
        archery.runtime?.projectiles.despawnAll()
        ragdoll.runtime?.reset()
    }

    func setCombatMusicActive(_ active: Bool) {
        musicDirector?.setCombatActive(active)
    }
}
