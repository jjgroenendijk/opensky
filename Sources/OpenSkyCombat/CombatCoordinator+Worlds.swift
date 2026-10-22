// `CombatCoordinator` as the world of its three runtimes. Each answer reads
// another runtime it owns, a `CombatCore` rule, or one `CombatWorld` member.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyWorldState
import simd

extension CombatCoordinator: ScriptHitReporting, SkillUseReporting, SpellHitApplying,
    WeaponEnchantmentApplying
{
    @discardableResult
    public func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        world.reportScriptHit(hit)
    }

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        world.reportSkillUse(use)
    }

    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        world.applySpellHit(hit)
    }

    @discardableResult
    public func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        world.applyWeaponEnchantment(hit)
    }

    @discardableResult
    public func applyWeaponPoison(_ hit: WeaponPoisonHit) -> WeaponPoisonReport? {
        world.applyWeaponPoison(hit)
    }

    /// Only the player carries a behavior graph, so an event on an NPC
    /// answers false.
    @discardableResult
    public func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard target == nil || target == .player else { return false }
        return world.raisePlayerGraphEvent(name)
    }

    public func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        world.writePlayerGraphVariable(value, named: name)
    }
}

extension CombatCoordinator: MeleeCombatWorld {
    public var meleeAttacker: MeleeAttacker {
        world.playerAttacker ?? MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    }

    public func meleeAttackMultiplier(handType: CombatHandType) -> Float {
        guard let values = world.actorValues(of: .player) else { return 1 }
        return CombatFortifyBonus.melee(handType: handType, reading: values)
    }

    public func meleeTargets() -> [MeleeTarget] {
        world.residentActors().map { MeleeTarget(key: $0.key, feet: $0.feet) }
    }

    public func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        let isBlocking = target == .player && melee?.state.isBlocking == true
        return CombatCore.block(
            of: target,
            playerIsBlocking: isBlocking,
            playerShieldRating: isBlocking ? meleeBashSource().shieldRating : nil,
            machineBlock: target == .player ? nil : loop?.blockKind(of: target)
        )
    }

    /// The blocker's fortify term times `Mod Percent Blocked`.
    public func meleeBlockMultiplier(of target: ReferenceKey) -> Float {
        guard let values = world.actorValues(of: target) else { return 1 }
        return CombatFortifyBonus.block(reading: values)
            * world.perkMultiplier(at: CombatCore.percentBlockedEntryPoint, on: target)
    }

    public func meleeStrike(_ blow: CombatBlow, on target: ReferenceKey) -> WeaponStrike {
        let strike = strike(blow, on: target)
        reportSneakAttack(strike, ranged: false)
        return strike
    }

    public func meleeResolvedWeapon(_ weapon: FormID?) -> ResolvedFormID? {
        items?.conditionSubject(of: weapon)?.id
    }

    public func meleeSweeps(_ blow: CombatBlow) -> Bool {
        perkSweeps(blow)
    }

    public func applyMeleeHitSpell(_ blow: CombatBlow, on target: ReferenceKey) {
        applyPerkHitSpell(blow, on: target)
    }

    /// `Mod Power Attack Stamina`, with the swung weapon bound.
    public func meleePowerAttackStamina(_ cost: Float, weapon: FormID?) -> Float {
        perkValue(
            cost,
            at: .modPowerAttackStamina,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player)
                .binding(.weapon, to: items?.conditionSubject(of: weapon))
        )
    }

    /// The player's own swing: the melee runtime only ever swings for the player.
    @discardableResult
    public func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        let standingPower = melee?.strikeKind == .power && melee?.powerDirection == .inPlace
        let severs = standingPower && melee.map { canSever(handType: $0.weapon.handType) } == true
        return applyHealthDamage(
            amount, to: target, attacker: meleeAttacker.key, kind: .melee, canSever: severs
        )
    }

    /// Every weapon, arrow, and explosion hit passes here, so difficulty scales
    /// health damage at one point. A nil attacker is never the player. An ethereal
    /// actor deals and takes none.
    @discardableResult
    public func applyHealthDamage(
        _ amount: Float,
        to target: ReferenceKey,
        attacker: ReferenceKey?,
        kind: CombatHitKind = .other,
        canSever: Bool = false
    ) -> Bool {
        guard amount > 0, !isEthereal(target), !(attacker.map(isEthereal) ?? false)
        else { return false }
        let scaled = DifficultyDamage.scaled(
            amount, attackerIsPlayer: attacker == .player, targetIsPlayer: target == .player,
            multipliers: difficultyMultipliers
        )
        let landed = world.damageHealth(by: scaled, of: target)
        if landed, attacker == .player, target != .player {
            playerStruckTarget = target
        }
        if landed {
            let hit = CombatHitRecord(
                damage: scaled, kind: kind, attacker: attacker, canSever: canSever
            )
            world.recordHealthHit(hit, on: target)
            if kind != .other {
                pendingCommands.append(.drewBlood(hit, target: target))
            }
        }
        return landed
    }

    /// UESP "Skyrim:One-handed" and "Skyrim:Two-handed": Savage Strike and Devastating
    /// Blow let a standing power attack decapitate. Maces and warhammers count, as in
    /// the unpatched game.
    func canSever(handType: CombatHandType, attacker: ReferenceKey = .player) -> Bool {
        switch handType {
        case .sword, .dagger, .axe, .mace:
            world.ownsPerk(editorID: "SavageStrike", on: attacker)
        case .greatsword, .battleaxe:
            world.ownsPerk(editorID: "DevastatingBlow", on: attacker)
        default:
            false
        }
    }

    private func isEthereal(_ key: ReferenceKey) -> Bool {
        world.magicInfluence(of: key).isEthereal
    }

    public func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        pendingCommands.append(.playImpact(impact, at: position))
    }

    public func showDefaultBlood(on target: ReferenceKey, at position: SIMD3<Float>, melee: Bool) {
        pendingCommands.append(.showDefaultBlood(on: target, at: position, melee: melee))
    }

    public func impactMaterial(of target: ReferenceKey) -> FormID? {
        world.impactMaterial(of: target)
    }
}

