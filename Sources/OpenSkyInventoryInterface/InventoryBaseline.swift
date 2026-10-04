// What an owner holds before runtime changes: a container's CNTO list, an
// actor's resolved default outfit, and nothing for the player. Baselines are
// re-derived on every call, so a reset restores what the records say now.
// Leveled entries resolve deterministically and `chanceNone` is ignored.
// Documented in docs/engine/inventory-state.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

/// Re-derives inventory baselines from plugin data.
///
/// Immutable and buildable once per load order, matching the `*Store`
/// convention (`WeatherStore`, `ItemDefinitionStore`): nothing here mutates
/// after `init`, so it is freely readable from the cell-build queue.
nonisolated public struct InventoryBaselineResolver {
    /// Deepest leveled-list nesting followed before expansion gives up. A list
    /// that points at itself is caught by the visited set; this cap catches the
    /// long chain that is technically acyclic and still nonsense.
    public static let maximumLeveledDepth = 8

    /// Item and container index.
    public let items: ItemDefinitionStore
    /// LVLI decodes by raw FormID. Kept here rather than in
    /// `ItemDefinitionStore` because a leveled list is not a carryable item and
    /// has neither a value nor a weight to expose through `ItemDefinition`.
    public let leveledItems: [UInt32: LeveledList]
    /// OTFT decodes by raw FormID.
    public let outfits: [UInt32: Outfit]
    /// Template-chain resolution, which supplies `defaultOutfit`.
    public let actors: ActorTemplateResolver
    /// LVLI and OTFT records that failed to decode.
    public private(set) var skippedRecords = SkippedRecords()

    /// Builds every index from one plugin, keyed by raw FormID.
    /// - Parameter enchantments: the load-order ENCH view `EITM` links resolve
    ///   through. Nil leaves every `resolvedID` nil, as in a synthetic session.
    /// - Parameter strings: the tables item names resolve through. Nil keeps
    ///   string IDs, so a row falls back to the editor ID.
    public static func build(
        from file: ESMFile,
        enchantments: ItemEnchantmentResolver? = nil,
        strings: LocalizedStrings? = nil
    ) -> InventoryBaselineResolver {
        let localized = file.isLocalized
        var skipped = SkippedRecords()
        var resolver = InventoryBaselineResolver(
            items: ItemDefinitionStore(file: file, enchantments: enchantments, strings: strings),
            leveledItems: file.indexRecords(of: "LVLI", skipped: &skipped) {
                try LeveledList(record: $0)
            },
            outfits: file.indexRecords(of: "OTFT", skipped: &skipped) { try Outfit(record: $0) },
            actors: ActorTemplateResolver.build(from: file, localized: localized)
        )
        resolver.skippedRecords = skipped
        return resolver
    }

    /// `owner`'s inventory as plugin data describes it, with no runtime state
    /// applied. An owner nothing has touched resolves through here every time.
    public func baseline(for owner: InventoryOwner) -> ReferenceInventoryState {
        switch owner {
        case .player, .generated:
            .empty
        case let .container(base):
            containerBaseline(base)
        case let .actor(base):
            actorBaseline(base)
        }
    }

    // MARK: - Per-owner derivation

    /// A container's CNTO list, leveled entries expanded. Nothing is equipped:
    /// a chest wears nothing.
    private func containerBaseline(_ base: FormID) -> ReferenceInventoryState {
        guard let container = items.container(base) else { return .empty }
        var stacks: [InventoryStack] = []
        for entry in container.entries {
            // A CNTO count of zero or less is left to
            // `ReferenceInventoryState.init` to drop, which it does for every
            // non-positive stack however it was produced.
            expand(entry.item, count: entry.count, into: &stacks)
        }
        return ReferenceInventoryState(stacks: stacks)
    }

    /// An actor's default outfit, also its baseline equipped set, so an NPC does
    /// not start naked. A broken template chain yields an empty baseline; the
    /// appearance path already reports it.
    private func actorBaseline(_ base: FormID) -> ReferenceInventoryState {
        guard
            let resolved = try? actors.resolve(base: base),
            let outfitID = resolved.defaultOutfit.value,
            let outfit = outfits[outfitID.rawValue]
        else { return .empty }
        var stacks: [InventoryStack] = []
        for item in outfit.items {
            expand(item, count: 1, into: &stacks)
        }
        return ReferenceInventoryState(stacks: stacks, equipped: stacks.map(\.item))
    }

    // MARK: - Leveled expansion

    /// `id` as stacks: itself, or its deterministic leveled pick when it names an LVLI.
    public func expanded(_ id: FormID, count: Int32) -> [InventoryStack] {
        var stacks: [InventoryStack] = []
        expand(id, count: count, into: &stacks)
        return ReferenceInventoryState(stacks: stacks).stacks
    }

    /// Appends `id` to `stacks`, expanding it first when it names a leveled
    /// list. `ReferenceInventoryState.init` merges the duplicates this can
    /// produce, so an entry reached twice through different lists stacks
    /// instead of appearing twice.
    private func expand(
        _ id: FormID,
        count: Int32,
        into stacks: inout [InventoryStack],
        depth: Int = 0,
        visiting: Set<UInt32> = []
    ) {
        guard
            depth < Self.maximumLeveledDepth,
            let list = leveledItems[id.rawValue],
            !visiting.contains(id.rawValue)
        else {
            stacks.append(InventoryStack(item: id, count: count))
            return
        }
        var visited = visiting
        visited.insert(id.rawValue)
        for entry in chosenEntries(of: list) {
            let scaled = Int64(count) * Int64(max(entry.count, 1))
            expand(
                entry.reference,
                count: Int32(clamping: scaled),
                into: &stacks,
                depth: depth + 1,
                visiting: visited
            )
        }
    }

    /// The entries one list contributes: every entry for a `useAll` bundle
    /// (`ArmorStormcloakSet` is boots plus cuirass plus gauntlets plus helmet,
    /// not a choice between them), otherwise the single deterministic pick.
    private func chosenEntries(of list: LeveledList) -> [LeveledList.Entry] {
        if list.flags.contains(.useAll) {
            return list.entries
        }
        guard let entry = list.deterministicEntry else { return [] }
        return [entry]
    }
}
