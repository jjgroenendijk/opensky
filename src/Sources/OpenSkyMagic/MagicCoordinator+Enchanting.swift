// Enchanting at an arcane enchanter: disenchanting a carried item to learn its base
// enchantment, and putting known bases on a plain item copy with a filled soul gem.
// The numbers are in `EnchantingRules`. See docs/engine/enchanting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// Why the enchanter refused.
nonisolated enum EnchantingRefusal: Error, Equatable, Sendable {
    case notCarried
    case notEnchanted
    /// A staff, or an item with `MagicDisallowEnchanting`.
    case cannotDisenchant
    case alreadyKnown
    case alreadyEnchanted
    /// Neither a weapon nor apparel, or a staff.
    case notEnchantable
    case noBase
    case unknownBase
    case baseDoesNotFit(String)
    case tooManyBases(allowed: Int)
    /// OpenSky keeps one plugin per made enchantment; see docs/engine/enchanting.md.
    case mixedPlugins
    case emptyGem
}

nonisolated enum EnchantingOutcome: Equatable, Sendable {
    case idle
    case learned(item: String, base: String)
    case enchanted(item: String, name: String, charge: EnchantmentCharge)
    case refused(EnchantingRefusal)
    case unavailable
}

extension MagicCoordinator.EnchantingTable {
    /// Entry point 80: Extra Effect sets 2.
    var appliedEnchantmentsAllowed: Int {
        let allowed = coordinator.world.perkModified(
            1, at: .modAppliedEnchantmentsAllowed, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player), seams: ConditionContext()
        )
        return max(1, Int(allowed.rounded(.down)))
    }

    /// Puts `bases` on the best plain copy of `item`, spending `gem`.
    @discardableResult
    func enchant(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate, name: String? = nil
    ) -> EnchantingOutcome {
        guard let inventory = coordinator.world.inventory
        else { return coordinator.enchantingRecords.noteEnchanting(.unavailable) }
        switch preview(item, with: bases, gem: gem, name: name) {
        case let .failure(refusal):
            return coordinator.enchantingRecords.noteEnchanting(.refused(refusal))
        case let .success(made):
            let (state, id) = coordinator.enchantingRecords.enchantingState.making(made)
            coordinator.enchantingRecords.writeEnchanting(state)
            inventory.editCopy(
                of: item,
                in: .player,
                where: { $0.enchantment == nil },
                Self.making(id)
            )
            spendGem(gem, in: inventory)
            coordinator.enchantingRecords.reportEnchantingUse(EnchantingRules.enchantExperience)
            coordinator.weaponEnchantments.refreshWornEnchantments(on: .player)
            let charge = EnchantmentCharge(
                capacity: made.capacity,
                costPerUse: made.costPerUse(atSkill: enchantingSkill(of: .player))
            )
            return coordinator.enchantingRecords.noteEnchanting(.enchanted(
                item: coordinator.world.itemName(item), name: made.name, charge: charge
            ))
        }
    }

    /// What enchanting `item` with `bases` and `gem` would make, or why it cannot.
    func preview(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate, name: String? = nil
    ) -> Result<MadeEnchantment, EnchantingRefusal> {
        guard
            let store = coordinator.enchantmentStore, let inventory = coordinator.world.inventory,
            inventory.count(
                of: item,
                in: .player
            ) > 0 else { return .failure(.notCarried) }
        guard let isWeapon = enchantableKind(of: item) else { return .failure(.notEnchantable) }
        guard
            coordinator.weaponEnchantments.enchantmentProfile(of: item) == nil,
            inventory.copies(of: item, in: .player).contains(where: { $0.enchantment == nil })
        else { return .failure(.alreadyEnchanted) }
        guard !bases.isEmpty else { return .failure(.noBase) }
        let allowed = appliedEnchantmentsAllowed
        guard bases.count <= allowed else { return .failure(.tooManyBases(allowed: allowed)) }
        let state = coordinator.enchantingRecords.enchantingState
        let records = bases.compactMap { state.knows($0) ? store.enchantment(key: $0) : nil }
        guard records.count == bases.count else { return .failure(.unknownBase) }
        if let misfit = records.first(where: { !fits($0, item: item, isWeapon: isWeapon) }) {
            return .failure(.baseDoesNotFit(misfit.displayName))
        }
        guard Set(records.map { $0.sourcePlugin.lowercased() }).count == 1 else {
            return .failure(.mixedPlugins)
        }
        guard gem.soul != .empty else { return .failure(.emptyGem) }
        let input = EnchantingInput(
            skill: enchantingSkill(of: .player),
            soul: gem.soul,
            bases: records.map { record in
                EnchantingBase(
                    cost: Float(record.cost.cost),
                    perkFactor: enchantmentPower(of: record, on: item, using: store)
                )
            },
            skillFactor: coordinator.enchantingSkillFactor
        )
        let scale = isWeapon ? EnchantingRules.weapon(input) : EnchantingRules.apparel(input)
        return .success(MadeEnchantment(
            bases: bases, powers: scale.powers, capacity: scale.capacity,
            unskilledCostPerUse: scale.unskilledCostPerUse,
            name: name ?? records.map(\.displayName).joined(separator: " + ")
        ))
    }

    /// True for a weapon, false for apparel, nil for anything an enchanter refuses.
    func enchantableKind(of item: FormID) -> Bool? {
        guard
            let items = coordinator.world.inventory?.baselines.items,
            let definition = items.definition(item),
            !coordinator.world.itemHasKeyword(
                "MagicDisallowEnchanting",
                on: item
            ) else { return nil }
        switch definition.family {
        case .weapon:
            let animation = items.weapon(item)?.animationType
            return animation == .staff ? nil : true
        case .armor:
            return false
        default:
            return nil
        }
    }

    /// A weapon takes fire-and-forget contact bases; apparel takes constant effects. The
    /// base's worn restriction list must name one of the item's keywords.
    private func fits(_ base: ResolvedEnchantment, item: FormID, isWeapon: Bool) -> Bool {
        guard base.data?.type != .staffEnchantment, Self.isWeaponBase(base) == isWeapon else {
            return false
        }
        return coordinator.world.enchantment(base, fits: item)
    }

    private static func isWeaponBase(_ base: ResolvedEnchantment) -> Bool {
        base.data?.castingType == .fireAndForget && base.data?.delivery == .touch
    }

    /// Entry point 77 with the base and the item bound.
    private func enchantmentPower(
        of base: ResolvedEnchantment, on item: FormID, using store: EnchantmentStore
    ) -> Float {
        let subject = coordinator.world.inventory?.baselines.items.conditionSubject(of: item)
        return coordinator.world.perkModified(
            1, at: .modEnchantmentPower, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player)
                .binding(.enchantment, to: store.conditionSubject(of: base))
                .binding(.item, to: subject),
            seams: ConditionContext()
        )
    }

    /// The Enchanting value as it is now, so a Fortify Enchanting potion counts.
    func enchantingSkill(of player: ActorValueHolder) -> Float {
        guard let index = ActorValueIdentity.index(named: "Enchanting") else { return 0 }
        return coordinator.effects?.values.value(at: index, on: player) ?? 0
    }

    /// Puts the made enchantment on a copy; the copy's old charge belongs to nothing now.
    private static func making(_ id: FormID) -> (inout ItemCopy) -> Void {
        { copy in
            copy.enchantment = id
            copy.charge = nil
        }
    }
}

extension MagicCoordinator.EnchantingTable {
    /// A reusable gem, such as Azura's Star, empties and stays; any other gem is used up.
    func spendGem(_ gem: SoulGemCandidate, in inventory: any InventoryAccess) {
        if gem.copy.soul != 0 {
            inventory.editCopy(
                of: gem.item,
                in: .player,
                where: { $0 == gem.copy },
                { $0.soul = 0 }
            )
        }
        guard !coordinator.world.itemHasKeyword("ReusableSoulGem", on: gem.item) else { return }
        _ = attempt { try inventory.remove(gem.item, count: 1, from: .player) }
    }
}
