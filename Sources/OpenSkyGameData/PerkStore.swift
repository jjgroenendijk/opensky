// Load-order-wide PERK lookup above RecordIndex, like `SpellStore`. Ability
// effects and spell-selecting entry points are resolved against `SpellStore`.
// Every entry-point effect is indexed by entry-point id, so the perk runtime
// does not scan every perk per formula.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// One effect of a perk, joined against the spell store.
nonisolated public struct ResolvedPerkEffect: Sendable {
    public let effect: PerkEffect
    /// The SPEL an ability effect grants, or the one a "select spell" function
    /// casts. Nil when the effect names no spell or the link does not resolve.
    public let spell: ResolvedSpell?

    public var entryPoint: PerkEntryPoint? {
        effect.entryPoint
    }

    public var spellName: String? {
        guard let raw = effect.spell else { return nil }
        return spell?.displayName ?? "[UNRESOLVED] \(raw)"
    }
}

nonisolated public struct ResolvedPerk: Sendable {
    public let id: ResolvedFormID
    public let record: Perk
    public let sourcePlugin: String
    public let effects: [ResolvedPerkEffect]
    /// NNAM resolved against the load order. Nil when the perk is the last
    /// rank or the link does not resolve.
    public let nextPerk: ResolvedFormID?

    public var editorID: String? {
        record.editorID
    }

    /// What the record's DATA declares, which is not the length of its rank
    /// chain — see `PerkHeaderData`. `PerkStore.rankChain(from:)` answers the
    /// real question.
    public var declaredRankCount: UInt8 {
        record.declaredRankCount
    }

    public var displayName: String {
        switch record.name {
        case let .inline(value): value
        case .tableID, .pluginTableID: record.editorID ?? id.description
        case nil: record.editorID ?? id.description
        }
    }
}

/// One entry-point hook, as the flat index holds it: enough to sort and filter
/// without touching the perk, plus the coordinates to fetch the effect.
nonisolated public struct PerkEntryPointMatch: Equatable, Sendable {
    public let perk: ResolvedFormID
    /// Position of the effect inside `ResolvedPerk.effects`.
    public let effectIndex: Int
    public let priority: UInt8
}

nonisolated public struct PerkStore: Sendable {
    /// Depth cap for a rank chain, so a mod-authored NNAM loop cannot hang a
    /// caller. Vanilla's longest chain is five ranks.
    private static let rankChainCap = 32

    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedPerk>
    /// Entry-point id to the effects that hook it, across every perk.
    public private(set) var entryPointIndex: [UInt8: [PerkEntryPointMatch]] = [:]
    private var recordsByKey: [ReferenceKey: ResolvedPerk] = [:]
    /// Each perk that is somebody's `NNAM` target, mapped back to the record naming
    /// it: the reverse of `rankChain(from:)`, so buying a rank finds the one before.
    private var previousRanks: [ResolvedFormID: ResolvedFormID] = [:]

    /// Every winning PERK identity in the load order.
    public var records: [ResolvedFormID: ResolvedPerk] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public var perks: [ResolvedPerk] {
        Array(records.values)
    }

    /// How many effects hook each entry point, most-used first. What scopes
    /// which entry points the perk runtime has to implement.
    public var entryPointHistogram: [(entryPoint: PerkEntryPoint, count: Int)] {
        entryPointIndex
            .map { (PerkEntryPoint(rawValue: $0.key), $0.value.count) }
            .sorted {
                $0.1 == $1.1 ? $0.0.rawValue < $1.0.rawValue : $0.1 > $1.1
            }
    }

    public init(index: RecordIndex, spells: SpellStore) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["PERK"],
            decode: Self.decode,
            editorID: \.editorID,
            resolve: { id, decoded, sourcePlugin in
                Self.join(
                    id: id,
                    record: decoded,
                    sourcePlugin: sourcePlugin,
                    index: index,
                    spells: spells
                )
            }
        )
        for resolved in table.orderedValues {
            add(resolved)
        }
    }

    public init(index: RecordIndex) {
        self.init(index: index, spells: SpellStore(index: index))
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(
            plugins: plugins,
            recordTypes: ["MGEF", "SPEL", "SCRL", "PERK"]
        ))
    }

    public func perk(_ id: ResolvedFormID) -> ResolvedPerk? {
        table.value(id)
    }

    /// The perk one runtime identity names, which is what the perk runtime
    /// looks every stored key up through.
    public func perk(key: ReferenceKey) -> ResolvedPerk? {
        recordsByKey[key]
    }

    public func perk(editorID: String) -> ResolvedPerk? {
        table.value(editorID: editorID)
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedPerk? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return perk(resolvedID)
    }

    /// A perk link as text: its name when the load order carries it, and an
    /// explicit unresolved marker when it does not. What every dump that
    /// prints a perk link uses, so a missing record never looks like a name.
    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// Every effect hooking one entry point, ordered by the PRKE priority the
    /// records declare and then by identity so the answer is deterministic.
    public func matches(at entryPoint: PerkEntryPoint) -> [PerkEntryPointMatch] {
        entryPointIndex[entryPoint.rawValue, default: []]
    }

    /// The effect one match names, or nil when the match came from a different
    /// store than the one being asked.
    public func effect(_ match: PerkEntryPointMatch) -> ResolvedPerkEffect? {
        guard
            let perk = perk(match.perk),
            match.effectIndex < perk.effects.count
        else { return nil }
        return perk.effects[match.effectIndex]
    }

    /// The rank this perk continues, or nil when it is a chain head or stands
    /// alone. Two records naming the same `NNAM` target — which vanilla does
    /// not author and a mod could — leave the first one seen as the answer,
    /// because a spend needs one predecessor to name rather than a set.
    public func previousRank(of id: ResolvedFormID) -> ResolvedPerk? {
        previousRanks[id].flatMap(perk)
    }

    /// The rank chain starting at `id`: the perk itself, then each perk its
    /// NNAM reaches. Stops on a repeat or at `rankChainCap`, so a mod-authored
    /// loop yields a short chain rather than hanging.
    public func rankChain(from id: ResolvedFormID) -> [ResolvedPerk] {
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
        recordsByKey[ReferenceKey(resolved: resolved.id)] = resolved
        if let next = resolved.nextPerk, previousRanks[next] == nil {
            previousRanks[next] = resolved.id
        }
        for (offset, effect) in resolved.effects.enumerated() {
            guard let entryPoint = effect.entryPoint else { continue }
            let match = PerkEntryPointMatch(
                perk: resolved.id,
                effectIndex: offset,
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

nonisolated public enum PerkStoreLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> PerkStore {
        PerkStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
