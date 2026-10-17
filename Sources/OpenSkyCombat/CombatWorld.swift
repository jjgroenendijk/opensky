// The world side of the combat domain: what `CombatCoordinator` reads from and
// asks of the running session. The app answers it; a test passes a fake. Changes
// nothing later in a step reads go back as `CombatCommand` values.
// See docs/engine/combat.md and docs/engine/coordinators.md.

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

/// What one actor could cast, before `CombatCore` filters it.
nonisolated public struct CombatCastingFacts: Equatable, Sendable {
    public let magicka: Float
    public let spells: [CombatSpellCandidate]

    public init(magicka: Float, spells: [CombatSpellCandidate]) {
        self.magicka = magicka
        self.spells = spells
    }
}

/// What `CombatCoordinator` reads from the running world. The hit, skill,
/// enchantment and spell reports pass through to the session's own runtimes.
public protocol CombatWorld: ScriptHitReporting, SkillUseReporting, SpellHitApplying,
    WeaponEnchantmentApplying
{
    /// The player's capsule pose. Nil without a renderer.
    var playerAttacker: MeleeAttacker? { get }
    /// Where a player shot leaves from and which way. Nil without a renderer.
    var playerShooter: ProjectileShooter? { get }
    /// Every resident actor, with its current pose and death state.
    func residentActors() -> [CombatActorObservation]
    /// The actor the panel's hostility control acts on.
    func selectedActor() -> ReferenceKey?
    /// The numbers of `key`'s resolved CSTY combat style, or nil when it has none.
    func combatStyle(of key: ReferenceKey) -> CombatStyleTuning?

    func hostility(of key: ReferenceKey) -> ActorHostility
    @discardableResult
    func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool
    func awareness(of observer: ReferenceKey, toward target: ReferenceKey) -> CombatAwareness

    /// Reads `key`'s actor values by AVIF index. Nil when the session has no
    /// actor-value runtime or `key` is not resident.
    func actorValues(of key: ReferenceKey) -> ((Int32) -> Float?)?
    func perkMultiplier(at entryPoint: PerkEntryPoint, on key: ReferenceKey) -> Float
    /// What `key`'s perks make of `value`, with `subjects` bound and `seams` laid over
    /// the live conditions.
    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float
    /// `key`'s passing effects at an entry point that picks a spell, highest priority first.
    func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice]
    /// Current and maximum health. Nil when `key` has no actor values.
    func health(of key: ReferenceKey) -> (current: Float, maximum: Float)?
    @discardableResult
    func damageHealth(by amount: Float, of key: ReferenceKey) -> Bool
    func damageStamina(by amount: Float, of key: ReferenceKey)
    /// Whether `key` owns the perk with `editorID`.
    func ownsPerk(editorID: String, on key: ReferenceKey) -> Bool

    /// The player's equipment. Nil without an equipment runtime.
    var equipment: (any EquipmentAccess)? { get }
    func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile?
    /// The quality level of the player's best copy of `item`. Zero when plain.
    func temperLevel(of item: FormID) -> Int32
    /// What `key` wears, each item with its tempering level. Empty when unknown.
    func equippedItems(of key: ReferenceKey) -> [(item: FormID, temperLevel: Int32)]
    func hasReadiedSpell(in hand: SpellHand) -> Bool
    /// The items the player carries, in the inventory's stable stack order.
    func playerCarriedItems() -> [FormID]
    @discardableResult
    func removeOneFromPlayer(_ item: FormID) -> Bool

    /// Nil when `key` cannot cast in this session.
    func castingFacts(of key: ReferenceKey) -> CombatCastingFacts?
    @discardableResult
    func beginCast(_ spell: ReferenceKey, by key: ReferenceKey) -> Bool
    /// Lets go of the cast. Returns true when the cast finished.
    @discardableResult
    func releaseCast(by key: ReferenceKey) -> Bool
    func cancelCast(by key: ReferenceKey)

    @discardableResult
    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool
    func stopActor(_ key: ReferenceKey)
    func resumePackage(for key: ReferenceKey)

    /// Raises `name` on the player's behavior graph. Returns true when the
    /// graph declares the event.
    @discardableResult
    func raisePlayerGraphEvent(_ name: String) -> Bool
    func writePlayerGraphVariable(_ value: BehaviorVariableValue, named name: String)
    @discardableResult
    func playReaction(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool
    /// The MATT an actor's body counts as when struck: its race's `NAM4`.
    func impactMaterial(of actor: ReferenceKey) -> FormID?

    func sweep(_ query: ShapeSweepQuery) -> ShapeSweepHit?
    func residentCells() -> Set<CellSceneLocation>
    /// Spawns a stuck arrow. Nil when the store refused it.
    func spawn(_ reference: ReferenceSpawnState, in location: CellSceneLocation) -> ReferenceKey?

    /// Ragdoll and dynamic-body counts. The projectile fields stay zero.
    var bodyTransients: CombatTransientCounts { get }
    /// Trims ragdolls and awake bodies, and returns how many of each went.
    func trimBodyTransients(to limits: CombatTransientLimits) -> CombatTransientCounts
    /// What `key`'s running magic effects force on it, such as Calm or Etherealize.
    func magicInfluence(of key: ReferenceKey) -> ActorMagicInfluence
    /// Adds `count` of `item` to `key`'s inventory. False where it holds none.
    @discardableResult
    func addItem(_ item: FormID, count: Int32, to key: ReferenceKey) -> Bool
}

extension CombatWorld {
    /// A session with no magic forces no behaviour.
    public func magicInfluence(of _: ReferenceKey) -> ActorMagicInfluence {
        .none
    }

    /// A session with no stamina pays nothing to block.
    public func damageStamina(by _: Float, of _: ReferenceKey) {}

    @discardableResult
    public func addItem(_: FormID, count _: Int32, to _: ReferenceKey) -> Bool {
        false
    }

    /// A session with no perks owns none.
    public func ownsPerk(editorID _: String, on _: ReferenceKey) -> Bool {
        false
    }

    public func perkModified(
        _ value: Float,
        at _: PerkEntryPoint,
        on _: ReferenceKey,
        subjects _: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> Float {
        value
    }

    public func perkChoices(
        at _: PerkEntryPoint,
        on _: ReferenceKey,
        subjects _: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> [PerkEntryPointChoice] {
        []
    }

    /// A session with no equipment wears nothing, so no armour stops a blow.
    public func equippedItems(of _: ReferenceKey) -> [(item: FormID, temperLevel: Int32)] {
        []
    }
}
