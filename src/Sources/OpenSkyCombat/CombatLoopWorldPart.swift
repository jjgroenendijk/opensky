// The combat loop's world. An NPC's weapon is always unarmed: nothing resolves an NPC's
// equipped WEAP into a swing profile yet (docs/engine/combat.md).

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

/// What the combat loop reads and changes, over the shared combat state.
final class CombatLoopWorldPart: CombatSharedPart, CombatLoopWorld {
    var combatPlayer: MeleeAttacker {
        shared.meleeAttacker
    }

    func combatActors() -> [CombatActorObservation] {
        shared.world.residentActors()
    }

    func combatActor(key: ReferenceKey) -> CombatActorObservation? {
        shared.world.residentActor(key: key)
    }

    /// The actor the player last hurt, while it lives and stands within
    /// `enemyBarRange` of `playerFeet`. The HUD names it under the compass.
    func engagedEnemy(playerFeet: SIMD3<Float>) -> CombatActorObservation? {
        guard
            let key = shared.playerStruckTarget,
            let actor = combatActor(key: key),
            !actor.isDead,
            simd_distance(actor.feet, playerFeet) <= Self.enemyBarRange
        else { return nil }
        return actor
    }

    /// About the distance at which a fight breaks off.
    static let enemyBarRange: Float = 4096

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        shared.world.hostility(of: key)
    }

    @discardableResult
    func setCombatHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        shared.world.setHostility(hostility, on: key)
    }

    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        shared.damage.applyHealthDamage(amount, to: key, attacker: nil)
    }

    /// An NPC's blow keeps its attacker, so its death push points away from it.
    @discardableResult
    func applyCombatBlow(_ amount: Float, to key: ReferenceKey, blow: CombatBlow) -> Bool {
        let damage = shared.damage
        let severs = blow.kind == .power && damage.canSever(
            handType: blow.handType,
            attacker: blow.attacker
        )
        return damage.applyHealthDamage(
            amount, to: key, attacker: blow.attacker, kind: .melee, canSever: severs
        )
    }

    func combatInfluence(of key: ReferenceKey) -> ActorMagicInfluence {
        shared.world.gearReads.magicInfluence(of: key)
    }

    /// A package that ignores combat, a knockdown, or a kill move holds the actor out of
    /// the fight.
    func combatIgnoredByPackage(_ key: ReferenceKey) -> Bool {
        shared.world.packageIgnoresCombat(key) || shared.world.isKnockedDown(key) || shared.world
            .isInKillMove(key)
    }

    /// `Confidence` is actor value 1 (UESP "Actor Value Indices").
    func combatTemperament(
        of key: ReferenceKey, toward target: ReferenceKey
    ) -> CombatTemperament? {
        guard
            shared.usesTemperament,
            let confidence = shared.world.actorValues(of: key)?(Self.confidenceIndex)
        else { return nil }
        return CombatTemperament(
            confidence: confidence,
            modifier: CombatTemperament.modifier(
                for: key, range: shared.combatAI.confidenceModifierRange
            ),
            strengthRatio: CombatTemperament.strengthRatio(
                level: shared.world.level(of: key) ?? 1,
                healthFraction: combatHealthFraction(of: key),
                targetLevel: shared.world.level(of: target) ?? 1,
                targetHealthFraction: combatHealthFraction(of: target)
            ),
            settings: shared.combatAI
        )
    }

    /// `Assistance` is actor value 5 (UESP "Actor Value Indices").
    func combatAssists(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool {
        guard
            shared.usesTemperament,
            let value = shared.world.actorValues(of: helper)?(Self.assistanceIndex),
            let reaction = shared.world.reaction(of: helper, toward: ally)
        else { return false }
        return CombatAssistance(value: value).helps(reaction)
    }

    static let confidenceIndex: Int32 = 1
    static let assistanceIndex: Int32 = 5

    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        shared.strikes.meleeBlock(of: key)
    }

    func combatWearsShield(_ key: ReferenceKey) -> Bool {
        shared.strikes.shieldRating(of: key) != nil
    }

    /// The same blocker's term the player's swing resolves, so both directions
    /// reduce a blow through one implementation.
    func combatBlockMultiplier(of key: ReferenceKey) -> Float {
        shared.perks.blockMultiplier(of: key)
    }

    func applyCombatBlockStamina(_ damage: MeleeDamageResult, to blocker: ReferenceKey) {
        shared.strikes.applyBlockStamina(damage, to: blocker)
    }

    func combatStrike(_ blow: CombatBlow, on target: ReferenceKey) -> WeaponStrike {
        shared.strikes.strike(blow, on: target)
    }

    func applyCombatHitSpell(_ blow: CombatBlow, on target: ReferenceKey) {
        shared.perks.applyPerkHitSpell(blow, on: target)
    }

    func applyCombatSwingSpell(_ blow: CombatBlow, at target: ReferenceKey) {
        shared.perks.applyPerkSwingSpell(blow, at: target)
    }

    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        shared.world.awareness(of: observer, toward: target)
    }

    func combatHealthFraction(of key: ReferenceKey) -> Float {
        guard let health = shared.world.health(of: key) else { return 1 }
        return CombatCore.healthFraction(current: health.current, maximum: health.maximum)
    }

    func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        .unarmed
    }

    func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        shared.world.combatStyle(of: key)
    }

    var combatInInterior: Bool {
        shared.world.isInInterior
    }

    func combatCasting(of key: ReferenceKey) -> CombatCastingProfile {
        guard
            shared.allowsActorCasting,
            let facts = shared.world.castingFacts(of: key) else { return .none }
        return CombatCore.castingProfile(facts)
    }

    /// A shout takes no hand, so there is nothing to ready.
    @discardableResult
    func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        option.purpose == .shout || shared.world.beginCast(option.spell, by: key)
    }

    @discardableResult
    func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        let finished = option.purpose == .shout
            ? shared.world.shout(option.spell, by: key) : shared.world.releaseCast(by: key)
        shared.actorCastCount += finished ? 1 : 0
        return finished
    }

    func cancelCombatCast(by key: ReferenceKey) {
        shared.world.cancelCast(by: key)
    }

    @discardableResult
    func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        shared.world.moveActor(key, to: point)
    }

    @discardableResult
    func moveCombatActor(
        _ key: ReferenceKey, to point: SIMD3<Float>, gait: LocomotionGait?
    ) -> Bool {
        shared.world.moveActor(key, to: point, gait: gait)
    }

    func turnCombatActor(_ key: ReferenceKey, toward point: SIMD3<Float>) {
        shared.world.faceActor(key, toward: point)
    }

    func combatFlies(_ key: ReferenceKey) -> Bool {
        shared.world.actorFlies(key)
    }

    func stopCombatMovement(of key: ReferenceKey) {
        shared.world.stopActor(key)
    }

    func resumeCombatPackage(for key: ReferenceKey) {
        shared.world.resumePackage(for: key)
    }

    /// Single-clip playback, because NPCs carry no behavior graph.
    @discardableResult
    func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        shared.world.playReaction(clip, on: key)
    }

    var combatTransients: CombatTransientCounts {
        var counts = shared.world.bodyTransients
        counts.liveProjectiles = shared.archery?.projectiles.live.count ?? 0
        counts.stuckProjectiles = shared.archery?.projectiles.stuck.count ?? 0
        return counts
    }

    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        var removed = CombatTransientCounts()
        if let projectiles = shared.archery?.projectiles {
            removed.liveProjectiles = projectiles.trimLive(to: limits.liveProjectiles)
            removed.stuckProjectiles = projectiles.trimStuck(to: limits.stuckProjectiles)
        }
        let bodies = shared.world.trimBodyTransients(to: limits)
        removed.activeRagdolls = bodies.activeRagdolls
        removed.awakeBodies = bodies.awakeBodies
        return removed
    }

    func despawnCombatTransients() {
        shared.archery?.projectiles.despawnAll()
        shared.pendingCommands.append(.resetRagdolls)
    }

    func setCombatMusicActive(_ active: Bool) {
        shared.pendingCommands.append(.setCombatMusic(active: active))
    }

    func combatBlockSkill(of key: ReferenceKey) -> Float {
        shared.strikes.combatBlockSkill(of: key)
    }

    func startCombatKillMove(
        by actor: ReferenceKey, on target: ReferenceKey, damage: Float
    ) -> Bool {
        shared.damage.startCombatKillMove(by: actor, on: target, damage: damage)
    }
}

extension CombatLoopWorldPart {
    func combatReaction(toPlayerOf key: ReferenceKey) -> ActorReaction? {
        shared.world.reaction(of: key, toward: .player)
    }

    func makeRuntime(_ data: CombatSessionData) -> CombatLoopRuntime {
        let runtime = CombatLoopRuntime(settings: data.combat, world: self)
        runtime.skillUses = data.skillUses
        runtime.staggers = data.staggers
        runtime.friendlyFire = CombatLoopRuntime.FriendlyFire(settings: data.friendlyFire)
        runtime.combatAI = data.combatAI
        runtime.applyingGameSettings = shared.appliesCombatGameSettings
        return runtime
    }
}
