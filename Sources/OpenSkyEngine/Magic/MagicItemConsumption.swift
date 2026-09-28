// Consuming a magic item (issue #469, roadmap item 19.6): the first consumer of
// the active-effect runtime — drinking a potion and eating an ingredient.
//
// A satellite of `ActiveEffectRuntime.swift` rather than more of it: that file
// owns applying, ticking and dispelling an already-resolved effect, and this one
// owns the inventory half — which record family an item belongs to, how many of
// it there are, and what "one unit" means. The two are separate because casting
// (issues 19.7 and 19.8) reaches the first without going anywhere near the
// second.
//
// ## The ingredient rule
//
// Eating a raw ingredient applies its *first* effect only. UESP's "Skyrim:
// Alchemy Effects" states it: "Ingredients listed in bold have that effect as
// their first, meaning that eating a sample of that ingredient will provide a
// small version of that effect."
// <https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>
//
// The Alchemy skill's Experimenter perk changes how many effects eating
// *reveals*, which is discovery state rather than application, and belongs to
// the alchemy milestone rather than here.
//
// Documented in docs/engine/magic.md.

import Foundation

/// What consuming one item applies.
nonisolated struct MagicItemUse: Equatable {
    let item: FormID
    /// Which source kind the resulting effects are attributed to.
    let kind: ActiveEffectSourceKind
    /// The effect entries one unit applies, already narrowed by the ingredient
    /// rule where it applies.
    let effects: [MagicItemEffect]
    /// ALCH ENIT's consume sound, for the milestone that plays it.
    let consumeSound: FormID?
}

/// Why a consume attempt did nothing.
nonisolated enum MagicItemConsumeError: Equatable, Error {
    /// The item is not an ALCH or an INGR, or no loaded plugin describes it.
    case notConsumable(FormID)
    /// The holder carries none of it.
    case noneCarried(FormID)
}

/// What one successful consume did.
nonisolated struct MagicItemConsumeOutcome: Equatable {
    let item: FormID
    let kind: ActiveEffectSourceKind
    /// Effect entries handed to the runtime — not all of which necessarily
    /// applied; the runtime's tally says which did not and why.
    let entryCount: Int
    /// The timed effects that became components. Instant effects moved a value
    /// and are not here, by design.
    let stored: [ActiveEffect]
}

extension ActiveEffectRuntime {
    /// Removes one unit of `item` from `holder` and applies what it does to
    /// `target`.
    ///
    /// The removal happens first and only on success, so a consume that cannot
    /// find the item applies nothing and a consume that applies nothing still
    /// costs the unit — which is what drinking a potion of an effect this
    /// engine has not implemented does in the original game.
    ///
    /// - Throws: `MagicItemConsumeError`, plus whatever `InventoryRuntime`
    ///   throws when the removal fails.
    @discardableResult
    mutating func consume(
        _ item: FormID,
        from holder: InventoryHolder,
        on target: ActorValueHolder,
        inventory: InventoryRuntime,
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
            item: item,
            kind: use.kind,
            entryCount: use.effects.count,
            stored: stored
        )
    }
}
