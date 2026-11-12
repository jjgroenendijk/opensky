// The calls the session makes on `CombatCoordinator` outside a frame step. Each
// forwards to the part that answers it.

public import OpenSkyActorsInterface
public import OpenSkyBehavior
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyMagicInterface
public import OpenSkyPhysics
public import OpenSkyProgressionInterface

extension CombatCoordinator {
    public var meleeAttacker: MeleeAttacker {
        shared.meleeAttacker
    }

    public var projectileShooter: ProjectileShooter {
        projectileWorld.projectileShooter
    }

    public func projectileTargets() -> [MeleeTarget] {
        projectileWorld.projectileTargets()
    }

    public func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        projectileWorld.sweepProjectile(query)
    }

    public func combatActor(key: ReferenceKey) -> CombatActorObservation? {
        loopWorld.combatActor(key: key)
    }

    public func engagedEnemy(playerFeet: SIMD3<Float>) -> CombatActorObservation? {
        loopWorld.engagedEnemy(playerFeet: playerFeet)
    }

    public func combatHostility(of key: ReferenceKey) -> ActorHostility {
        loopWorld.combatHostility(of: key)
    }

    @discardableResult
    public func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        loopWorld.raiseCombatEvent(name, on: target)
    }

    public func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        loopWorld.writeCombatVariable(value, named: name)
    }

    @discardableResult
    public func applyHealthDamage(
        _ amount: Float,
        to target: ReferenceKey,
        attacker: ReferenceKey?,
        canSever: Bool
    ) -> Bool {
        shared.damage.applyHealthDamage(amount, to: target, attacker: attacker, canSever: canSever)
    }

    @discardableResult
    public func applyFall(height: Float, speed: Float, to actor: ReferenceKey) -> Float {
        shared.damage.applyFall(height: height, speed: speed, to: actor)
    }

    @discardableResult
    public func forceKnockBack(_ target: ReferenceKey, damage: Float) -> HitKnock? {
        shared.damage.forceKnockBack(target, damage: damage)
    }

    public var impulses: ImpulseRuntime? {
        shared.explosions.impulses
    }

    public func adjustingForDifficulty(_ use: SkillUseEvent) -> SkillUseEvent {
        shared.damage.adjustingForDifficulty(use)
    }

    @discardableResult
    public func notePlayerSneaking(_ isSneaking: Bool) -> SpellHitReport? {
        shared.perks.notePlayerSneaking(isSneaking)
    }

    public func perkGraphFlagChanges() -> [String: Bool] {
        shared.perks.perkGraphFlagChanges()
    }

    /// The first weapon the player has equipped, or nil when unarmed.
    public func playerWeapon() -> Weapon? {
        shared.gear.playerWeapon()
    }

    public var bowZoomTimeScale: Float {
        shared.gear.bowZoomTimeScale
    }
}
