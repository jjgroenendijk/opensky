// `CombatCoordinator` as the combat loop's world. An NPC's weapon is always
// unarmed: nothing resolves an NPC's equipped WEAP into a swing profile yet
// (docs/engine/combat.md).

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension CombatCoordinator: CombatLoopWorld {
    public var combatPlayer: MeleeAttacker {
        meleeAttacker
    }

    public func combatActors() -> [CombatActorObservation] {
        world?.residentActors() ?? []
    }

    public func combatHostility(of key: ReferenceKey) -> ActorHostility {
        world?.hostility(of: key) ?? .neutral
    }

    @discardableResult
    public func setCombatHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        world?.setHostility(hostility, on: key) ?? false
    }

    @discardableResult
    public func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        applyMeleeDamage(amount, to: key)
    }

    public func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        meleeBlock(of: key)
    }

    /// The same blocker's term the player's swing resolves, so both directions
    /// reduce a blow through one implementation.
    public func combatBlockMultiplier(of key: ReferenceKey) -> Float {
        meleeBlockMultiplier(of: key)
    }

    public func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        world?.awareness(of: observer, toward: target) ?? .unaware
    }

    public func combatHealthFraction(of key: ReferenceKey) -> Float {
        guard let health = world?.health(of: key) else { return 1 }
        return CombatCore.healthFraction(current: health.current, maximum: health.maximum)
    }

    public func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        .unarmed
    }

    public func combatCasting(of key: ReferenceKey) -> CombatCastingProfile {
        guard allowsActorCasting, let facts = world?.castingFacts(of: key) else { return .none }
        return CombatCore.castingProfile(facts)
    }

    @discardableResult
    public func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        world?.beginCast(option.spell, by: key) ?? false
    }

    @discardableResult
    public func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        let finished = world?.releaseCast(by: key) ?? false
        actorCastCount += finished ? 1 : 0
        return finished
    }

    public func cancelCombatCast(by key: ReferenceKey) {
        world?.cancelCast(by: key)
    }

    @discardableResult
    public func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        world?.moveActor(key, to: point) ?? false
    }

    public func stopCombatMovement(of key: ReferenceKey) {
        world?.stopActor(key)
    }

    public func resumeCombatPackage(for key: ReferenceKey) {
        world?.resumePackage(for: key)
    }

    /// Single-clip playback, because NPCs carry no behavior graph.
    @discardableResult
    public func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        world?.playReaction(clip, on: key) ?? false
    }

    public var combatTransients: CombatTransientCounts {
        var counts = world?.bodyTransients ?? .none
        counts.liveProjectiles = archery?.projectiles.live.count ?? 0
        counts.stuckProjectiles = archery?.projectiles.stuck.count ?? 0
        return counts
    }

    @discardableResult
    public func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        var removed = CombatTransientCounts()
        if let projectiles = archery?.projectiles {
            removed.liveProjectiles = projectiles.trimLive(to: limits.liveProjectiles)
            removed.stuckProjectiles = projectiles.trimStuck(to: limits.stuckProjectiles)
        }
        let bodies = world?.trimBodyTransients(to: limits) ?? .none
        removed.activeRagdolls = bodies.activeRagdolls
        removed.awakeBodies = bodies.awakeBodies
        return removed
    }

    public func despawnCombatTransients() {
        archery?.projectiles.despawnAll()
        world?.resetRagdolls()
    }

    public func setCombatMusicActive(_ active: Bool) {
        world?.setCombatMusicActive(active)
    }
}
