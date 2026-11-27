// The combat loop's world over the shared combat state. An NPC swings or shoots the
// weapon it has equipped (docs/engine/combat.md).

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
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
        CombatSteps(owner: self).applyCombatBlow(amount, to: key, blow: blow)
    }

    func combatInfluence(of key: ReferenceKey) -> ActorMagicInfluence {
        ActorReads(owner: self).combatInfluence(of: key)
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
        CombatSteps(owner: self).combatTemperament(of: key, toward: target)
    }

    /// `Assistance` is actor value 5 and `Aggression` 0 (UESP "Actor Value Indices").
    func combatAssists(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool {
        ActorReads(owner: self).combatAssists(helper, ally: ally)
    }

    static let aggressionIndex: Int32 = 0
    static let confidenceIndex: Int32 = 1
    static let moralityIndex: Int32 = 3
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

    func combatHitFacts(
        from attacker: ReferenceKey, on target: ReferenceKey, weaponStagger: Float
    ) -> HitReactionFacts {
        ActorReads(owner: self).combatHitFacts(
            from: attacker,
            on: target,
            weaponStagger: weaponStagger
        )
    }

    func noteCombatHitReaction(_ report: HitReactionReport) {
        shared.note(report)
    }

    func combatAttackDisease(of attacker: ReferenceKey) -> ReferenceKey? {
        shared.world.attackDisease(of: attacker)
    }

    func combatDiseaseResist(of target: ReferenceKey) -> Float? {
        ActorReads(owner: self).combatDiseaseResist(of: target)
    }

    @discardableResult
    func contractCombatDisease(_ disease: ReferenceKey, on target: ReferenceKey) -> Bool {
        shared.world.contractDisease(disease, on: target)
    }

    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        CombatSteps(owner: self).combatAwareness(of: observer, toward: target)
    }

    func combatHealthFraction(of key: ReferenceKey) -> Float {
        guard let health = shared.world.health(of: key) else { return 1 }
        return CombatCore.healthFraction(current: health.current, maximum: health.maximum)
    }

    func combatHealth(of key: ReferenceKey) -> Float {
        shared.world.health(of: key)?.current ?? 100
    }

    func combatDangerThreats() -> [DangerThreat] {
        CombatSteps(owner: self).combatDangerThreats()
    }

    /// The weapon in `key`'s right hand, with its tempering; unarmed without one.
    func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        ActorReads(owner: self).handWeapon(of: key, \.right) ?? .unarmed
    }

    func combatLeftWeapon(of key: ReferenceKey) -> MeleeWeaponProfile? {
        ActorReads(owner: self).combatLeftWeapon(of: key)
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
        _ key: ReferenceKey, to point: SIMD3<Float>, pace: CombatPace?
    ) -> Bool {
        shared.world.moveActor(key, to: point, pace: pace)
    }

    func turnCombatActor(_ key: ReferenceKey, toward point: SIMD3<Float>) {
        shared.world.faceActor(key, toward: point)
    }

    func lookCombatActor(_ key: ReferenceKey, at target: ReferenceKey?, seconds: Float?) {
        shared.world.lookActor(key, at: target, seconds: seconds)
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
        CombatSteps(owner: self).combatTransients
    }

    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        CombatSteps(owner: self).trimCombatTransients(to: limits)
    }

    func despawnCombatTransients() {
        CombatSteps(owner: self).despawnCombatTransients()
    }

    func setCombatMusicActive(_ active: Bool) {
        CombatSteps(owner: self).setCombatMusicActive(active)
    }

    func combatBlockSkill(of key: ReferenceKey) -> Float {
        shared.strikes.combatBlockSkill(of: key)
    }

    func startCombatKillMove(
        by actor: ReferenceKey, on target: ReferenceKey, damage: Float, action: String
    ) -> Bool {
        shared.damage.startCombatKillMove(by: actor, on: target, damage: damage, action: action)
    }
}

extension CombatLoopWorldPart {
    func combatDestructibles(within radius: Float, of center: SIMD3<Float>) -> [MeleeTarget] {
        shared.world.destructibleObjects(within: radius, of: center)
    }

    func damageCombatDestructible(_ object: ReferenceKey, amount: Float) {
        shared.world.damageDestructible(object, amount: amount)
    }

    func combatFlies(_ key: ReferenceKey) -> Bool {
        shared.world.actorFlies(key)
    }

    func combatIsChild(_ key: ReferenceKey) -> Bool {
        shared.world.actorIsChild(key)
    }

