// Load-order-wide MGEF lookup above RecordIndex. EFID links resolve relative
// to the plugin carrying the magic item, so overrides remain canonical and no
// consumer needs a hardcoded vanilla FormID.

import Foundation

nonisolated struct ResolvedMagicEffect: Equatable {
    let id: ResolvedFormID
    let effect: MagicEffect
    let sourcePlugin: String

    var displayName: String {
        switch effect.name {
        case let .inline(value): value
        case let .tableID(id): effect.editorID ?? "string #\(id)"
        case nil: effect.editorID ?? id.description
        }
    }
}

nonisolated struct MagicEffectStore {
    private let index: RecordIndex
    private(set) var effects: [ResolvedFormID: ResolvedMagicEffect] = [:]
    private var effectsByEditorID: [String: ResolvedMagicEffect] = [:]

    init(index: RecordIndex) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            MagicEffectStoreOrdering.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "MGEF" else { continue }
            guard
                case let .decoded(effect, sourcePlugin) = index.decodeIndexed(
                    id,
                    using: Self.decode
                )
            else { continue }
            let resolved = ResolvedMagicEffect(
                id: id,
                effect: effect,
                sourcePlugin: sourcePlugin
            )
            effects[id] = resolved
            if let editorID = effect.editorID {
                effectsByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["MGEF"]))
    }

    func effect(_ id: ResolvedFormID) -> ResolvedMagicEffect? {
        effects[id] ?? effects.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    func effect(editorID: String) -> ResolvedMagicEffect? {
        effectsByEditorID[editorID.lowercased()]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedMagicEffect? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return effect(resolvedID)
    }

    func resolve(
        _ itemEffect: MagicItemEffect,
        fromPlugin pluginName: String
    ) -> ResolvedMagicEffect? {
        resolve(itemEffect.effect, fromPlugin: pluginName)
    }

    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    private static func decode(_ indexed: IndexedRecord) throws -> MagicEffect {
        let effect = try MagicEffect(
            record: indexed.record,
            localized: indexed.localized
        )
        guard effect.data != nil else {
            throw ESMError.malformed("MGEF has no readable DATA field")
        }
        return effect
    }
}

nonisolated extension MagicItemEffect {
    func resolved(
        fromPlugin pluginName: String,
        using store: MagicEffectStore
    ) -> ResolvedMagicEffect? {
        store.resolve(self, fromPlugin: pluginName)
    }
}

nonisolated enum MagicEffectStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> MagicEffectStore {
        MagicEffectStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}

nonisolated private enum MagicEffectStoreOrdering {
    static func precedes(
        _ left: ResolvedFormID,
        _ right: ResolvedFormID,
        index: RecordIndex
    ) -> Bool {
        let leftSource = index.records[left]?.sourcePlugin ?? left.plugin
        let rightSource = index.records[right]?.sourcePlugin ?? right.plugin
        let leftPriority = index.priority(ofPlugin: leftSource)
        let rightPriority = index.priority(ofPlugin: rightSource)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if left.plugin.caseInsensitiveCompare(right.plugin) != .orderedSame {
            return left.plugin.localizedCaseInsensitiveCompare(right.plugin) == .orderedAscending
        }
        return left.objectID < right.objectID
    }
}
