// `CombatCoordinator` as the combat loop's world. An NPC's weapon is always
// unarmed: nothing resolves an NPC's equipped WEAP into a swing profile yet
// (docs/engine/combat.md).

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

extension CombatCoordinator: CombatLoopWorld {
    public var combatPlayer: MeleeAttacker {
        meleeAttacker
    }

    public func combatActors() -> [CombatActorObservation] {
        world.residentActors()
    }

    public func combatActor(key: ReferenceKey) -> CombatActorObservation? {
        world.residentActor(key: key)
    }

    /// The actor the player last hurt, while it lives and stands within
    /// `enemyBarRange` of `playerFeet`. The HUD names it under the compass.
    public func engagedEnemy(playerFeet: SIMD3<Float>) -> CombatActorObservation? {
        guard
            let key = playerStruckTarget,
            let actor = combatActor(key: key),
            !actor.isDead,
            simd_distance(actor.feet, playerFeet) <= Self.enemyBarRange
        else { return nil }
        return actor
    }

    /// About the distance at which a fight breaks off.
    public static let enemyBarRange: Float = 4096

    public func combatHostility(of key: ReferenceKey) -> ActorHostility {
        world.hostility(of: key)
    }

    @discardableResult
    public func setCombatHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        world.setHostility(hostility, on: key)
    }

    @discardableResult
    public func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        applyHealthDamage(amount, to: key, attacker: nil)
    }

    public func combatInfluence(of key: ReferenceKey) -> ActorMagicInfluence {
        world.magicInfluence(of: key)
    }

    public func combatIgnoredByPackage(_ key: ReferenceKey) -> Bool {
        world.packageIgnoresCombat(key)
    }

    /// `Confidence` is actor value 1 (UESP "Actor Value Indices").
    public func combatTemperament(
        of key: ReferenceKey, toward target: ReferenceKey
    ) -> CombatTemperament? {
        guard
            usesTemperament,
            let confidence = world.actorValues(of: key)?(Self.confidenceIndex)
        else { return nil }
        return CombatTemperament(
            confidence: confidence,
            modifier: CombatTemperament.modifier(for: key),
            strengthRatio: CombatTemperament.strengthRatio(
                level: world.level(of: key) ?? 1,
                healthFraction: combatHealthFraction(of: key),
                targetLevel: world.level(of: target) ?? 1,
                targetHealthFraction: combatHealthFraction(of: target)
            )
        )
    }

    /// `Assistance` is actor value 5 (UESP "Actor Value Indices").
    public func combatAssists(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool {
        guard
            usesTemperament,
            let value = world.actorValues(of: helper)?(Self.assistanceIndex),
            let reaction = world.reaction(of: helper, toward: ally)
        else { return false }
        return CombatAssistance(value: value).helps(reaction)
    }

    static let confidenceIndex: Int32 = 1
    static let assistanceIndex: Int32 = 5

    public func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        meleeBlock(of: key)
    }

    /// The same blocker's term the player's swing resolves, so both directions
    /// reduce a blow through one implementation.
    public func combatBlockMultiplier(of key: ReferenceKey) -> Float {
        meleeBlockMultiplier(of: key)
    }

    public func applyCombatBlockStamina(_ damage: MeleeDamageResult, to blocker: ReferenceKey) {
        applyBlockStamina(damage, to: blocker)
    }

    public func combatStrike(_ blow: CombatBlow, on target: ReferenceKey) -> WeaponStrike {
        strike(blow, on: target)
    }

    public func applyCombatHitSpell(_ blow: CombatBlow, on target: ReferenceKey) {
        applyPerkHitSpell(blow, on: target)
    }

    public func applyCombatSwingSpell(_ blow: CombatBlow, at target: ReferenceKey) {
        applyPerkSwingSpell(blow, at: target)
    }

    public func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        world.awareness(of: observer, toward: target)
    }

    public func combatHealthFraction(of key: ReferenceKey) -> Float {
        guard let health = world.health(of: key) else { return 1 }
        return CombatCore.healthFraction(current: health.current, maximum: health.maximum)
    }

    public func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        .unarmed
    }

    public func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        world.combatStyle(of: key)
    }

    public func combatCasting(of key: ReferenceKey) -> CombatCastingProfile {
        guard allowsActorCasting, let facts = world.castingFacts(of: key) else { return .none }
        return CombatCore.castingProfile(facts)
    }

    @discardableResult
    public func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        world.beginCast(option.spell, by: key)
    }

    @discardableResult
    public func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        let finished = world.releaseCast(by: key)
        actorCastCount += finished ? 1 : 0
        return finished
    }

    public func cancelCombatCast(by key: ReferenceKey) {
        world.cancelCast(by: key)
    }

    @discardableResult
    public func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        world.moveActor(key, to: point)
    }

    public func stopCombatMovement(of key: ReferenceKey) {
        world.stopActor(key)
    }

    public func resumeCombatPackage(for key: ReferenceKey) {
        world.resumePackage(for: key)
    }

    /// Single-clip playback, because NPCs carry no behavior graph.
    @discardableResult
    public func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        world.playReaction(clip, on: key)
    }

    public var combatTransients: CombatTransientCounts {
        var counts = world.bodyTransients
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
        let bodies = world.trimBodyTransients(to: limits)
        removed.activeRagdolls = bodies.activeRagdolls
        removed.awakeBodies = bodies.awakeBodies
        return removed
    }

    public func despawnCombatTransients() {
        archery?.projectiles.despawnAll()
        pendingCommands.append(.resetRagdolls)
    }

    public func setCombatMusicActive(_ active: Bool) {
        pendingCommands.append(.setCombatMusic(active: active))
    }
}
