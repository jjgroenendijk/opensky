// Enchanting at an arcane enchanter: disenchanting a carried item to learn its base
// enchantment, and putting known bases on a plain item copy with a filled soul gem.
// The numbers are in `EnchantingRules`. See docs/engine/enchanting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// Why the enchanter refused.
nonisolated public enum EnchantingRefusal: Error, Equatable, Sendable {
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

nonisolated public enum EnchantingOutcome: Equatable, Sendable {
    case idle
    case learned(item: String, base: String)
    case enchanted(item: String, name: String, charge: EnchantmentCharge)
    case refused(EnchantingRefusal)
    case unavailable
}

/// One known base enchantment, for the readout.
nonisolated public struct EnchantingBaseReadout: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String
    /// A weapon base, rather than an apparel one.
    public let isWeapon: Bool

    public init(key: ReferenceKey, name: String, isWeapon: Bool) {
        self.key = key
        self.name = name
        self.isWeapon = isWeapon
    }
}

extension MagicCoordinator {
    public var enchantingState: EnchantingState {
        effects?.store.component(EnchantingState.self, for: .player) ?? EnchantingState()
    }

    /// Entry point 80: Extra Effect sets 2.
    public var appliedEnchantmentsAllowed: Int {
        let allowed = world.perkModified(
            1, at: .modAppliedEnchantmentsAllowed, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player), seams: ConditionContext()
        )
        return max(1, Int(allowed.rounded(.down)))
    }

    /// Destroys one `item` and teaches the root of its enchantment's base chain.
    @discardableResult
    public func disenchant(_ item: FormID) -> EnchantingOutcome {
        guard let store = enchantmentStore, let inventory = world.inventory else {
            return noteEnchanting(.unavailable)
        }
        guard inventory.count(of: item, in: .player) > 0 else {
            return noteEnchanting(.refused(.notCarried))
        }
        guard
            let profile = enchantmentProfile(of: item),
            let base = rootBase(of: profile),
            let root = store.enchantment(key: base)
        else { return noteEnchanting(.refused(.notEnchanted)) }
        guard !profile.isStaff, !world.itemHasKeyword("MagicDisallowEnchanting", on: item) else {
            return noteEnchanting(.refused(.cannotDisenchant))
        }
        let state = enchantingState
        guard !state.knows(base) else { return noteEnchanting(.refused(.alreadyKnown)) }
        let items = inventory.baselines.items
        let worth = items.gameValue(of: item) - (items.definition(item)?.value ?? 0)
        let itemName = world.itemName(item)
        _ = try? inventory.remove(item, count: 1, from: .player)
        writeEnchanting(state.learning(base))
        reportEnchantingUse(enchantingSettings.disenchantExperience(worth: worth))
        return noteEnchanting(.learned(item: itemName, base: root.displayName))
    }

    /// Puts `bases` on the best plain copy of `item`, spending `gem`.
    @discardableResult
    public func enchant(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate, name: String? = nil
    ) -> EnchantingOutcome {
        guard let inventory = world.inventory else { return noteEnchanting(.unavailable) }
        switch preview(item, with: bases, gem: gem, name: name) {
        case let .failure(refusal):
            return noteEnchanting(.refused(refusal))
        case let .success(made):
            let (state, id) = enchantingState.making(made)
            writeEnchanting(state)
            inventory.editCopy(
                of: item,
                in: .player,
                where: { $0.enchantment == nil },
                Self.making(id)
            )
            spendGem(gem, in: inventory)
            reportEnchantingUse(EnchantingRules.enchantExperience)
            refreshWornEnchantments(on: .player)
            let charge = EnchantmentCharge(capacity: made.capacity, costPerUse: made.costPerUse)
            return noteEnchanting(.enchanted(
                item: world.itemName(item), name: made.name, charge: charge
            ))
        }
    }

    /// What enchanting `item` with `bases` and `gem` would make, or why it cannot.
    public func preview(
        _ item: FormID, with bases: [ReferenceKey], gem: SoulGemCandidate, name: String? = nil
    ) -> Result<MadeEnchantment, EnchantingRefusal> {
        guard let store = enchantmentStore, let inventory = world.inventory else {
            return .failure(.notCarried)
        }
        guard inventory.count(of: item, in: .player) > 0 else { return .failure(.notCarried) }
        guard let isWeapon = enchantableKind(of: item) else { return .failure(.notEnchantable) }
        guard
            enchantmentProfile(of: item) == nil,
            inventory.copies(of: item, in: .player).contains(where: { $0.enchantment == nil })
        else { return .failure(.alreadyEnchanted) }
        guard !bases.isEmpty else { return .failure(.noBase) }
        let allowed = appliedEnchantmentsAllowed
        guard bases.count <= allowed else { return .failure(.tooManyBases(allowed: allowed)) }
        let state = enchantingState
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
            }
        )
        let scale = isWeapon ? EnchantingRules.weapon(input) : EnchantingRules.apparel(input)
        return .success(MadeEnchantment(
            bases: bases, powers: scale.powers, capacity: scale.capacity,
            costPerUse: scale.costPerUse,
            name: name ?? records.map(\.displayName).joined(separator: " + ")
        ))
    }

    /// Every base the player knows, named.
    public var knownEnchantingBases: [EnchantingBaseReadout] {
        guard let store = enchantmentStore else { return [] }
        return enchantingState.known.compactMap { key in
            store.enchantment(key: key).map {
                EnchantingBaseReadout(
                    key: key,
                    name: $0.displayName,
                    isWeapon: Self.isWeaponBase($0)
                )
            }
        }
    }

    /// The profile of the made enchantment on `holder`'s best copy of `item`, or nil.
    func madeProfile(of item: FormID, on holder: InventoryHolder) -> ItemEnchantmentProfile? {
        guard
            let store = enchantmentStore,
            let id = world.inventory?.copies(of: item, in: holder).first?.enchantment,
            EnchantingState.isMade(id),
            let made = enchantingState.made[id]
        else { return nil }
        return ItemEnchantmentProfile.made(made, item: item, using: store)
    }

    /// The last link of `profile`'s base chain, which disenchanting teaches.
    func rootBase(of profile: ItemEnchantmentProfile) -> ReferenceKey? {
        guard
            let store = enchantmentStore,
            case let .plugin(name, objectID) = profile.enchantment,
            let root = store.baseChain(of: ResolvedFormID(plugin: name, objectID: objectID)).last
        else { return nil }
        return ReferenceKey(resolved: root.id)
    }

    func isEnchantable(_ item: FormID) -> Bool {
        enchantableKind(of: item) != nil
    }

    /// True for a weapon, false for apparel, nil for anything an enchanter refuses.
    private func enchantableKind(of item: FormID) -> Bool? {
        guard let items = world.inventory?.baselines.items, let definition = items.definition(item)
        else { return nil }
        guard !world.itemHasKeyword("MagicDisallowEnchanting", on: item) else { return nil }
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
        return world.enchantment(base, fits: item)
    }

    private static func isWeaponBase(_ base: ResolvedEnchantment) -> Bool {
        base.data?.castingType == .fireAndForget && base.data?.delivery == .touch
    }

    /// Entry point 77 with the base and the item bound.
    private func enchantmentPower(
        of base: ResolvedEnchantment, on item: FormID, using store: EnchantmentStore
    ) -> Float {
        let subject = world.inventory?.baselines.items.conditionSubject(of: item)
        return world.perkModified(
            1, at: .modEnchantmentPower, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player)
                .binding(.enchantment, to: store.conditionSubject(of: base))
                .binding(.item, to: subject),
            seams: ConditionContext()
        )
    }

    /// The Enchanting value as it is now, so a Fortify Enchanting potion counts.
    private func enchantingSkill(of player: ActorValueHolder) -> Float {
        guard let index = ActorValueIdentity.index(named: "Enchanting") else { return 0 }
        return effects?.values.value(at: index, on: player) ?? 0
    }

    func reportEnchantingUse(_ amount: Float) {
        guard amount > 0, let skill = ActorValueIdentity.index(named: "Enchanting") else { return }
        world.reportSkillUse(SkillUseEvent(
            actor: .player,
            action: .craft(skill: skill),
            amount: amount
        ))
    }

    private func writeEnchanting(_ state: EnchantingState) {
        guard let store = effects?.store else { return }
        if state.isEmpty {
            store.reset(.enchanting, for: .player)
        } else {
            store.set(state, for: .player)
        }
    }

    @discardableResult
    private func noteEnchanting(_ outcome: EnchantingOutcome) -> EnchantingOutcome {
        lastEnchanting = outcome
        return outcome
    }

    /// Puts the made enchantment on a copy; the copy's old charge belongs to nothing now.
    private static func making(_ id: FormID) -> (inout ItemCopy) -> Void {
        { copy in
            copy.enchantment = id
            copy.charge = nil
        }
    }
}