extension CombatCoordinator: ProjectileWorld {
    public var projectileShooter: ProjectileShooter {
        world.playerShooter ?? ProjectileShooter(
            key: .player, origin: SIMD3(), aim: SIMD3(1, 0, 0),
            isFirstPerson: true, location: nil
        )
    }

    public func projectileTargets() -> [MeleeTarget] {
        meleeTargets()
    }

    public func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        world.sweep(query)
    }

    @discardableResult
    public func applyProjectileDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        let shooter = projectileShooter.key
        guard !deflectsArrow(target) else { return false }
        let blow = CombatBlow(
            attacker: shooter, weapon: playerWeapon()?.formID, handType: .bow, baseDamage: amount
        )
        let strike = strike(blow, on: target)
        reportSneakAttack(strike, ranged: true)
        let landed = applyHealthDamage(
            strike.damage(base: amount), to: target, attacker: shooter, kind: .ranged
        )
        if landed {
            applyPerkHitSpell(blow, on: target)
        }
        return landed
    }

    public func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        pendingCommands.append(.playImpact(impact, at: position))
        pendingCommands.append(.detectionEvent(owner: .player, at: position))
    }

    /// False on an empty quiver, which is ordinary play: the shot does not happen.
    @discardableResult
    public func consumeArrow(_ ammunition: FormID) -> Bool {
        world.removeOneFromPlayer(ammunition)
    }

    /// A stuck arrow is a spawned AMMO model at the impact point. It does not
    /// follow the bone of the actor it hit.
    @discardableResult
    public func spawnStuckProjectile(_ arrow: StuckProjectile) -> ReferenceKey? {
        let spawn = ReferenceSpawnState(
            base: arrow.base,
            location: arrow.location,
            placement: PlacedReference.Placement(
                position: arrow.position,
                rotation: arrow.rotation
            ),
            count: 1
        )
        guard let key = world.spawn(spawn, in: arrow.location) else { return nil }
        stuckKeys.insert(key)
        return key
    }

    public func removeStuckProjectile(_ key: ReferenceKey) {
        guard stuckKeys.remove(key) != nil else { return }
        pendingCommands.append(.removeReference(key))
    }

    public func residentProjectileCells() -> Set<CellSceneLocation> {
        world.residentCells()
    }

    @discardableResult
    public func raiseArcheryEvent(_ name: String) -> Bool {
        raiseCombatEvent(name, on: nil)
    }

    public func writeArcheryVariable(_ value: BehaviorVariableValue, named name: String) {
        writeCombatVariable(value, named: name)
    }

    @discardableResult
    public func giveRecoveredArrow(_ ammunition: FormID, to target: ReferenceKey) -> Bool {
        world.addItem(ammunition, count: 1, to: target)
    }

    public func showArcheryNotice(_ text: String) {
        pendingCommands.append(.showNotification(text))
    }

    /// Hunter's Discipline doubles the chance through this entry point.
    public func arrowRecoveryMultiplier(of shooter: ReferenceKey) -> Float {
        world.perkMultiplier(at: .modRecoverArrowChance, on: shooter)
    }
}
