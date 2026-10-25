// What an owner holds before runtime changes: a container's CNTO list, and an
// actor's carried items and default outfit. Baselines are re-derived on every
// call, so a reset restores what the records say now. Leveled entries roll
// through the shared `LeveledListRoller`, seeded by the owner.
// See docs/engine/inventory-state.md and docs/engine/leveled-lists.md.

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
    /// The `Player` NPC_ record, whose outfit the player's body wears.
    public static let playerBase = FormID(0x7)

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

    public static func build(
        from file: ESMFile,
        enchantments: ItemEnchantmentResolver? = nil,
        strings: LocalizedStrings? = nil
    ) -> InventoryBaselineResolver {
        build(from: LoadOrderPlugins(file: file), enchantments: enchantments, strings: strings)
    }

    /// Builds every index over the load order, keyed by load-order FormID.
    /// - Parameter enchantments: the load-order ENCH view `EITM` links resolve
    ///   through. Nil leaves every `resolvedID` nil, as in a synthetic session.
    /// - Parameter strings: the tables item names resolve through. Nil keeps
    ///   string IDs, so a row falls back to the editor ID.
    public static func build(
        from loadOrder: LoadOrderPlugins,
        leveling: LeveledListRoller = LeveledListRoller(),
        enchantments: ItemEnchantmentResolver? = nil,
        strings: LocalizedStrings? = nil
    ) -> InventoryBaselineResolver {
        var skipped = SkippedRecords()
        var resolver = InventoryBaselineResolver(
            items: ItemDefinitionStore(
                loadOrder: loadOrder, enchantments: enchantments, strings: strings
            ),
            leveledItems: loadOrder.indexRecords(of: "LVLI", skipped: &skipped) {
                try LeveledList(record: $0)
            },
            outfits: loadOrder.indexRecords(of: "OTFT", skipped: &skipped) {
                try Outfit(record: $0)
            },
            actors: ActorTemplateResolver.build(from: loadOrder, leveling: leveling)
        )
        resolver.skippedRecords = skipped
        return resolver
    }

    /// The roll every leveled entry goes through, shared with the actor walk.
    public var leveling: LeveledListRoller {
        actors.leveling
    }

    /// `owner`'s inventory as plugin data describes it, with no runtime state
    /// applied. An owner nothing has touched resolves through here every time.
    public func baseline(for owner: InventoryOwner) -> ReferenceInventoryState {
        switch owner {
        case .player:
            actorBaseline(Self.playerBase)
        case .generated:
            .empty
        case let .container(base):
            containerBaseline(base, seed: UInt64(base.rawValue), cell: nil)
        case let .actor(base):
            actorBaseline(base)
        }
    }

    /// The same baseline for a placed owner. A container rolls by its own key and
    /// at its cell's encounter level, so two chests of one base differ.
    public func baseline(of holder: InventoryHolder) -> ReferenceInventoryState {
        guard case let .container(base) = holder.owner else { return baseline(for: holder.owner) }
        return containerBaseline(
            base, seed: LeveledListRoll.seed(text: holder.key.description), cell: holder.cell
        )
    }

    // MARK: - Per-owner derivation

    /// A container's CNTO list, leveled entries expanded. Nothing is equipped:
    /// a chest wears nothing.
    private func containerBaseline(
        _ base: FormID, seed: UInt64, cell: CellSceneLocation?
    ) -> ReferenceInventoryState {
        guard let container = items.container(base) else { return .empty }
        let roll = Roll(request: leveling.request(forCell: cell), seed: seed)
        var stacks: [InventoryStack] = []
        for entry in container.entries {
            // A CNTO count of zero or less is left to
            // `ReferenceInventoryState.init` to drop, which it does for every
            // non-positive stack however it was produced.
            expand(entry.item, count: entry.count, roll: roll, into: &stacks)
        }
        return ReferenceInventoryState(stacks: stacks)
    }

    /// An actor's carried `CNTO` items plus its default outfit. The outfit is also
    /// its baseline equipped set, so an NPC does not start naked. A broken template
    /// chain yields an empty baseline; the appearance path already reports it.
    private func actorBaseline(_ base: FormID) -> ReferenceInventoryState {
        guard let resolved = try? actors.resolve(base: base) else { return .empty }
        let worn = resolved.defaultOutfit.value.flatMap { outfitStacks($0, for: base) } ?? []
        var stacks = worn
        let carried = (try? actors.resolveCarriedItems(base: base).value) ?? []
        let roll = Roll(request: leveling.request(forActor: base), seed: UInt64(base.rawValue))
        for entry in carried {
            expand(entry.item, count: entry.count, roll: roll, into: &stacks)
        }
        return ReferenceInventoryState(stacks: stacks, equipped: worn.map(\.item))
    }

    /// The actor base whose rolls an owner's outfit takes. Nil for a container.
    public static func actorBase(of owner: InventoryOwner) -> FormID? {
        switch owner {
        case .player: playerBase
        case let .actor(base): base
        case .container, .generated: nil
        }
    }

    /// One of each `OTFT` item, leveled entries rolled for the actor `base`, as
    /// `ActorVisualResolver` rolls them. Nil when no outfit has the ID.
    public func outfitStacks(_ outfitID: FormID, for base: FormID) -> [InventoryStack]? {
        guard let outfit = outfits[outfitID.rawValue] else { return nil }
        let roll = Roll(request: leveling.request(forActor: base), seed: UInt64(base.rawValue))
        var stacks: [InventoryStack] = []
        for item in outfit.items {
            expand(item, count: 1, roll: roll, into: &stacks)
        }
        return ReferenceInventoryState(stacks: stacks).stacks
    }

    /// The death item an actor of `base` gets when it dies, rolled at its own `level`
    /// (CK "LeveledItem"). Empty when the actor has none or the roll gives nothing.
    public func deathItemStacks(for base: FormID, level: Int, seed: UInt64) -> [InventoryStack] {
        guard let item = (try? actors.resolveDeathItem(base: base))?.value else { return [] }
        return expanded(item, count: 1, request: leveling.request(atLevel: level), seed: seed)
    }

    // MARK: - Leveled expansion

    /// One owner's leveled request and the seed its lists roll by.
    private struct Roll {
        let request: LeveledRequest
        let seed: UInt64
    }

    /// `id` as stacks: itself, or its leveled roll at `request` when it names an LVLI.
    public func expanded(
        _ id: FormID, count: Int32, request: LeveledRequest, seed: UInt64
    ) -> [InventoryStack] {
        var stacks: [InventoryStack] = []
        expand(id, count: count, roll: Roll(request: request, seed: seed), into: &stacks)
        return ReferenceInventoryState(stacks: stacks).stacks
    }

    /// Appends `id` to `stacks`, expanding it first when it names a leveled
    /// list. `ReferenceInventoryState.init` merges the duplicates this can
    /// produce, so an entry reached twice through different lists stacks
    /// instead of appearing twice.
    private func expand(
        _ id: FormID,
        count: Int32,
        roll: Roll,
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
        let picks = leveling.roll(list, count: count, request: roll.request, seed: roll.seed)
        for pick in picks {
            expand(
                pick.entry.reference,
                count: pick.count,
                roll: roll,
                into: &stacks,
                depth: depth + 1,
                visiting: visited
            )
        }
    }
}
