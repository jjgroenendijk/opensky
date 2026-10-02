// A fake `MagicWorld` for the coordinator suite.
// Every answer is a stored value and every call is recorded.

import OpenSkyActorsInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface

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
