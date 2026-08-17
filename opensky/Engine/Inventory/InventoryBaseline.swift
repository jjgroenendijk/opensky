// Inventory baselines (issue #176, roadmap item 12.1.2): what an owner holds
// before anything at runtime has touched it.
//
// Baselines are never stored, exactly as `ReferenceState` never stores a
// placement baseline. They are re-derived from plugin data on every call, so a
// reset genuinely restores whatever the records now say and a reloaded plugin
// cannot leave a stale copy behind. The runtime component
// (`ReferenceInventoryState`) only exists once a mutation has materialized one
// of these into it.
//
// Three baseline sources, one per owner kind:
//
// * A container's baseline is its CONT `CNTO` list (#175), expanded through
//   leveled lists.
// * An actor's baseline is the default outfit its resolved template chain
//   provides. `ActorTemplateResolver` already follows TPLT links and the ACBS
//   `useInventory` flag, so this reuses that resolution rather than repeating
//   it.
// * The player's baseline is empty. No record describes the player in this
//   engine (see `ReferenceKey.player`), so there is nothing to derive from.
//
// Approximations recorded for v1, all of them narrowing rather than wrong:
//
// * Leveled entries resolve deterministically, through
//   `LeveledList.deterministicEntry` and the `useAll` bundle flag — the same
//   policy the bind-pose milestone already uses for LVLN. Rolling against
//   player level and chance-none needs a player level, which no milestone has
//   yet; when it arrives it replaces `expand` alone and nothing else here
//   changes.
// * `chanceNone` is ignored, because ignoring it can only ever place an item
//   the list might have skipped, and an empty container is the harder failure
//   to notice.
// * NPC_ does not decode a `CNTO` list yet (`ActorBase` reads the appearance
//   and template fields only), so an actor's baseline is its outfit and not
//   the loot it also carries.
// * A form that resolves to neither an indexed item nor a leveled list is kept
//   as a plain stack rather than dropped. It is genuinely in the container; it
//   simply carries no weight or value here, because no loaded plugin index
//   describes it.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// Which plugin record an owner's baseline comes from.
///
/// A `ReferenceKey` alone cannot answer this: the store keys state by identity
/// and knows nothing about record types, so the caller that has the placement
/// says which kind of owner it is holding.
nonisolated enum InventoryOwner: Equatable, Sendable {
    /// The player, whose baseline is empty.
    case player
    /// A placed CONT, identified by its base record.
    case container(base: FormID)
    /// A placed ACHR, identified by its NPC_ base record.
    case actor(base: FormID)
    /// An owner with no plugin baseline at all — a runtime-created object such
    /// as a dropped-item pile (#177) or a summon.
    case generated
}

/// Re-derives inventory baselines from plugin data.
///
/// Immutable and buildable once per load order, matching the `*Store`
/// convention (`WeatherStore`, `ItemDefinitionStore`): nothing here mutates
/// after `init`, so it is freely readable from the cell-build queue.
nonisolated struct InventoryBaselineResolver {
    /// Deepest leveled-list nesting followed before expansion gives up. A list
    /// that points at itself is caught by the visited set; this cap catches the
    /// long chain that is technically acyclic and still nonsense.
    static let maximumLeveledDepth = 8

    /// Item and container index from #175.
    let items: ItemDefinitionStore
    /// LVLI decodes by raw FormID. Kept here rather than in
    /// `ItemDefinitionStore` because a leveled list is not a carryable item and
    /// has neither a value nor a weight to expose through `ItemDefinition`.
    let leveledItems: [UInt32: LeveledList]
    /// OTFT decodes by raw FormID.
    let outfits: [UInt32: Outfit]
    /// Template-chain resolution, which supplies `defaultOutfit`.
    let actors: ActorTemplateResolver

    /// Builds every index this resolver needs from one plugin.
    ///
    /// Single-plugin and raw-FormID keyed, matching `ItemDefinitionStore` and
    /// the actor resolution indexes. Cross-plugin override resolution is a
    /// separate concern and is not needed until inventory reads more than
    /// `Skyrim.esm`.
    /// - Parameter enchantments: the load-order ENCH view every `EITM` link is
    ///   resolved through (issue #466), already paired with the plugin those
    ///   links are relative to. Nil leaves every enchanted item's `resolvedID`
    ///   nil, and then nothing can apply an enchantment at runtime (issue #472) —
    ///   which is what a synthetic session means.
    static func build(
        from file: ESMFile,
        enchantments: ItemEnchantmentResolver? = nil
    ) -> InventoryBaselineResolver {
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        return InventoryBaselineResolver(
            items: ItemDefinitionStore(file: file, enchantments: enchantments),
            leveledItems: index(file, "LVLI") { try LeveledList(record: $0) },
            outfits: index(file, "OTFT") { try Outfit(record: $0) },
            actors: ActorTemplateResolver.build(from: file, localized: localized)
        )
    }

    /// `owner`'s inventory as plugin data describes it, with no runtime state
    /// applied. An owner nothing has touched resolves through here every time.
    func baseline(for owner: InventoryOwner) -> ReferenceInventoryState {
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

    /// An actor's default outfit, one of each piece, leveled entries expanded.
    ///
    /// The outfit is also the baseline equipped set: "default outfit" is by
    /// definition what the actor is wearing when the game starts it, so
    /// baselining it as carried-but-unworn would make every NPC start naked.
    /// Which slot each piece occupies, and what happens when two pieces claim
    /// the same one, is issue #178.
    ///
    /// A broken template chain — a dangling TPLT, a cycle, an empty LVLN —
    /// resolves to an empty baseline rather than propagating. This is runtime
    /// state, not parsing; an actor whose chain does not resolve has no
    /// appearance either, and the appearance path already reports that.
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

    // MARK: - Indexing

    /// Decodes every record of one top group into a raw-FormID map, dropping
    /// the ones that throw. Matches the indexing helper shape the actor
    /// resolution builders already use.
    private static func index<Value>(
        _ file: ESMFile,
        _ type: FourCC,
        _ decode: (ESMRecord) throws -> Value
    ) -> [UInt32: Value] {
        guard let group = file.topGroup(of: type), let children = try? group.children() else {
            return [:]
        }
        var result: [UInt32: Value] = [:]
        for case let .record(record) in children {
            guard record.type == type, !record.isDeleted else { continue }
            result[record.formID] = try? decode(record)
        }
        return result
    }
}
