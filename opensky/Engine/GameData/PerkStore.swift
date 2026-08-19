// Load-order-wide PERK lookup above RecordIndex, in the shape SpellStore and
// MagicEffectStore already use: winning record per identity, editor-ID lookup,
// and the joins a consumer would otherwise redo.
//
// Two joins beyond the usual. Ability effects and spell-selecting entry-point
// functions are resolved against `SpellStore`, so a caller reading a perk gets
// the spell record rather than a raw link. And every entry-point effect in the
// load order is collected into one index keyed by entry-point id, because the
// perk runtime (issue 20.4) asks "which perk effects hook Mod Attack Damage"
// once per formula evaluation and must not scan all 523 perks to answer.
//
// Owning perks on an actor, and evaluating an entry point's conditions, are
// issue 20.4 and deliberately absent here.

import Foundation

/// One effect of a perk, joined against the spell store.
nonisolated struct ResolvedPerkEffect {
    let effect: PerkEffect
    /// The SPEL an ability effect grants, or the one a "select spell" function
    /// casts. Nil when the effect names no spell or the link does not resolve.
    let spell: ResolvedSpell?

    var entryPoint: PerkEntryPoint? {
        effect.entryPoint
    }

    var spellName: String? {
        guard let raw = effect.spell else { return nil }
        return spell?.displayName ?? "[UNRESOLVED] \(raw)"
    }
}

nonisolated struct ResolvedPerk {
    let id: ResolvedFormID
    let record: Perk
    let sourcePlugin: String
    let effects: [ResolvedPerkEffect]
    /// NNAM resolved against the load order. Nil when the perk is the last
    /// rank or the link does not resolve.
    let nextPerk: ResolvedFormID?

    var editorID: String? {
        record.editorID
    }

    /// What the record's DATA declares, which is not the length of its rank
    /// chain — see `PerkHeaderData`. `PerkStore.rankChain(from:)` answers the
    /// real question.
    var declaredRankCount: UInt8 {
        record.declaredRankCount
    }

    var displayName: String {
        switch record.name {
        case let .inline(value): value
        case .tableID: record.editorID ?? id.description
        case nil: record.editorID ?? id.description
        }
    }
}

/// One entry-point hook, as the flat index holds it: enough to sort and filter
/// without touching the perk, plus the coordinates to fetch the effect.
nonisolated struct PerkEntryPointMatch: Equatable {
    let perk: ResolvedFormID
    /// Position of the effect inside `ResolvedPerk.effects`.
    let effectIndex: Int
    let entryPoint: PerkEntryPoint
    /// PRKE rank, counting from zero as the record stores it.
    let rank: UInt8
    let priority: UInt8
}

