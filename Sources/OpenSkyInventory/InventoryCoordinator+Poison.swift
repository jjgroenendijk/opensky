// Weapon poison: using a poison puts it on the weapon in the right hand, for as many
// hits as Mod Poison Dose Count gives. The hit side lives in the magic feature.
// CK wiki "Perk Entry Point": <https://ck.uesp.net/wiki/Perk_Entry_Point>.
// See docs/engine/alchemy.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    /// The poisons on the player's weapons.
    public var playerWeaponPoisons: WeaponPoisonState {
        runtime?.store.component(WeaponPoisonState.self, for: .player) ?? WeaponPoisonState()
    }

    /// Whether `item` is an `ALCH` with the Poison flag, which a use puts on a weapon.
    public func isPoison(_ item: FormID) -> Bool {
        runtime?.inventory.baselines.items.ingestibles[item.rawValue]?.flags
            .contains(.poison) == true
    }

    /// The weapon the player holds in the right hand, or nil with none drawn.
    public var poisonableWeapon: FormID? {
        guard let runtime, let equipment else { return nil }
        let items = runtime.inventory.baselines.items
        let weapons = equipment.equipped(on: runtime.player).filter { items.weapon($0) != nil }
        return weapons.first { equipment.occupancy(of: $0).hands.contains(.rightHand) }
            ?? weapons.first
    }

    /// Uses one `poison` on the right-hand weapon. A staff, or a weapon that still carries a
    /// poison, refuses it, as `sPoisonUnableToPoison` and `sPoisonAlreadyPoisonedMessage` say.
    @discardableResult
    public func applyPoison(_ poison: FormID) -> AlchemyActionOutcome {
        guard let runtime else { return noteAlchemy(.unavailable) }
        let poisonName = name(of: poison)
        guard isPoison(poison) else { return noteAlchemy(.notAPoison(poisonName)) }
        guard let weapon = poisonableWeapon else { return noteAlchemy(.noWeapon) }
        if runtime.inventory.baselines.items.weapon(weapon)?.animationType == .staff {
            return noteAlchemy(.cannotPoison)
        }
        if playerWeaponPoisons.poisons[weapon] != nil {
            return noteAlchemy(.alreadyPoisoned)
        }
        do {
            try runtime.inventory.remove(poison, count: 1, from: runtime.player)
        } catch {
            return noteAlchemy(.noneCarried(poisonName))
        }
        let doses = poisonDoses(of: poison)
        runtime.store.set(
            playerWeaponPoisons.applying(WeaponPoison(poison: poison, doses: doses), to: weapon),
            for: .player
        )
        return noteAlchemy(.poisoned(weapon: name(of: weapon), poison: poisonName, doses: doses))
    }

    /// Mod Poison Dose Count, with the poison bound as the item.
    private func poisonDoses(of poison: FormID) -> Int32 {
        let subject = runtime?.inventory.baselines.items.conditionSubject(of: poison)
        let value = world.perkModified(
            1,
            at: .modPoisonDoseCount,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
        return value.isFinite ? Int32(clamping: Int(max(1, value.rounded(.down)))) : 1
    }
}
