// Load-order-wide SPEL and SCRL lookup above RecordIndex, like `KeywordStore`.
// One store, because a scroll is a spell in an item. `MagicCastingRecord` keeps
// the two apart. Each effect is joined with `MagicEffectStore` and the
// auto-calculated cost is computed once.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// One effect of a spell or scroll, joined against the effect store.
nonisolated public struct ResolvedSpellEffect: Sendable {
    /// The EFID/EFIT entry as it appears in the record.
    public let item: MagicItemEffect
    /// The MGEF the EFID names, or nil when the link does not resolve.
    public let effect: ResolvedMagicEffect?
    /// This effect's contribution to the auto-calculated cost.
    public let cost: Float

    public var displayName: String {
        effect?.displayName ?? "[UNRESOLVED] \(item.effect)"
    }
}

nonisolated public struct ResolvedSpell: Sendable {
    public let id: ResolvedFormID
    public let record: MagicCastingRecord
    public let sourcePlugin: String
    public let effects: [ResolvedSpellEffect]
    public let cost: SpellCostResult

    public var editorID: String? {
        record.editorID
    }

    public var data: SpellItemData? {
        record.data
    }

    public var recordType: FourCC {
        record.recordType
    }

    /// Runtime identity of this record, which the spellbook and the active-effect
    /// runtime use.
    public var key: ReferenceKey {
        ReferenceKey(resolved: id)
    }

    /// SPIT spell type, `.spell` when the header did not decode — the same
    /// fallback the cost calculation takes.
    public var spellType: SpellType {
        data?.type ?? .spell
    }

    /// True when the record carries the SPIT "PC Start Spell" flag.
    public var isPlayerStartSpell: Bool {
        data?.flags.contains(.pcStartSpell) ?? false
    }

    public var displayName: String {
        switch record.name {
        case let .inline(value): value
        case let .tableID(id): record.editorID ?? "string #\(id)"
        case nil: record.editorID ?? id.description
        }
    }
}

nonisolated public struct SpellStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedSpell>
    /// The same records under the identity the world state keys them by, so the
    /// spellbook can go from a stored key back to the record.
    private let recordsByKey: [ReferenceKey: ResolvedSpell]

    /// Every winning SPEL and SCRL identity in the load order.
    public var records: [ResolvedFormID: ResolvedSpell] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public var spells: [ResolvedSpell] {
        records.values.filter { $0.recordType == "SPEL" }
    }

    /// Editor IDs of the spells the player knows before learning anything: "You will
    /// always know the spells Flames and Healing"
    /// (<https://en.uesp.net/wiki/Skyrim:Spells>). Named, not derived: vanilla sets
    /// SPIT "PC Start Spell" only on `PCHealRateCombat` (`CasterRealDataTests`) and
    /// grants these from a quest script. Editor IDs, so a load order without them
    /// grants nothing.
    public static let vanillaStartSpellEditorIDs = ["Flames", "Healing"]

    /// The records `vanillaStartSpellEditorIDs` names that this load order
    /// actually carries, in that order.
    public var playerStartSpells: [ResolvedSpell] {
        Self.vanillaStartSpellEditorIDs.compactMap { spell(editorID: $0) }
    }

    public var scrolls: [ResolvedSpell] {
        records.values.filter { $0.recordType == "SCRL" }
    }

    public init(index: RecordIndex, effects: MagicEffectStore) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["SPEL", "SCRL"],
            decode: Self.decode,
            editorID: \.editorID,
            resolve: { id, decoded, sourcePlugin in
                Self.join(id: id, record: decoded, sourcePlugin: sourcePlugin, effects: effects)
            }
        )
        recordsByKey = Dictionary(
            table.values.values.map { ($0.key, $0) },
            uniquingKeysWith: { _, later in later }
        )
    }

    public init(index: RecordIndex) {
        self.init(index: index, effects: MagicEffectStore(index: index))
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["MGEF", "SPEL", "SCRL"]))
    }

    public func spell(_ id: ResolvedFormID) -> ResolvedSpell? {
        table.value(id)
    }

    public func spell(editorID: String) -> ResolvedSpell? {
        table.value(editorID: editorID)
    }

    /// The record behind a stored runtime identity, or nil when this load order no
    /// longer carries it.
    public func spell(key: ReferenceKey) -> ResolvedSpell? {
        recordsByKey[key]
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedSpell? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return spell(resolvedID)
    }

    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// Joins one record's effect list against the effect store. A caller that
    /// already decoded the record, such as the text dump, gets the store's numbers.
    public static func resolvedEffects(
        of record: MagicCastingRecord,
        fromPlugin pluginName: String,
        effects store: MagicEffectStore
    ) -> [ResolvedSpellEffect] {
        store.resolvedEffects(
            record.effects,
            fromPlugin: pluginName,
            castingType: record.data?.castingType ?? .fireAndForget
        )
    }

    /// Totals joined effects into the cost the game charges.
    public static func cost(
        of record: MagicCastingRecord,
        effects: [ResolvedSpellEffect]
    ) -> SpellCostResult {
        SpellCost.result(
            data: record.data,
            total: SpellCost.total(ofEffectCosts: effects.map(\.cost)),
            unresolvedEffects: effects.count { $0.effect == nil }
        )
    }

    private static func join(
        id: ResolvedFormID,
        record: MagicCastingRecord,
        sourcePlugin: String,
        effects store: MagicEffectStore
    ) -> ResolvedSpell {
        let resolvedEffects = resolvedEffects(
            of: record,
            fromPlugin: sourcePlugin,
            effects: store
        )
        return ResolvedSpell(
            id: id,
            record: record,
            sourcePlugin: sourcePlugin,
            effects: resolvedEffects,
            cost: cost(of: record, effects: resolvedEffects)
        )
    }

    private static func decode(_ indexed: IndexedRecord) throws -> MagicCastingRecord {
        switch indexed.record.type {
        case "SPEL":
            return try .spell(Spell(record: indexed.record, localized: indexed.localized))
        case "SCRL":
            return try .scroll(Scroll(record: indexed.record, localized: indexed.localized))
        default:
            throw ESMError.malformed("expected SPEL or SCRL, got \(indexed.record.type)")
        }
    }
}

nonisolated extension MagicEffectStore {
    /// Joins effect items against this store and prices each one.
    public func resolvedEffects(
        _ items: [MagicItemEffect],
        fromPlugin pluginName: String,
        castingType: MagicEffectCastingType
    ) -> [ResolvedSpellEffect] {
        items.map { item in
            let resolved = resolve(item, fromPlugin: pluginName)
            let baseCost = resolved?.effect.data?.baseCost
            return ResolvedSpellEffect(
                item: item,
                effect: resolved,
                cost: baseCost.map {
                    SpellCost.effectCost(
                        baseCost: $0,
                        magnitude: item.magnitude,
                        duration: item.duration,
                        castingType: castingType
                    )
                } ?? 0
            )
        }
    }
}
