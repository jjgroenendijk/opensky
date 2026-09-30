// Consuming a magic item: drinking a potion or eating an ingredient. The
// inventory half of `ActiveEffectRuntime`. Eating an ingredient applies only its
// first effect (<https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>).
// See docs/engine/magic.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

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

/// What one successful consume did.
nonisolated public struct MagicItemConsumeOutcome: Equatable, Sendable {
    public let kind: ActiveEffectSourceKind
    /// Effect entries handed to the runtime — not all of which necessarily
    /// applied; the runtime's tally says which did not and why.
    public let entryCount: Int
    /// The timed effects that became components. Instant effects moved a value
    /// and are not here, by design.
    public let stored: [ActiveEffect]
}

extension ActiveEffectRuntime {
    /// Removes one unit of `item` from `holder` and applies its effects to `target`.
    /// A consume that applies nothing still costs the unit, as in the game.
    /// - Throws: `MagicItemConsumeError`, plus `InventoryRuntime` removal errors.
    @discardableResult
    public mutating func consume(
        _ item: FormID,
        from holder: InventoryHolder,
        on target: ActorValueHolder,
        inventory: any InventoryAccess,
        fromPlugin pluginName: String
    ) throws -> MagicItemConsumeOutcome {
        guard let use = inventory.baselines.items.magicItemUse(item) else {
            throw MagicItemConsumeError.notConsumable(item)
        }
        guard inventory.count(of: item, in: holder) > 0 else {
            throw MagicItemConsumeError.noneCarried(item)
        }
        try inventory.remove(item, count: 1, from: holder)
        let stored = apply(
            use.effects,
            fromPlugin: pluginName,
            source: ActiveEffectSource(kind: use.kind, record: ReferenceKey.plugin(
                name: pluginName.lowercased(),
                objectID: item.objectID
            )),
            on: target
        )
        return MagicItemConsumeOutcome(
            kind: use.kind,
            entryCount: use.effects.count,
            stored: stored
        )
    }
}
