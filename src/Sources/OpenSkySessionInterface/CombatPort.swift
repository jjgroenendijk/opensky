public import OpenSkyActorsInterface
public import OpenSkyBehavior
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
public import OpenSkyPhysics
public import OpenSkyProgressionInterface

/// What the world adapters use of `CombatCoordinator`.
public protocol CombatPort: AnyObject {
    associatedtype ArcheryRuntime: ArcheryRuntimePort
    associatedtype CombatLoopRuntime: CombatLoopRuntimePort
    associatedtype ExplosionRuntime: ExplosionRuntimePort
    associatedtype ImpulseRuntime: ImpulseRuntimePort
    associatedtype MeleeCombatRuntime: MeleeCombatRuntimePort
    func adjustingForDifficulty(_ use: SkillUseEvent) -> SkillUseEvent
    func advanceLoop(by delta: Float) -> [CombatCommand]
    @discardableResult func applyFall(height: Float, speed: Float, to actor: ReferenceKey) -> Float
    @discardableResult func applyHealthDamage(
        _ amount: Float,
        to target: ReferenceKey,
        attacker: ReferenceKey?
    ) -> Bool
    var archery: ArcheryRuntime? { get }
    func combatActor(key: ReferenceKey) -> CombatActorObservation?
    var combatLoopSnapshot: CombatLoopSnapshot { get }
    var difficulty: DifficultyLevel { get set }
    func engagedEnemy(playerFeet: SIMD3<Float>) -> CombatActorObservation?
    var explosions: ExplosionRuntime { get }
    @discardableResult func forceKnockBack(_ target: ReferenceKey, damage: Float) -> HitKnock?
    var impulses: ImpulseRuntime? { get }
    var isTimeSlowed: Bool { get set }
    var isWeaponDrawn: Bool { get }
    var items: ItemDefinitionStore? { get }
    var lastFall: FallOutcome? { get }
    var loop: CombatLoopRuntime? { get }
    var melee: MeleeCombatRuntime? { get }
    var meleeAttacker: MeleeAttacker { get }
    var meleeCombatSnapshot: MeleeCombatSnapshot { get }
    @discardableResult func notePlayerSneaking(_ isSneaking: Bool) -> SpellHitReport?
    var playerActionFacts: ActorActionFacts? { get }
    func playerWeapon() -> Weapon?
    func prepareForPersistence() -> [CombatCommand]
    var projectileShooter: ProjectileShooter { get }
    func projectileTargets() -> [MeleeTarget]
    @discardableResult func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool
    func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit?
    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String)
    func advanceArchery(
        events: [String],
        intent: ArcheryIntent,
        isPlayerControlled: Bool,
        delta: Float
    ) -> [CombatCommand]
    func perkGraphFlagChanges() -> [String: Bool]

    func advanceMelee(
        events: [String],
        intent: MeleeIntent,
        isPlayerControlled: Bool
    ) -> [CombatCommand]
    var bowZoomTimeScale: Float { get }
    func combatHostility(of key: ReferenceKey) -> ActorHostility
}

extension CombatPort {
    /// The projectiles in flight; none before archery starts.
    public var liveProjectiles: [LiveProjectile] {
        archery?.projectiles.live ?? []
    }

    public var projectileImpacts: ArcheryRuntime.ProjectileRuntime.MeleeImpactResolver? {
        archery?.projectiles.impacts
    }

    @discardableResult public func removeArrows(stuckIn host: FormID) -> Int {
        archery?.projectiles.removeArrows(stuckIn: host) ?? 0
    }

    /// Whether the player's weapon is out; nil before melee starts.
    public var meleeWeaponInHand: Bool? {
        melee?.state.drawState.isWeaponInHand
    }
}
