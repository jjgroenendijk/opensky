// One enchanted item, resolved once into everything the runtime needs, like
// `SpellPayload`. The casting type selects behavior: a constant effect is worn,
// a contact one fires on a hit, and a staff one is neither. The worn restriction
// is not enforced, because vanilla items break it (Gauldur Amulet;
// `EnchantmentRuntimeRealDataTests`). See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One enchanted item's enchantment, resolved.
nonisolated public struct ItemEnchantmentProfile: Equatable, Sendable {
    /// The WEAP or ARMO base record. What the charge and the worn effects are
    /// keyed by, and what a readout names.
    public let item: FormID
    /// The winning ENCH identity, which every applied effect is sourced to.
    public let enchantment: ReferenceKey
    /// The plugin every `EFID` in `entries` is relative to.
    public let sourcePlugin: String
    /// The effect list as authored. Magnitudes are pre-resistance.
    public let entries: [MagicItemEffect]
    /// FULL name or editor ID of the enchantment, for the readout. Never empty.
    public let name: String
    public let castingType: MagicEffectCastingType
    public let delivery: MagicEffectDelivery
    public let type: EnchantmentType
    /// The item's `EAMT`: the fully charged value. Zero on ARMO, which has no
    /// charge field at all.
    public let capacity: Float
    /// The enchantment's cost — what one use spends.
    public let costPerUse: Float
    /// The `FLST` of keywords the enchantment may be applied to, from the
    /// nearest link in the base chain. Carried for inspection only; see the file
    /// header for why it gates nothing here.
    public let wornRestriction: FormID?

    /// The effects a worn item grants for as long as it is worn.
    public var isWorn: Bool {
        castingType == .constantEffect
    }

    /// The effects a landed hit delivers. Contact delivery, which is the only
    /// delivery a weapon enchantment has.
    public var isContact: Bool {
        delivery == .touch && !isWorn
    }

    /// Whether this is a staff enchantment, which neither of the two paths above
    /// carries out.
    public var isStaff: Bool {
        type == .staffEnchantment
    }

    /// A fully charged reading, which is what an item nothing has spent yet
    /// reads.
    public var fullCharge: EnchantmentCharge {
        EnchantmentCharge(capacity: capacity, costPerUse: costPerUse)
    }

    /// The charge with `remaining` left of it.
    public func charge(remaining: Float) -> EnchantmentCharge {
        EnchantmentCharge(capacity: capacity, remaining: remaining, costPerUse: costPerUse)
    }

    /// What the applied effects are sourced to.
    public var source: ActiveEffectSource {
        ActiveEffectSource(kind: .enchantment, record: enchantment)
    }

    /// Whether `keywords` satisfies the worn restriction: true when there is none,
    /// the list is empty, or the item has a listed keyword.
    /// - Parameter listedKeywords: the resolved `wornRestriction` list, or nil when
    ///   it could not be resolved, which allows everything.
    public func allowsWearing(keywords: [FormID], listedKeywords: [FormID]?) -> Bool {
        guard let listedKeywords, !listedKeywords.isEmpty else { return true }
        let carried = Set(keywords.map(\.rawValue))
        return listedKeywords.contains { carried.contains($0.rawValue) }
    }
}

nonisolated extension ItemEnchantmentProfile {
    /// Resolves one carried item's enchantment, or nil when it has none or its
    /// `EITM` does not resolve.
    /// - Parameters:
    ///   - definition: the item view with the resolved enchantment and `EAMT` charge.
    ///   - store: the ENCH store with effects, cost, and the base chain.
    public static func resolve(
        _ definition: ItemDefinition,
        using store: EnchantmentStore
    ) -> ItemEnchantmentProfile? {
        guard
            let link = definition.enchantment,
            let resolvedID = link.resolvedID,
            let resolved = store.enchantment(resolvedID)
        else { return nil }
        return ItemEnchantmentProfile(
            item: definition.formID,
            enchantment: ReferenceKey(resolved: resolved.id),
            sourcePlugin: resolved.sourcePlugin,
            entries: resolved.record.effects,
            name: resolved.displayName,
            castingType: resolved.data?.castingType ?? .fireAndForget,
            delivery: resolved.data?.delivery ?? .touch,
            type: resolved.data?.type ?? .enchantment,
            capacity: Float(link.charge ?? 0),
            costPerUse: Float(resolved.cost.cost),
            wornRestriction: store.baseChain(of: resolved.id)
                .lazy
                .compactMap { $0.data?.wornRestrictions }
                .first
        )
    }
}
