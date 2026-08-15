// Resolved text for the Asset Browser's M18 record rows. The same formatter
// feeds the CLI record command, keeping link honesty out of the AppKit layer.

import Foundation

nonisolated struct ReferenceRecordInspector {
    private let index: RecordIndex
    private let keywords: KeywordStore
    private let formLists: FormListStore
    private let magicEffects: MagicEffectStore
    private let spells: SpellStore
    private let enchantments: EnchantmentStore
    private let locations: LocationStore
    private let encounterZones: EncounterZoneStore
    private let collisionLayers: CollisionLayerStore
    private let defaultObjects: DefaultObjectStore
    private let keywordUsage: [ResolvedFormID: [String]]

    init(index: RecordIndex) {
        self.index = index
        let keywordStore = KeywordStore(index: index)
        keywords = keywordStore
        formLists = FormListStore(index: index)
        let magicEffectStore = MagicEffectStore(index: index)
        magicEffects = magicEffectStore
        spells = SpellStore(index: index, effects: magicEffectStore)
        enchantments = EnchantmentStore(index: index, effects: magicEffectStore)
        locations = LocationStore(index: index)
        encounterZones = EncounterZoneStore(index: index)
        collisionLayers = CollisionLayerStore(index: index)
        defaultObjects = DefaultObjectStore(index: index)
        keywordUsage = Self.buildKeywordUsage(index: index, keywords: keywordStore)
    }

    func text(for preview: PreviewRecord) -> String {
        var sections = [RecordTextDump.dump(
            record: preview.record,
            localized: preview.localized,
            magicInspectorContext: RecordTextDump.MagicInspectorContext(
                keywordStore: keywords,
                formListStore: formLists,
                magicEffectStore: magicEffects,
                spellStore: spells,
                enchantmentStore: enchantments,
                sourcePlugin: preview.sourcePlugin
            )
        )]
        sections.insert(metadata(preview), at: 1)
        if let resolved = resolvedDetail(preview) {
            sections.insert(resolved, at: 2)
        }
        return sections.joined(separator: "\n\n")
    }

    private func metadata(_ preview: PreviewRecord) -> String {
        let identity = preview.resolvedID?.description ?? resolvedIdentity(preview).description
        return "resolved inspector:\n"
            + "  winner plugin: \(preview.sourcePlugin)\n"
            + "  identity: \(identity)"
    }

    private func resolvedDetail(_ preview: PreviewRecord) -> String? {
        guard let id = preview.resolvedID ?? resolvedIdentity(preview).value else { return nil }
        switch preview.record.type {
        case "KYWD": return keywordUsers(id)
        case "FLST": return flattenedList(id)
        case "LCTN": return locationChain(id)
        case "ECZN": return encounterZone(id)
        case "COLL": return collisionLayer(id)
        case "DOBJ": return defaultObjectTable()
        case "ENCH": return enchantmentChain(id)
        default: return nil
        }
    }

    private func keywordUsers(_ keywordID: ResolvedFormID) -> String {
        cappedLines(title: "users", values: keywordUsage[keywordID, default: []])
    }

    private func flattenedList(_ id: ResolvedFormID) -> String {
        guard let flattened = formLists.flattened(id) else {
            return "flattened membership:\n  [UNRESOLVED] \(id)"
        }
        let values = flattened.entries.map { entry in
            guard let entry else { return "NULL" }
            return displayName(entry)
        }
        let suffix = flattened.hitDepthCap ? " [DEPTH CAP]" : ""
        return cappedLines(
            title: "flattened membership (depth \(flattened.maximumDepth))\(suffix)",
            values: values
        )
    }

    private func locationChain(_ id: ResolvedFormID) -> String {
        let chain = locations.parentChain(of: id)
        guard !chain.isEmpty else { return "parent chain:\n  [UNRESOLVED] \(id)" }
        let values = chain.map { resolved in
            let name = resolved.location.editorID ?? resolved.id.description
            let keywordNames = resolved.location.keywords.displayStrings(
                fromPlugin: resolved.sourcePlugin,
                using: keywords
            )
            return "\(name) — \(resolved.sourcePlugin) — keywords ["
                + keywordNames.joined(separator: ", ") + "]"
        }
        return cappedLines(title: "parent chain", values: values)
    }

    /// The selected enchantment followed by each base enchantment above it.
    /// A vanilla chain is one or two entries; the store's cycle guard is what
    /// keeps a mod-authored loop from hanging the inspector.
    private func enchantmentChain(_ id: ResolvedFormID) -> String? {
        let chain = enchantments.baseChain(of: id)
        guard !chain.isEmpty else { return nil }
        let values = chain.map { resolved in
            let cost = resolved.cost
            return "\(resolved.editorID ?? resolved.id.description) — "
                + "\(resolved.sourcePlugin) — \(resolved.effects.count) effects, "
                + "cost \(cost.cost)\(cost.isManual ? " (manual)" : "")"
        }
        return cappedLines(title: "base enchantment chain", values: values)
    }

    private func encounterZone(_ id: ResolvedFormID) -> String? {
        guard let resolved = encounterZones.zone(id) else { return nil }
        let zone = resolved.zone
        return "resolved links:\n"
            + "  owner: \(link(zone.owner, fromPlugin: resolved.sourcePlugin))\n"
            + "  location: \(link(zone.location, fromPlugin: resolved.sourcePlugin))"
    }

    private func collisionLayer(_ id: ResolvedFormID) -> String? {
        guard let resolved = collisionLayers.layer(id) else { return nil }
        let values = resolved.layer.collidesWith.map {
            link($0, fromPlugin: resolved.sourcePlugin)
        }
        return cappedLines(title: "collides with", values: values)
    }

    private func defaultObjectTable() -> String {
        let values = defaultObjects.entries.values
            .sorted { $0.tag.description < $1.tag.description }
            .map { entry in
                let object = if let object = entry.object {
                    displayName(object)
                } else if let raw = entry.rawObject {
                    link(raw, fromPlugin: entry.sourcePlugin)
                } else {
                    "NULL"
                }
                return "\(entry.tag): \(object) — \(entry.sourcePlugin)"
            }
        return cappedLines(title: "merged default-object table", values: values)
    }

    private func link(_ raw: FormID?, fromPlugin plugin: String) -> String {
        guard let raw else { return "NULL" }
        switch index.resolve(raw, fromPlugin: plugin) {
        case .nullReference: return "NULL"
        case let .unavailablePlugin(name): return "[UNRESOLVED source \(name)] \(raw)"
        case let .resolved(id):
            guard case .record = index.lookup(id) else { return "[UNRESOLVED] \(id)" }
            return displayName(id)
        }
    }

    private func displayName(_ id: ResolvedFormID) -> String {
        guard case let .record(indexed) = index.lookup(id) else {
            return "[UNRESOLVED] \(id)"
        }
        return displayName(id, indexed: indexed)
    }

    private func displayName(_ id: ResolvedFormID, indexed: IndexedRecord) -> String {
        let editorID = ReferenceRecordCatalog.editorID(in: indexed.record) ?? id.description
        return "\(editorID) — \(indexed.sourcePlugin) — \(id)"
    }

    private func resolvedIdentity(_ preview: PreviewRecord) -> OptionalDescription<ResolvedFormID> {
        switch index.resolve(FormID(preview.record.formID), fromPlugin: preview.sourcePlugin) {
        case let .resolved(id): OptionalDescription(value: id, description: id.description)
        case .nullReference: OptionalDescription(value: nil, description: "NULL")
        case let .unavailablePlugin(name):
            OptionalDescription(value: nil, description: "[UNRESOLVED source \(name)]")
        }
    }

    private func cappedLines(title: String, values: [String]) -> String {
        let visible = values.prefix(RecordTextDump.fieldPrintCap).map { "  \($0)" }
        let suffix = values.count > RecordTextDump.fieldPrintCap
            ? ["  ... \(values.count - RecordTextDump.fieldPrintCap) more"]
            : []
        return "\(title) (\(values.count)):\n" + (visible + suffix).joined(separator: "\n")
    }

    private static func buildKeywordUsage(
        index: RecordIndex,
        keywords: KeywordStore
    ) -> [ResolvedFormID: [String]] {
        var usage: [ResolvedFormID: [String]] = [:]
        for (id, indexed) in index.records {
            guard let fields = try? indexed.record.fields() else { continue }
            var list = KeywordList()
            for field in fields {
                guard (try? list.decode(field: field)) != nil else { break }
            }
            let editorID = ReferenceRecordCatalog.editorID(in: indexed.record) ?? id.description
            let user = "\(editorID) — \(indexed.sourcePlugin) — \(id)"
            for raw in list.keywords {
                guard
                    let keywordID = keywords.resolvedID(
                        raw,
                        fromPlugin: indexed.sourcePlugin
                    ) else { continue }
                usage[keywordID, default: []].append(user)
            }
        }
        return usage.mapValues {
            $0.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }
}

nonisolated private struct OptionalDescription<Value> {
    let value: Value?
    let description: String
}
