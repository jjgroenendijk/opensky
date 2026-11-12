// Effects on weapons: bound weapons go when sheathed, and an enhancement needs a melee
// weapon. A refused effect tells the player why.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import simd

extension MagicCoordinator.WeaponArchetypes {
    /// The weapons `holder`'s running Bound Weapon effects conjured.
    func boundWeapons(on holder: ActorValueHolder) -> [FormID] {
        guard let runtime = coordinator.effects else { return [] }
        return runtime.active(on: holder)
            .filter { runtime.rule(of: $0) == .world(.boundWeapon) }
            .compactMap {
                coordinator.associatedItem(of: $0.effect).flatMap(runtime.effects.loadOrderFormID)
            }
    }

    /// Bound Weapon "dispels it when the duration expires or the weapon is sheathed".
    func dismissBoundWeaponsOnSheathe(of key: ReferenceKey) {
        guard
            let runtime = coordinator.effects,
            let holder = coordinator.world.actorValueHolder(for: key) else { return }
        let running = runtime.active(on: holder)
            .filter { runtime.rule(of: $0) == .world(.boundWeapon) }
        guard !running.isEmpty else { return }
        let sequences = Set(running.map(\.sequence))
        coordinator.withEffects { $0.dispel(on: holder) { sequences.contains($0.sequence) } }
    }

    /// "Until unequipped": an actor left with no usable melee weapon loses the effect.
    func endWeaponEnhancement(on holder: ActorValueHolder) {
        guard
            let runtime = coordinator.effects,
            enhanceWeaponRefusal(on: holder) != nil else { return }
        let running = runtime.active(on: holder)
            .filter { runtime.rule(of: $0) == .world(.enhanceWeapon) }
        guard !running.isEmpty else { return }
        let sequences = Set(running.map(\.sequence))
        coordinator.withEffects { $0.dispel(on: holder) { sequences.contains($0.sequence) } }
    }

    /// "Any equipped (melee) weapon receives the specified enchantment." UESP: it "does
    /// not work on enchanted or bound weapons".
    func enhanceWeaponRefusal(on holder: ActorValueHolder) -> MagicEffectPlanFailure? {
        let weapons = meleeWeapons(of: holder)
        guard !weapons.isEmpty else { return .noMeleeWeapon }
        let owner = InventoryHolder(actor: holder)
        let bound = Set(boundWeapons(on: holder))
        let usable = weapons.filter { weapon in
            coordinator.weaponEnchantments
                .enchantmentProfile(of: weapon, on: owner) == nil && !bound.contains(weapon)
        }
        return usable.isEmpty ? .weaponEnchanted : nil
    }

    /// The equipped weapons that strike in melee: not a bow, a crossbow, or a staff.
    func meleeWeapons(of holder: ActorValueHolder) -> [FormID] {
        guard
            let inventory = coordinator.world.inventory,
            let equipment = coordinator.world.equipment else { return [] }
        let items = inventory.baselines.items
        return equipment.equipped(on: InventoryHolder(actor: holder)).filter { item in
            guard let kind = items.weapon(item)?.animationType else { return false }
            return ![.bow, .staff, .crossbow, .other].contains(kind)
        }
    }

    /// Why `archetype` cannot act on `holder`, for the runtime's target check.
    func worldRefusal(
        _ archetype: MagicWorldArchetype, on holder: ActorValueHolder
    ) -> MagicEffectPlanFailure? {
        switch archetype {
        case .banish, .commandSummoned:
            let summoned = coordinator.commanded
                .contains { $0.actor == holder.key && $0.kind == .summoned }
            return summoned ? nil : .wrongTarget(archetype == .banish ? .banish : .commandSummoned)
        case .werewolfFeed:
            return coordinator.world.isActorDead(holder.key) ? nil : .wrongTarget(.werewolfFeed)
        case .enhanceWeapon:
            let refusal = enhanceWeaponRefusal(on: holder)
            if let refusal, holder.key == .player {
                coordinator.pendingCommands.append(.notice(coordinator.texts.castNotices[
                    refusal == .noMeleeWeapon ? .enhanceWeaponNoWeapon : .enhanceWeaponEnchanted
                ]))
            }
            return refusal
        default:
            return nil
        }
    }
}
