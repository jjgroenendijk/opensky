// A `CombatWorld` over plain dictionaries, for `CombatCoordinatorTests`. Each
// write is recorded so a test can check what the coordinator asked for.

@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
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
    var healths: [ReferenceKey: (current: Float, maximum: Float)] = [:]
    var casting: [ReferenceKey: CombatCastingFacts] = [:]
    var styles: [ReferenceKey: CombatStyleTuning] = [:]
    var finishesCasts = true
    var bodyTransients = CombatTransientCounts.none
    var trimmedBodies = CombatTransientCounts.none

    private(set) var damage: [(key: ReferenceKey, amount: Float)] = []
    private(set) var castingQueries: [ReferenceKey] = []
    private(set) var cancelledCasts: [ReferenceKey] = []
    private(set) var raisedEvents: [String] = []
    private(set) var spawned: [ReferenceSpawnState] = []
    private(set) var resetKeys: [ReferenceKey] = []
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

    func awareness(of _: ReferenceKey, toward _: ReferenceKey) -> CombatAwareness {
        .unaware
    }

    func actorValues(of key: ReferenceKey) -> ((Int32) -> Float?)? {
        guard let entries = values[key] else { return nil }
        return { entries[$0] }
    }

    func perkMultiplier(at _: PerkEntryPoint, on key: ReferenceKey) -> Float {
        perkMultipliers[key] ?? 1
    }

    func health(of key: ReferenceKey) -> (current: Float, maximum: Float)? {
        healths[key]
    }

    func damageHealth(by amount: Float, of key: ReferenceKey) -> Bool {
        damage.append((key, amount))
        return true
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

    func playImpact(_: ResolvedMeleeImpact, at _: SIMD3<Float>) {}

    func impactMaterial(of _: ReferenceKey) -> FormID? {
        nil
    }

    func setCombatMusicActive(_: Bool) {}

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

    func resetReference(_ key: ReferenceKey) {
        resetKeys.append(key)
    }

    func trimBodyTransients(to _: CombatTransientLimits) -> CombatTransientCounts {
        trimmedBodies
    }

    func resetRagdolls() {}

    func applySpellHit(_: SpellHit) -> SpellHitReport {
        .none
    }

    func applyWeaponEnchantment(_: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        nil
    }
}
