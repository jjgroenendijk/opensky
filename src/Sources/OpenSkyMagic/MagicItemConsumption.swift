// Consuming a magic item: drinking a potion or eating an ingredient. The
// inventory half of `ActiveEffectRuntime`. Eating an ingredient applies only its
// first effect (<https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>).
// See docs/engine/magic.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface

/// What consuming one item applies.
nonisolated public struct MagicItemUse: Equatable, Sendable {
    /// Which source kind the resulting effects are attributed to.
    public let kind: ActiveEffectSourceKind
    /// The effect entries one unit applies, already narrowed by the ingredient
    /// rule where it applies.
    public let effects: [MagicItemEffect]
}

/// Why a consume attempt did nothing.
nonisolated public enum MagicItemConsumeError: Equatable, Error {
    /// The item is not an ALCH or an INGR, or no loaded plugin describes it.
    case notConsumable(FormID)
    /// The holder carries none of it.
    case noneCarried(FormID)
}

extension ActiveEffectRuntime {
    /// Removes one unit of `item` from `holder` and applies its effects, after
    /// `scaling`, to `target`.
    /// A consume that applies nothing still costs the unit, as in the game.
    /// - Throws: `MagicItemConsumeError`, plus `InventoryRuntime` removal errors.
    @discardableResult
    public mutating func consume(
        _ item: FormID,
        use: (from: InventoryHolder, on: ActorValueHolder),
        inventory: any InventoryAccess,
        fromPlugin pluginName: String,
        scaling: ([MagicItemEffect], ReferenceKey) -> [MagicItemEffect] = { entries, _ in entries }
    ) throws -> MagicItemConsumeOutcome {
        let (holder, target) = use
        let (kind, entries) = try inventory.takeMagicItem(item, from: holder)
        let source = ActiveEffectSource(
            kind: kind, record: effects.sourceKey(of: item, fallbackPlugin: pluginName)
        )
        let stored = apply(
            scaling(entries, source.record),
            fromPlugin: pluginName,
            source: source,
            on: target
        )
        return MagicItemConsumeOutcome(kind: kind, entryCount: entries.count, stored: stored)
    }
}

nonisolated extension MagicEffectStore {
    /// The plugin that defines `item`, which sits in the load-order FormID space.
    func sourceKey(of item: FormID, fallbackPlugin pluginName: String) -> ReferenceKey {
        resolvedID(item, fromPlugin: FormIDResolver.loadOrderSpaceName)
            .map(ReferenceKey.init(resolved:))
            ?? .plugin(name: pluginName.lowercased(), objectID: item.objectID)
    }
}

extension InventoryAccess {
    /// Removes one unit of a potion or ingredient and returns what it applies.
    /// - Throws: `MagicItemConsumeError`, plus the inventory's removal errors.
    func takeMagicItem(
        _ item: FormID, from holder: InventoryHolder
    ) throws -> (kind: ActiveEffectSourceKind, effects: [MagicItemEffect]) {
        guard let use = baselines.items.magicItemUse(item) else {
            throw MagicItemConsumeError.notConsumable(item)
        }
        guard count(of: item, in: holder) > 0 else {
            throw MagicItemConsumeError.noneCarried(item)
        }
        try remove(item, count: 1, from: holder)
        return (use.kind, use.effects)
    }
}