nonisolated struct PerkStore {
    /// Depth cap for a rank chain, so a mod-authored NNAM loop cannot hang a
    /// caller. Vanilla's longest chain is five ranks.
    private static let rankChainCap = 32

    private let index: RecordIndex
    /// Every winning PERK identity in the load order.
    private(set) var records: [ResolvedFormID: ResolvedPerk] = [:]
    /// Entry-point id to the effects that hook it, across every perk.
    private(set) var entryPointIndex: [UInt8: [PerkEntryPointMatch]] = [:]
    private var recordsByEditorID: [String: ResolvedPerk] = [:]
    private var recordsByKey: [ReferenceKey: ResolvedPerk] = [:]

    var perks: [ResolvedPerk] {
        Array(records.values)
    }

    /// How many effects hook each entry point, most-used first. What scopes
    /// which entry points the perk runtime has to implement.
    var entryPointHistogram: [(entryPoint: PerkEntryPoint, count: Int)] {
        entryPointIndex
            .map { (PerkEntryPoint(rawValue: $0.key), $0.value.count) }
            .sorted {
                $0.1 == $1.1 ? $0.0.rawValue < $1.0.rawValue : $0.1 > $1.1
            }
    }

    init(index: RecordIndex, spells: SpellStore) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "PERK" else { continue }
            guard
                case let .decoded(decoded, sourcePlugin) = index.decodeIndexed(
                    id,
                    using: Self.decode
                )
            else { continue }
            add(Self.join(
                id: id,
                record: decoded,
                sourcePlugin: sourcePlugin,
                index: index,
                spells: spells
            ))
        }
    }

    init(index: RecordIndex) {
        self.init(index: index, spells: SpellStore(index: index))
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(
            plugins: plugins,
            recordTypes: ["MGEF", "SPEL", "SCRL", "PERK"]
        ))
    }

    func perk(_ id: ResolvedFormID) -> ResolvedPerk? {
        records[id] ?? records.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    /// The perk one runtime identity names, which is what the perk runtime
    /// looks every stored key up through.
    func perk(key: ReferenceKey) -> ResolvedPerk? {
        recordsByKey[key]
    }

    func perk(editorID: String) -> ResolvedPerk? {
        recordsByEditorID[editorID.lowercased()]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedPerk? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return perk(resolvedID)
    }

    /// A perk link as text: its name when the load order carries it, and an
    /// explicit unresolved marker when it does not. What every dump that
    /// prints a perk link uses, so a missing record never looks like a name.
    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// Every effect hooking one entry point, ordered by the PRKE priority the
    /// records declare and then by identity so the answer is deterministic.
    func matches(at entryPoint: PerkEntryPoint) -> [PerkEntryPointMatch] {
        entryPointIndex[entryPoint.rawValue, default: []]
    }

    /// The effect one match names, or nil when the match came from a different
    /// store than the one being asked.
    func effect(_ match: PerkEntryPointMatch) -> ResolvedPerkEffect? {
        guard
            let perk = perk(match.perk),
            match.effectIndex < perk.effects.count
        else { return nil }
        return perk.effects[match.effectIndex]
    }

    /// The rank chain starting at `id`: the perk itself, then each perk its
    /// NNAM reaches. Stops on a repeat or at `rankChainCap`, so a mod-authored
    /// loop yields a short chain rather than hanging.
    func rankChain(from id: ResolvedFormID) -> [ResolvedPerk] {
        var chain: [ResolvedPerk] = []
        var seen: Set<ResolvedFormID> = []
        var next: ResolvedFormID? = id
        while let current = next, !seen.contains(current), chain.count < Self.rankChainCap {
            guard let resolved = perk(current) else { break }
            seen.insert(current)
            chain.append(resolved)
            next = resolved.nextPerk
        }
        return chain
    }

    private mutating func add(_ resolved: ResolvedPerk) {
        records[resolved.id] = resolved
        recordsByKey[ReferenceKey(resolved: resolved.id)] = resolved
        if let editorID = resolved.record.editorID {
            recordsByEditorID[editorID.lowercased()] = resolved
        }
        for (offset, effect) in resolved.effects.enumerated() {
            guard let entryPoint = effect.entryPoint else { continue }
            let match = PerkEntryPointMatch(
                perk: resolved.id,
                effectIndex: offset,
                entryPoint: entryPoint,
                rank: effect.effect.rank,
                priority: effect.effect.priority
            )
            var matches = entryPointIndex[entryPoint.rawValue, default: []]
            matches.append(match)
            matches.sort { Self.precedes($0, $1) }
            entryPointIndex[entryPoint.rawValue] = matches
        }
    }

    /// Higher priority first, then by owning perk and effect position, which
    /// is what keeps the index order stable across runs.
    private static func precedes(
        _ left: PerkEntryPointMatch,
        _ right: PerkEntryPointMatch
    ) -> Bool {
        if left.priority != right.priority {
            return left.priority > right.priority
        }
        if left.perk.plugin.caseInsensitiveCompare(right.perk.plugin) != .orderedSame {
            return left.perk.plugin.localizedCaseInsensitiveCompare(right.perk.plugin)
                == .orderedAscending
        }
        if left.perk.objectID != right.perk.objectID {
            return left.perk.objectID < right.perk.objectID
        }
        return left.effectIndex < right.effectIndex
    }

    private static func join(
        id: ResolvedFormID,
        record: Perk,
        sourcePlugin: String,
        index: RecordIndex,
        spells: SpellStore
    ) -> ResolvedPerk {
        let effects = record.effects.map { effect in
            ResolvedPerkEffect(
                effect: effect,
                spell: effect.spell.flatMap {
                    spells.resolve($0, fromPlugin: sourcePlugin)
                }
            )
        }
        let nextPerk = record.nextPerk.flatMap { link -> ResolvedFormID? in
            guard case let .resolved(resolved) = index.resolve(link, fromPlugin: sourcePlugin)
            else { return nil }
            return resolved
        }
        return ResolvedPerk(
            id: id,
            record: record,
            sourcePlugin: sourcePlugin,
            effects: effects,
            nextPerk: nextPerk
        )
    }

    private static func decode(_ indexed: IndexedRecord) throws -> Perk {
        try Perk(record: indexed.record, localized: indexed.localized)
    }
}

nonisolated enum PerkStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> PerkStore {
        PerkStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
