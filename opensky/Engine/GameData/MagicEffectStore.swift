// Load-order-wide MGEF lookup above RecordIndex. EFID links resolve relative
// to the plugin carrying the magic item, so overrides remain canonical and no
// consumer needs a hardcoded vanilla FormID.

import Foundation

nonisolated struct ResolvedMagicEffect: Equatable {
    let id: ResolvedFormID
    let effect: MagicEffect
    let sourcePlugin: String

    /// Runtime identity of this record, which is how an active effect names the
    /// MGEF it is an application of (issue #469).
    var key: ReferenceKey {
        ReferenceKey(resolved: id)
    }

    /// This effect's KWDA entries as runtime identities, resolved through the
    /// store the record came out of (issue #474).
    ///
    /// A keyword the load order no longer carries is dropped rather than
    /// guessed at, which makes the answer a subset of what is authored and
    /// never a superset.
    func keywordKeys(in store: MagicEffectStore) -> Set<ReferenceKey> {
        Set(effect.keywords.keywords.compactMap { keyword in
            store.resolvedID(keyword, fromPlugin: sourcePlugin).map(ReferenceKey.init(resolved:))
        })
    }

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
    /// The same records under the identity the active-effect component keys
    /// them by, so a stored effect goes back to its record without walking
    /// every entry (issue #474).
    private var effectsByKey: [ReferenceKey: ResolvedMagicEffect] = [:]

    init(index: RecordIndex) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
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
            effectsByKey[resolved.key] = resolved
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

    /// The record behind a stored runtime identity, or nil when this load order
    /// no longer carries it — which is what a save written under a different
    /// load order hands back.
    func effect(key: ReferenceKey) -> ResolvedMagicEffect? {
        effectsByKey[key]
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
