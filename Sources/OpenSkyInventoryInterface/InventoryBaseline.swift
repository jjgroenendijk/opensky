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
    /// What each item occupies, which picks the carried items an NPC equips.
    public var equipment = EquipmentCatalog(items: [:])
    /// CSTY records, whose Equipment Score Mults pick a carried weapon.
    public var combatStyles: [UInt32: CombatStyle] = [:]
    /// LVLI, OTFT, and CSTY records that failed to decode.
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
        resolver.combatStyles = loadOrder.indexRecords(of: "CSTY", skipped: &skipped) {
            try CombatStyle(record: $0)
        }
        resolver.skippedRecords = skipped
        resolver.equipment = EquipmentCatalog.build(from: loadOrder)
        return resolver
    }

    /// The roll every leveled entry goes through, shared with the actor walk.
    public var leveling: LeveledListRoller {
        actors.leveling
    }

    /// `owner`'s inventory as plugin data describes it, with no runtime state
    /// applied, rolled for the base record. A placed owner goes through `baseline(of:)`.
    public func baseline(for owner: InventoryOwner) -> ReferenceInventoryState {
        switch owner {
        case .player:
            actorBaseline(Self.playerBase, templates: actors)
        case .generated:
            .empty
        case let .container(base):
            containerBaseline(base, roll: leveling.roll(forActor: base))
        case let .actor(base):
            actorBaseline(base, templates: actors)
        }
    }

    /// The same baseline for a placed owner, rolled by its own key at the player level
    /// its cell froze, so two chests or two bandits of one base differ.
    public func baseline(of holder: InventoryHolder, frozenLevel: Int?) -> ReferenceInventoryState {
        guard let roll = roll(of: holder, frozenLevel: frozenLevel) else {
            return baseline(for: holder.owner)
        }
        switch holder.owner {
        case let .container(base): return containerBaseline(base, roll: roll)
        case let .actor(base): return actorBaseline(base, templates: actors.rolling(roll))
        case .player, .generated: return baseline(for: holder.owner)
        }
    }

    /// A placed actor's or container's roll. Nil for the player and a generated owner,
    /// which roll for their base.
    public func roll(of holder: InventoryHolder, frozenLevel: Int?) -> LeveledRoll? {
        switch holder.owner {
        case let .actor(base):
            leveling.roll(
                for: holder.key, base: base, cell: holder.cell, frozenLevel: frozenLevel
            )
        case .container:
            leveling.roll(for: holder.key, base: nil, cell: holder.cell, frozenLevel: frozenLevel)
        case .player, .generated:
            nil
        }
    }

    /// Whether `owner`'s records roll a leveled list: a leveled template, or an outfit,
    /// carried item, spell, or container entry that names one. Only such an owner
    /// freezes a level.
    public func rollsLeveledLists(_ owner: InventoryOwner) -> Bool {
        switch owner {
        case let .container(base):
            return items.container(base)?.entries.contains { isLeveled($0.item) } ?? false
        case let .actor(base):
            guard let resolved = try? actors.resolve(base: base) else { return false }
            let hasLeveledHop = resolved.chain.contains {
                if case .leveled = $0 {
                    true
                } else {
                    false
                }
            }
            let outfit = resolved.defaultOutfit.value.flatMap { outfits[$0.rawValue] }?.items
            let carried = (try? actors.resolveCarriedItems(base: base).value)?.map(\.item)
            let spells = (try? actors.resolveSpells(base: base).spells.value) ?? []
            return hasLeveledHop || ((outfit ?? []) + (carried ?? [])).contains(where: isLeveled)
                || spells.contains { actors.leveledSpells[$0.rawValue] != nil }
        case .player, .generated:
            return false
        }
    }

    private func isLeveled(_ item: FormID) -> Bool {
        leveledItems[item.rawValue] != nil
    }

    // MARK: - Per-owner derivation

    /// A container's CNTO list, leveled entries expanded. Nothing is equipped:
    /// a chest wears nothing.
    private func containerBaseline(_ base: FormID, roll: LeveledRoll) -> ReferenceInventoryState {
        guard let container = items.container(base) else { return .empty }
        var stacks: [InventoryStack] = []
        for entry in container.entries {
            // A CNTO count of zero or less is left to
            // `ReferenceInventoryState.init` to drop, which it does for every
            // non-positive stack however it was produced.
            expand(entry.item, count: entry.count, roll: Roll(roll), into: &stacks)
        }
        return ReferenceInventoryState(stacks: stacks)
    }

    /// An actor's carried `CNTO` items plus its default outfit. The baseline equipped
    /// set is the outfit plus the carried items `carriedPicks` chooses, so an NPC does
    /// not start naked or empty-handed. A broken template chain yields an empty
    /// baseline; the appearance path already reports it.
    private func actorBaseline(
        _ base: FormID, templates: ActorTemplateResolver
    ) -> ReferenceInventoryState {
        guard let resolved = try? templates.resolve(base: base) else { return .empty }
        let roll = templates.roll(for: base)
        let worn = resolved.defaultOutfit.value.flatMap { outfitStacks($0, roll: roll) } ?? []
        var carriedStacks: [InventoryStack] = []
        let carried = (try? templates.resolveCarriedItems(base: base).value) ?? []
        for entry in carried {
            expand(entry.item, count: entry.count, roll: Roll(roll), into: &carriedStacks)
        }
        let outfit = worn.map(\.item)
        let style = (try? templates.resolveCombatStyle(base: base))?.value
        let picks = equipment.carriedPicks(
            worn: outfit,
            carried: carriedStacks.filter { $0.count >= 1 }.map(\.item),
            preference: style.flatMap { combatStyles[$0.rawValue] }
                .map(WeaponPreference.init(style:))
        )
        return ReferenceInventoryState(stacks: worn + carriedStacks, equipped: outfit + picks)
    }

    /// One of each `OTFT` item, leveled entries rolled by `roll`, as
    /// `ActorVisualResolver` rolls them. Nil when no outfit has the ID.
    public func outfitStacks(_ outfitID: FormID, roll: LeveledRoll) -> [InventoryStack]? {
        guard let outfit = outfits[outfitID.rawValue] else { return nil }
        var stacks: [InventoryStack] = []
        for item in outfit.items {
            expand(item, count: 1, roll: Roll(roll), into: &stacks)
        }
        return ReferenceInventoryState(stacks: stacks).stacks
    }

    /// The death item an actor gets when it dies, its template chain walked by `roll`
    /// and its list rolled at the actor's own `level` (CK "LeveledItem").
    public func deathItemStacks(
        for base: FormID, roll: LeveledRoll, level: Int
    ) -> [InventoryStack] {
        let templates = actors.rolling(roll)
        guard let item = (try? templates.resolveDeathItem(base: base))?.value else { return [] }
        return expanded(item, count: 1, request: leveling.request(atLevel: level), seed: roll.seed)
    }

    // MARK: - Leveled expansion

    /// One owner's leveled request and the seed its lists roll by.
    private struct Roll {
        let request: LeveledRequest
        let seed: UInt64

        init(request: LeveledRequest, seed: UInt64) {
            self.request = request
            self.seed = seed
        }

        init(_ roll: LeveledRoll) {
            self.init(request: roll.request, seed: roll.seed)
        }
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
