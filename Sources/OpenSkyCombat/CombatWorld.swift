// The world side of the combat domain: what `CombatCoordinator` reads from and
// does to the running session. The app answers it; a test passes a fake.
// See docs/engine/combat.md and docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
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
    /// The ground material under the player, for impact sounds.
    var groundMaterial: FormID? { get }

    func hostility(of key: ReferenceKey) -> ActorHostility
    @discardableResult
    func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool
    func awareness(of observer: ReferenceKey, toward target: ReferenceKey) -> CombatAwareness

    /// Reads `key`'s actor values by AVIF index. Nil when the session has no
    /// actor-value runtime or `key` is not resident.
    func actorValues(of key: ReferenceKey) -> ((Int32) -> Float?)?
    func perkMultiplier(at entryPoint: PerkEntryPoint, on key: ReferenceKey) -> Float
    /// Current and maximum health. Nil when `key` has no actor values.
    func health(of key: ReferenceKey) -> (current: Float, maximum: Float)?
    @discardableResult
    func damageHealth(by amount: Float, of key: ReferenceKey) -> Bool

    /// The player's equipment. Nil without an equipment runtime.
    var equipment: (any EquipmentAccess)? { get }
    func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile?
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
    func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>)
    func setCombatMusicActive(_ active: Bool)

    func sweep(_ query: ShapeSweepQuery) -> ShapeSweepHit?
    func residentCells() -> Set<CellSceneLocation>
    /// Spawns a stuck arrow. Nil when the store refused it.
    func spawn(_ reference: ReferenceSpawnState, in location: CellSceneLocation) -> ReferenceKey?
    /// Drops every stored change for `key`, which removes a spawned reference.
    func resetReference(_ key: ReferenceKey)

    /// Ragdoll and dynamic-body counts. The projectile fields stay zero.
    var bodyTransients: CombatTransientCounts { get }
    /// Trims ragdolls and awake bodies, and returns how many of each went.
    func trimBodyTransients(to limits: CombatTransientLimits) -> CombatTransientCounts
    func resetRagdolls()
}
