// A fake `MagicWorld` and a fixed `ActorValueAccess` for the coordinator suite.
// Every answer is a stored value and every call is recorded.

import OpenSkyActorsInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState

@MainActor
final class FakeMagicWorld: MagicWorld {
    var gameDaysPassed: Float = 0
    var inventory: (any InventoryAccess)?
    var equipment: (any EquipmentAccess)?
    var residents: [ReferenceKey] = []
    var raceSpells: [FormID] = []
    var aim = SpellAim.none
    var canFireProjectile = true
    private(set) var firedProjectiles: [SpellPayload] = []
    private(set) var aimRequests: [(range: Float, caster: ReferenceKey)] = []
    private(set) var skillUses: [SkillUseEvent] = []
    private(set) var probedFunctions: [UInt16] = []

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return 0
    }

    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        key == .player ? .player : nil
    }

    func regeneratingHolders() -> [ActorValueHolder] {
        [.player]
    }

    func nearestActorValueHolder() -> ActorValueHolder? {
        nil
    }

    func residentActorKeys() -> [ReferenceKey] {
        residents
    }

    func actorName(_ holder: ActorValueHolder) -> String {
        holder.key.description
    }

    func itemName(_ item: FormID) -> String {
        "item \(item.rawValue)"
    }

    func playerRaceSpells() -> [FormID] {
        raceSpells
    }

    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        firedProjectiles.append(payload)
        return canFireProjectile
    }

    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        aimRequests.append((range, caster))
        return aim
    }

    func conditionText(
        of function: UInt16,
        parameter _: UInt32,
        in _: ConditionContext
    ) -> String {
        probedFunctions.append(function)
        return "probed"
    }
}

/// Every actor has the same fixed values, and no write changes them.
@MainActor
struct FixedActorValues: ActorValueAccess {
    let store = WorldStateStore()
    let baselines = ActorValueBaselineResolver(
        fallback: ActorValueBaseline(
            maximums: ActorValues(repeating: 100),
            regenPercentPerSecond: .zero
        )
    )
    var values = ActorValues(repeating: 100)

    func baseline(of _: ActorValueHolder) -> ActorValueBaseline {
        baselines.fallback
    }

    func maximums(of _: ActorValueHolder) -> ActorValues {
        values
    }

    func current(of _: ActorValueHolder) -> ActorValues {
        values
    }

    func fractions(of _: ActorValueHolder) -> ActorValues {
        ActorValues(repeating: 1)
    }

    func hasZeroHealth(_: ActorValueHolder) -> Bool {
        false
    }

    func damage(_: ActorValueKind, by _: Float, on _: ActorValueHolder) -> ActorValueState {
        ActorValueState(current: values)
    }

    func set(_: ActorValueKind, to _: Float, on _: ActorValueHolder) -> ActorValueState {
        ActorValueState(current: values)
    }

    func restoreAll(on _: ActorValueHolder) -> ActorValueState {
        ActorValueState(current: values)
    }

    func value(at _: Int32, on _: ActorValueHolder) -> Float? {
        nil
    }

    func baseValue(at _: Int32, on _: ActorValueHolder) -> Float? {
        nil
    }

    func entry(at _: Int32, on _: ActorValueHolder) -> ActorValueEntry? {
        nil
    }

    func resolvedEntries(of _: ActorValueHolder) -> [Int32: ActorValueEntry] {
        [:]
    }

    func damage(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func restore(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func setValue(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func setBase(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func incrementBase(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func advanceSkill(at _: Int32, by _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func addModifier(
        _: Float,
        to _: ActorValueModifier,
        at _: Int32,
        on _: ActorValueHolder
    ) -> Bool {
        false
    }

    func setModifier(
        _: Float,
        for _: ActorValueModifier,
        at _: Int32,
        on _: ActorValueHolder
    ) -> Bool {
        false
    }

    func forceValue(at _: Int32, to _: Float, on _: ActorValueHolder) -> Bool {
        false
    }

    func magicDamageMultiplier(
        element _: Int32?,
        on _: ActorValueHolder,
        settings _: ActorResistanceSettings
    ) -> Float {
        1
    }
}
