// Load-order-wide SPEL and SCRL lookup above RecordIndex, in the shape
// `KeywordStore` and `MagicEffectStore` already use.
//
// Both record types live in one store because they are the same payload: a
// scroll is a spell wrapped in an inventory item, and every consumer that
// chases a link — BOOK's spell tome, WEAP's critical effect, the caster
// runtime in 19.7 — wants the casting header and the resolved effect list, not
// the record tag. `MagicCastingRecord` keeps the two decoders distinguishable.
//
// The store joins each effect against `MagicEffectStore` and computes the
// auto-calculated cost once, at construction, so no consumer recomputes it.

import Foundation

/// One effect of a spell or scroll, joined against the effect store.
nonisolated struct ResolvedSpellEffect {
    /// The EFID/EFIT entry as it appears in the record.
    let item: MagicItemEffect
    /// The MGEF the EFID names, or nil when the link does not resolve.
    let effect: ResolvedMagicEffect?
    /// This effect's contribution to the auto-calculated cost.
    let cost: Float

    var displayName: String {
        effect?.displayName ?? "[UNRESOLVED] \(item.effect)"
    }
}

nonisolated struct ResolvedSpell {
    let id: ResolvedFormID
    let record: MagicCastingRecord
    let sourcePlugin: String
    let effects: [ResolvedSpellEffect]
    let cost: SpellCostResult

    var editorID: String? {
        record.editorID
    }

    var data: SpellItemData? {
        record.data
    }

    var recordType: FourCC {
        record.recordType
    }

    /// Runtime identity of this record, which is how the spellbook and the
    /// active-effect runtime address it (issue #470).
    var key: ReferenceKey {
        ReferenceKey(resolved: id)
    }

    /// SPIT spell type, `.spell` when the header did not decode — the same
    /// fallback the cost calculation takes.
    var spellType: SpellType {
        data?.type ?? .spell
    }

    /// True when the record carries the SPIT "PC Start Spell" flag, which is
    /// what makes a spell one the player already knows (issue #470).
    var isPlayerStartSpell: Bool {
        data?.flags.contains(.pcStartSpell) ?? false
    }

    var displayName: String {
        switch record.name {
        case let .inline(value): value
        case let .tableID(id): record.editorID ?? "string #\(id)"
        case nil: record.editorID ?? id.description
        }
    }
}

nonisolated struct SpellStore {
    private let index: RecordIndex
    /// Every winning SPEL and SCRL identity in the load order.
    private(set) var records: [ResolvedFormID: ResolvedSpell] = [:]
    private var recordsByEditorID: [String: ResolvedSpell] = [:]
    /// The same records under the identity the world state keys them by, so the
    /// spellbook can go from a stored key back to the record without walking
    /// every entry (issue #470).
    private var recordsByKey: [ReferenceKey: ResolvedSpell] = [:]

    var spells: [ResolvedSpell] {
        records.values.filter { $0.recordType == "SPEL" }
    }

    /// Editor IDs of the spells the player knows before learning anything.
    ///
    /// UESP: "You will always know the spells Flames and Healing by the time you
    /// start Unbound, regardless of your race"
    /// (<https://en.uesp.net/wiki/Skyrim:Spells>).
    ///
    /// Named rather than derived, and that is a deliberate finding rather than
    /// a shortcut. The obvious data source would be the SPIT "PC Start Spell"
    /// flag, and it is not the mechanism: across the whole vanilla load order
    /// that bit is set on exactly one record, `PCHealRateCombat`, which
    /// `CasterRealDataTests` pins so the finding cannot quietly rot. Vanilla
    /// grants Flames and Healing from the intro quest's Papyrus script instead,
    /// and this build does not run that quest. Editor IDs rather than FormIDs so
    /// the lookup goes through the load order: a load order carrying neither
    /// record grants nothing rather than reaching for a form that is not there.
    static let vanillaStartSpellEditorIDs = ["Flames", "Healing"]

    /// The records `vanillaStartSpellEditorIDs` names that this load order
    /// actually carries, in that order.
    var playerStartSpells: [ResolvedSpell] {
        Self.vanillaStartSpellEditorIDs.compactMap { spell(editorID: $0) }
    }

    var scrolls: [ResolvedSpell] {
        records.values.filter { $0.recordType == "SCRL" }
    }

    init(index: RecordIndex, effects: MagicEffectStore) {
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

    init(index: RecordIndex) {
        self.init(index: index, effects: MagicEffectStore(index: index))
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["MGEF", "SPEL", "SCRL"]))
    }

    func spell(_ id: ResolvedFormID) -> ResolvedSpell? {
        records[id] ?? records.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    func spell(editorID: String) -> ResolvedSpell? {
        recordsByEditorID[editorID.lowercased()]
    }

    /// The record behind a stored runtime identity, or nil when this load order
    /// no longer carries it — which is what a save written under a different
    /// load order hands back (issue #470).
    func spell(key: ReferenceKey) -> ResolvedSpell? {
        recordsByKey[key]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedSpell? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return spell(resolvedID)
    }

    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// Joins one record's effect list against the effect store. Exposed so a
    /// caller holding an already-decoded record — the text dump, which decodes
    /// the record in front of it — gets the same numbers the store holds.
    static func resolvedEffects(
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
    static func cost(
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

nonisolated enum SpellStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> SpellStore {
        SpellStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