    func writeCombatActorVariable(
        _ value: BehaviorVariableValue, named name: String, on actor: ReferenceKey
    ) {
        shared.world.writeActorGraphVariable(value, named: name, on: actor)
    }

    func combatGraphIsAttackReady(_ actor: ReferenceKey) -> Bool? {
        shared.world.actorGraphVariable(named: CombatGraphNames.isAttackReady, on: actor)?.boolValue
    }

    func combatIsInKillMove(_ actor: ReferenceKey) -> Bool {
        shared.world.isInKillMove(actor)
    }

    func combatGraphIsEquipping(_ actor: ReferenceKey) -> Bool {
        shared.world.actorGraphVariable(named: CombatGraphNames.isEquipping, on: actor)?
            .boolValue ?? false
    }

    func combatReaction(toPlayerOf key: ReferenceKey) -> ActorReaction? {
        shared.world.reaction(of: key, toward: .player)
    }

    func combatReaction(of observer: ReferenceKey, toward target: ReferenceKey) -> ActorReaction? {
        shared.world.reaction(of: observer, toward: target)
    }

    func combatIsHostile(_ observer: ReferenceKey, toward target: ReferenceKey) -> Bool {
        shared.world.isHostile(observer, toward: target)
    }

    func combatAggroRadius(of key: ReferenceKey) -> AggroRadius? {
        shared.world.aggroRadius(of: key)
    }

    func sayCombatWarning(by key: ReferenceKey, to target: ReferenceKey) {
        shared.world.sayWarning(by: key, to: target)
    }

    func makeRuntime(_ data: CombatSessionData) -> CombatLoopRuntime {
        CombatSteps(owner: self).makeRuntime(data)
    }
}

extension CombatLoopWorldPart {
    func combatIsTeammate(_ key: ReferenceKey) -> Bool {
        shared.world.isPlayerTeammate(key)
    }

    /// `Morality` is actor value 3 (UESP "Actor Value Indices").
    func combatMorality(of key: ReferenceKey) -> Float {
        guard shared.usesTemperament else { return 0 }
        return shared.world.actorValues(of: key)?(Self.moralityIndex) ?? 0
    }

    func combatCrimeStanding(
        of actor: ReferenceKey, judgedBy helper: ReferenceKey
    ) -> CombatCrimeStanding {
        CombatSteps(owner: self).combatCrimeStanding(of: actor, judgedBy: helper)
    }

    func combatIsGuard(_ key: ReferenceKey) -> Bool {
        shared.world.isGuard(key)
    }

    func combatAttacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool {
        shared.world.attacksPlayerOnSightForCrimes(key)
    }
}

extension CombatLoopWorldPart {
    /// Reads the combat facts of one actor: its influence, temperament, awareness, hands, and crime
    /// standing.
    struct ActorReads {
        unowned let owner: CombatLoopWorldPart

        func combatInfluence(of key: ReferenceKey) -> ActorMagicInfluence {
            owner.shared.world.gearReads.magicInfluence(of: key)
        }

        func combatTemperament(
            of key: ReferenceKey, toward target: ReferenceKey
        ) -> CombatTemperament? {
            guard
                owner.shared.usesTemperament,
                let confidence = owner.shared.world
                    .actorValues(of: key)?(CombatLoopWorldPart.confidenceIndex)
            else { return nil }
            return CombatTemperament(
                confidence: confidence,
                modifier: CombatTemperament.modifier(
                    for: key, range: owner.shared.combatAI.confidenceModifierRange
                ),
                strengthRatio: CombatTemperament.strengthRatio(
                    level: owner.shared.world.level(of: key) ?? 1,
                    healthFraction: owner.combatHealthFraction(of: key),
                    targetLevel: owner.shared.world.level(of: target) ?? 1,
                    targetHealthFraction: owner.combatHealthFraction(of: target)
                ),
                settings: owner.shared.combatAI
            )
        }

