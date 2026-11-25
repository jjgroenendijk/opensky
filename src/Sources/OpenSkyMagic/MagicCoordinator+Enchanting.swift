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
    case emptyGem
}

/// What the player set besides the item, bases, and gem.
nonisolated struct EnchantingOptions: Equatable, Sendable {
    /// A typed name; nil names the enchantment after its bases.
    var name: String?
    /// The slider's magnitude; nil is the highest.
    var magnitude: Int?
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
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate,
        options: EnchantingOptions = EnchantingOptions()
    ) -> EnchantingOutcome {
        guard let inventory = coordinator.world.inventory
        else { return coordinator.enchantingRecords.noteEnchanting(.unavailable) }
        switch preview(item, with: bases, gem: gem, options: options) {
        case let .failure(refusal):
            return coordinator.enchantingRecords.noteEnchanting(.refused(refusal))
        case let .success(made):
            let (state, id) = coordinator.enchantingRecords.enchantingState.making(made)
            coordinator.enchantingRecords.writeEnchanting(state)
            inventory.editCopy(
                of: item,
                in: .player,
                where: { $0.enchantment == nil },
                Self.making(id, named: options.name)
            )
            spendGem(gem, in: inventory)
            coordinator.incrementStat("Magic Items Made")
            coordinator.enchantingRecords.reportEnchantingUse(EnchantingRules.enchantExperience)
            coordinator.weaponEnchantments.refreshWornEnchantments(on: .player)
            let charge = EnchantmentCharge(capacity: made.capacity, costPerUse: made.costPerUse)
            return coordinator.enchantingRecords.noteEnchanting(.enchanted(
                item: coordinator.world.itemName(item), name: made.name, charge: charge
            ))
        }
    }

    /// What enchanting `item` with `bases` and `gem` would make, or why it cannot.
    func preview(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate,
        options: EnchantingOptions = EnchantingOptions()
    ) -> Result<MadeEnchantment, EnchantingRefusal> {
        let order: EnchantingOrder
        switch input(item, with: bases, gem: gem, magnitude: options.magnitude) {
        case let .failure(refusal): return .failure(refusal)
        case let .success(found): order = found
        }
        let scale = order.isWeapon
            ? EnchantingRules.weapon(order.input) : EnchantingRules.apparel(order.input)
        return .success(MadeEnchantment(
            bases: bases, powers: scale.powers, capacity: scale.capacity,
            costPerUse: scale.costPerUse,
            name: order.records.map(\.displayName).joined(separator: " + ")
        ))
    }

    /// The magnitude slider for `item` with `bases`, or nil for apparel or a maximum of 1.
    func slider(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate, magnitude: Int?
    ) -> EnchantingSlider? {
        guard
            case let .success(order) = input(item, with: bases, gem: gem, magnitude: magnitude),
            order.isWeapon, var slider = EnchantingRules.slider(order.input)
        else { return nil }
        slider.uses = EnchantingRules.weapon(order.input).uses
        return slider
    }

    /// The rules' input for this choice, or why the enchanter refuses it.
    private func input(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate, magnitude: Int?
    ) -> Result<EnchantingOrder, EnchantingRefusal> {
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
        guard gem.soul != .empty else { return .failure(.emptyGem) }
        let perks = EnchantingPerks(world: coordinator.world, item: item, store: store)
        var input = EnchantingInput(
            skill: enchantingSkill(of: .player),
            soul: gem.soul,
            bases: records.map { record in
                EnchantingBase(cost: perks.cost(of: record), perkFactor: perks.power(of: record))
            },
            skillFactor: coordinator.enchantingSkillFactor
        )
        input.charge = perks.charge(of: gem.soul, first: records[0])
        input.baseMagnitude = Self.scaledValue(of: records[0])
        input.chosen = magnitude
        return .success(EnchantingOrder(input: input, isWeapon: isWeapon, records: records))
    }

    /// The first effect's magnitude, or its duration where power changes only that.
    static func scaledValue(of base: ResolvedEnchantment) -> Float {
        EnchantingKinds.scaledValue(of: base)
    }

    /// True for a weapon, false for apparel, nil for anything an enchanter refuses.
    func enchantableKind(of item: FormID) -> Bool? {
        EnchantingKinds(owner: self).enchantableKind(of: item)
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

    /// The Enchanting value as it is now, so a Fortify Enchanting potion counts.
    func enchantingSkill(of player: ActorValueHolder) -> Float {
        guard let index = ActorValueIdentity.index(named: "Enchanting") else { return 0 }
        return coordinator.effects?.values.value(at: index, on: player) ?? 0
    }

    /// Puts the made enchantment and the typed name on a copy; the copy's old charge
    /// belongs to nothing now.
    private static func making(_ id: FormID, named name: String?) -> (inout ItemCopy) -> Void {
        { copy in
            copy.enchantment = id
            copy.charge = nil
            copy.name = name
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

/// One enchanter choice as the rules read it: their input, whether the item is a weapon,
/// and the base records.
struct EnchantingOrder {
    let input: EnchantingInput
    let isWeapon: Bool
    let records: [ResolvedEnchantment]
}

extension MagicCoordinator.EnchantingTable {
    /// Scales an enchantment's value and finds the kind of item it fits.
    struct EnchantingKinds {
        let owner: MagicCoordinator.EnchantingTable

        static func scaledValue(of base: ResolvedEnchantment) -> Float {
            guard let first = base.effects.first else { return 0 }
            let flags = first.effect?.effect.data?.flags ?? []
            if flags.contains(.powerAffectsDuration), !flags.contains(.powerAffectsMagnitude) {
                return Float(first.item.duration)
            }
            return first.item.magnitude
        }

        func enchantableKind(of item: FormID) -> Bool? {
            let coordinator = owner.coordinator
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
    }
}
