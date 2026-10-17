// A `CombatWorld` over plain dictionaries, for `CombatCoordinatorTests`. Each
// write is recorded so a test can check what the coordinator asked for.

@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventoryInterface
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
@testable import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import simd

@MainActor
final class FakeCoordinatorWorld: CombatWorld {
    var actors: [CombatActorObservation] = []
    var selected: ReferenceKey?
    var hostilities: [ReferenceKey: ActorHostility] = [:]
    var values: [ReferenceKey: [Int32: Float]] = [:]
    var perkMultipliers: [ReferenceKey: Float] = [:]
    /// Every actor's perks at an entry point: `value * factor + addend`.
    var perkFactors: [PerkEntryPoint: Float] = [:]
    var perkAddends: [PerkEntryPoint: Float] = [:]
    /// The spell each picking entry point chooses.
    var perkSpells: [PerkEntryPoint: ResolvedSpell] = [:]
    var perkTexts: [PerkEntryPoint: [String]] = [:]
    /// The owner and subjects of the last question at each entry point.
    private(set) var perkQuestions: [PerkEntryPoint: PerkEvaluationSubjects] = [:]
    private(set) var spellHits: [SpellHit] = []
    var healths: [ReferenceKey: (current: Float, maximum: Float)] = [:]
    var casting: [ReferenceKey: CombatCastingFacts] = [:]
    var styles: [ReferenceKey: CombatStyleTuning] = [:]
    /// Who each observer has detected; everyone else is unaware.
    var detects: [ReferenceKey: Set<ReferenceKey>] = [:]
    var finishesCasts = true
    var bodyTransients = CombatTransientCounts.none
    var trimmedBodies = CombatTransientCounts.none

    private(set) var damage: [(key: ReferenceKey, amount: Float)] = []
    private(set) var staminaDamage: [(key: ReferenceKey, amount: Float)] = []
    private(set) var castingQueries: [ReferenceKey] = []
    private(set) var cancelledCasts: [ReferenceKey] = []
    private(set) var raisedEvents: [String] = []
    private(set) var spawned: [ReferenceSpawnState] = []
    private var nextKey: UInt64 = 100

    var playerAttacker: MeleeAttacker? {
        MeleeAttacker(key: .player, feet: SIMD3(), facing: 0)
    }

    var playerShooter: ProjectileShooter? {
        nil
    }

    var equipment: (any EquipmentAccess)? {
        nil
    }

    func residentActors() -> [CombatActorObservation] {
        actors
    }

    func selectedActor() -> ReferenceKey? {
        selected
    }

    func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        styles[key]
    }

    func hostility(of key: ReferenceKey) -> ActorHostility {
        hostilities[key] ?? .neutral
    }

    func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        hostilities[key] = hostility
        return true
    }

    func awareness(of observer: ReferenceKey, toward target: ReferenceKey) -> CombatAwareness {
        detects[observer]?.contains(target) == true ? .detected(at: SIMD3()) : .unaware
    }

    func actorValues(of key: ReferenceKey) -> ((Int32) -> Float?)? {
        guard let entries = values[key] else { return nil }
        return { entries[$0] }
    }

    func perkMultiplier(at _: PerkEntryPoint, on key: ReferenceKey) -> Float {
        perkMultipliers[key] ?? 1
    }

    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on _: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> Float {
        perkQuestions[entryPoint] = subjects
        return value * (perkFactors[entryPoint] ?? 1) + (perkAddends[entryPoint] ?? 0)
    }

    func perkChoices(
        at entryPoint: PerkEntryPoint,
        on _: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> [PerkEntryPointChoice] {
        perkQuestions[entryPoint] = subjects
        if let texts = perkTexts[entryPoint] {
            return texts.map { PerkEntryPointChoice(text: $0) }
        }
        guard let spell = perkSpells[entryPoint] else { return [] }
        return [PerkEntryPointChoice(spell: spell)]
    }

    func health(of key: ReferenceKey) -> (current: Float, maximum: Float)? {
        healths[key]
    }

    func damageHealth(by amount: Float, of key: ReferenceKey) -> Bool {
        damage.append((key, amount))
        return true
    }

    func damageStamina(by amount: Float, of key: ReferenceKey) {
        staminaDamage.append((key, amount))
    }

    func enchantmentProfile(of _: FormID) -> ItemEnchantmentProfile? {
        nil
    }

    func temperLevel(of _: FormID) -> Int32 {
        0
    }

    func hasReadiedSpell(in _: SpellHand) -> Bool {
        false
    }

    func playerCarriedItems() -> [FormID] {
        []
    }

    func removeOneFromPlayer(_: FormID) -> Bool {
        false
    }

    func castingFacts(of key: ReferenceKey) -> CombatCastingFacts? {
        castingQueries.append(key)
        return casting[key]
    }

    func beginCast(_: ReferenceKey, by _: ReferenceKey) -> Bool {
        true
    }

    func releaseCast(by _: ReferenceKey) -> Bool {
        finishesCasts
    }

    func cancelCast(by key: ReferenceKey) {
        cancelledCasts.append(key)
    }

    func moveActor(_: ReferenceKey, to _: SIMD3<Float>) -> Bool {
        true
    }

    func stopActor(_: ReferenceKey) {}

    func resumePackage(for _: ReferenceKey) {}

    func raisePlayerGraphEvent(_ name: String) -> Bool {
        raisedEvents.append(name)
        return true
    }

    func writePlayerGraphVariable(_: BehaviorVariableValue, named _: String) {}

    func playReaction(_: CombatActorClip, on _: ReferenceKey) -> Bool {
        false
    }

    func impactMaterial(of _: ReferenceKey) -> FormID? {
        nil
    }

    func sweep(_: ShapeSweepQuery) -> ShapeSweepHit? {
        nil
    }

    func residentCells() -> Set<CellSceneLocation> {
        []
    }

    func spawn(_ reference: ReferenceSpawnState, in _: CellSceneLocation) -> ReferenceKey? {
        spawned.append(reference)
        nextKey += 1
        return .generated(nextKey)
    }

    func trimBodyTransients(to _: CombatTransientLimits) -> CombatTransientCounts {
        trimmedBodies
    }

    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        spellHits.append(hit)
        return .none
    }

    func applyWeaponEnchantment(_: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        nil
    }

    private(set) var skillUses: [SkillUseEvent] = []

    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return use.amount
    }
}
