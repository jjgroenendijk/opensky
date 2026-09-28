// `CombatLoopWorld` conformance (issues #374 and #424, roadmap items 15.7 and
// 16.7): the answers the combat loop needs from the session around it.
//
// Every one is a plain read off something that already exists — the walk
// controller's capsule pose, the streamer's resident actors, the world-state
// store's hostility and death components, the actor-value runtime, the melee
// runtime's guard state, the projectile and ragdoll registries, the music
// director. Nothing here invents an accounting of its own, which is what keeps
// the runtime's behaviour the same under test as it is in the app.
//
// Item 16.7 paid one of the two debts this file used to record.
// `combatBlock(of:)` now answers for every actor: an NPC's guard is its combat
// behavior machine's `blocking` phase rather than a graph state, so a blocked
// hit resolves through the same pinned 15.4 formula in both directions.
//
// The other debt stands and is worth restating rather than papering over:
// `raiseCombatEvent(_:on:)` can only reach the player's graph. Item 14.6
// attached a behavior graph to the player and to nobody else, so a reaction
// raised on an NPC answers false and the readout records it as not played.
// NPC reactions go through `playCombatClip(_:on:)` instead, which is single-clip
// playback and says so.

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
            let moved = streamer.npcTransform(for: entry.key)
                ?? worldState.component(ReferenceTransformOverride.self, for: entry.key)
            return CombatActorObservation(
                key: entry.key,
                feet: moved?.position ?? actor.placement.position,
                facing: moved?.rotation.z ?? actor.placement.rotation.z,
                scale: actor.scale,
                isDead: worldState.component(ActorDeathState.self, for: entry.key)?.isDead
                    ?? false,
                name: "\(entry.key.description) (base \(actor.base))"
            )
        }
    }

    /// The derived answer (issue #503), falling back to the stored override
    /// alone when there is no faction runtime — which is every synthetic scene,
    /// and every session started without game data.
    ///
    /// The override is not consulted here: it is the first term of the
    /// derivation itself (`HostilityDerivation`), so consulting it twice would
    /// be two places that could disagree about precedence.
    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        if let decision = derivedHostilityDecision(of: key) {
            return decision.hostility
        }
        return worldState.component(ActorCombatState.self, for: key)?.hostility ?? .neutral
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

    /// The same blocker's term the player's own swing path resolves, so a blow
    /// from an NPC and a blow from the player are reduced by one implementation
    /// (issues #472 and #497).
    func combatBlockMultiplier(of key: ReferenceKey) -> Float {
        meleeBlockMultiplier(of: key)
    }

    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        guard let runtime = perception.runtime else { return .unaware }
        let pair = runtime.state(observer: observer, target: target)
        return CombatAwareness(state: pair.state, lastKnownPosition: pair.lastKnownPosition)
    }

    func combatHealthFraction(of key: ReferenceKey) -> Float {
        guard
            let runtime = actorValues.runtime,
            let holder = actorValueHolder(for: key)
        else { return 1 }
        let maximum = runtime.maximums(of: holder).health
        guard maximum > 0 else { return 1 }
        return min(1, max(0, runtime.current(of: holder).health / maximum))
    }

    func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        // Unarmed for every actor, and stated rather than hidden: nothing in
        // this engine resolves an NPC's equipped WEAP into a swing profile yet.
        // Item 15.5 equips the *player* from the inventory layer, and an NPC's
        // equipment is resolved for drawing only (`ActorVisualResolutionEquipment`).
        // Reporting the model's sword as a swing profile would be inventing a
        // damage number from a mesh. Listed in docs/engine/combat.md.
        .unarmed
    }

    @discardableResult
    func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        streamer?.moveActor(key, to: point) == .started
    }

    func stopCombatMovement(of key: ReferenceKey) {
        streamer?.stopActor(key)
    }

    func resumeCombatPackage(for key: ReferenceKey) {
        resumePackage(for: key)
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