        func combatAssists(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool {
            guard
                owner.shared.usesTemperament,
                let value = owner.shared.world
                    .actorValues(of: helper)?(CombatLoopWorldPart.assistanceIndex),
                let reaction = owner.shared.world.reaction(of: helper, toward: ally)
            else { return false }
            let aggression = owner.shared.world
                .actorValues(of: ally)?(CombatLoopWorldPart.aggressionIndex) ?? 0
            return CombatAssistance(value: value).helps(reaction, allyAggression: aggression)
        }

        func combatHitFacts(
            from attacker: ReferenceKey, on target: ReferenceKey, weaponStagger: Float
        ) -> HitReactionFacts {
            owner.shared.strikes.hitFacts(
                attacker: attacker, target: target, event: CombatGraphNames.attackStart,
                weaponStagger: weaponStagger
            )
        }

        func combatDiseaseResist(of target: ReferenceKey) -> Float? {
            DiseaseContraction.resistIndex
                .flatMap { owner.shared.world.actorValues(of: target)?($0) }
        }

        func combatAwareness(
            of observer: ReferenceKey, toward target: ReferenceKey
        ) -> CombatAwareness {
            owner.shared.world.awareness(of: observer, toward: target)
        }

        func combatLeftWeapon(of key: ReferenceKey) -> MeleeWeaponProfile? {
            handWeapon(of: key, \.left).flatMap { $0.handType.isOneHandedMelee ? $0 : nil }
        }

        func handWeapon(
            of key: ReferenceKey, _ hand: KeyPath<WornWeapons, FormID?>
        ) -> MeleeWeaponProfile? {
            guard let items = owner.shared.items else { return nil }
            let reads = owner.shared.world.gearReads
            let worn = reads.equippedItems(of: key)
            let hands = WornWeapons.resolve(
                in: worn.map(\.item),
                leftHand: reads.leftHand(of: key)
            ) {
                items.weapon($0) == nil ? nil : reads.equipment?.occupancy(of: $0)
                    .hands ?? .rightHand
            }
            guard
                let item = hands[keyPath: hand],
                let weapon = items.weapon(item) else { return nil }
            let level = worn.first { $0.item == item }?.temperLevel ?? 0
            return MeleeWeaponProfile(weapon: weapon).tempered(level: level)
        }

        func combatCrimeStanding(
            of actor: ReferenceKey, judgedBy helper: ReferenceKey
        ) -> CombatCrimeStanding {
            owner.shared.world.crimeStanding(of: actor, judgedBy: helper)
        }
    }
}

extension CombatLoopWorldPart {
    /// Applies blows, reads dangers and temperament, and trims the fight's transients.
    struct CombatSteps {
        unowned let owner: CombatLoopWorldPart
        var shared: CombatShared {
            owner.shared
        }

        @discardableResult
        func applyCombatBlow(_ amount: Float, to key: ReferenceKey, blow: CombatBlow) -> Bool {
            let damage = shared.damage
            let severs = blow.kind == .power && damage.canSever(
                handType: blow.handType,
                attacker: blow.attacker
            )
            return damage.applyHealthDamage(
                amount, to: key, attacker: blow.attacker, kind: .melee, canSever: severs,
                weaponOnHit: blow.weapon.flatMap { shared.items?.weapon($0)?.onHit } ?? 0
            )
        }

        func combatTemperament(
            of key: ReferenceKey, toward target: ReferenceKey
        ) -> CombatTemperament? {
            ActorReads(owner: owner).combatTemperament(of: key, toward: target)
        }

        func combatAwareness(
            of observer: ReferenceKey, toward target: ReferenceKey
        ) -> CombatAwareness {
            ActorReads(owner: owner).combatAwareness(of: observer, toward: target)
        }

        func combatDangerThreats() -> [DangerThreat] {
            guard
                let projectiles = shared.archery?.projectiles,
                let explosions = projectiles.explosions
            else { return [] }
            return projectiles.live.compactMap { shot in
                guard let spec = explosions.spec(itemLink: shot.profile.explosion)
                else { return nil }
                return DangerRule.threat(
                    id: shot.id, source: shot.shooter,
                    motion: (shot.position, shot.state.velocity),
                    explosion: (spec.damage, spec.radius)
                )
            }
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

        func makeRuntime(_ data: CombatSessionData) -> CombatLoopRuntime {
            let runtime = CombatLoopRuntime(settings: data.combat, world: owner)
            runtime.skillUses = data.skillUses
            runtime.staggers = data.staggers
            runtime.danger = data.danger
            runtime.friendlyFire = CombatLoopRuntime.FriendlyFire(settings: data.friendlyFire)
            runtime.combatAI = data.combatAI
            runtime.applyingGameSettings = shared.appliesCombatGameSettings
            return runtime
        }

        func combatCrimeStanding(
            of actor: ReferenceKey, judgedBy helper: ReferenceKey
        ) -> CombatCrimeStanding {
            ActorReads(owner: owner).combatCrimeStanding(of: actor, judgedBy: helper)
        }
    }
}
