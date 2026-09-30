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
    /// Every winning SPEL and SCRL identity in the load order.
    public private(set) var records: [ResolvedFormID: ResolvedSpell] = [:]
    private var recordsByEditorID: [String: ResolvedSpell] = [:]
    /// The same records under the identity the world state keys them by, so the
    /// spellbook can go from a stored key back to the record.
    private var recordsByKey: [ReferenceKey: ResolvedSpell] = [:]

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
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard let type = index.records[id]?.record.type, type == "SPEL" || type == "SCRL"
            else { continue }
            guard
                case let .decoded(decoded, sourcePlugin) = index.decodeIndexed(
                    id,
                    using: Self.decode
                )
            else { continue }
            let resolved = Self.join(
                id: id,
                record: decoded,
                sourcePlugin: sourcePlugin,
                effects: effects
            )
            records[id] = resolved
            recordsByKey[resolved.key] = resolved
            if let editorID = decoded.editorID {
                recordsByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    public init(index: RecordIndex) {
        self.init(index: index, effects: MagicEffectStore(index: index))
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["MGEF", "SPEL", "SCRL"]))
    }

    public func spell(_ id: ResolvedFormID) -> ResolvedSpell? {
        records[id] ?? records.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    public func spell(editorID: String) -> ResolvedSpell? {
        recordsByEditorID[editorID.lowercased()]
    }

    /// The record behind a stored runtime identity, or nil when this load order no
    /// longer carries it.
    public func spell(key: ReferenceKey) -> ResolvedSpell? {
        recordsByKey[key]
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedSpell? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return spell(resolvedID)
    }

    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// Joins one record's effect list against the effect store. Exposed so a
    /// caller holding an already-decoded record — the text dump, which decodes
    /// the record in front of it — gets the same numbers the store holds.
    public static func resolvedEffects(
        of record: MagicCastingRecord,
        fromPlugin pluginName: String,
        effects store: MagicEffectStore
    ) -> [ResolvedSpellEffect] {
        let castingType = record.data?.castingType ?? .fireAndForget
        return record.effects.map { item in
            let resolved = store.resolve(item, fromPlugin: pluginName)
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
