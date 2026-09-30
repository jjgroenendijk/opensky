// Load-order-wide MGEF lookup above RecordIndex. EFID links resolve relative
// to the plugin carrying the magic item, so overrides remain canonical and no
// consumer needs a hardcoded vanilla FormID.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedMagicEffect: Equatable, Sendable {
    public let id: ResolvedFormID
    public let effect: MagicEffect
    public let sourcePlugin: String

    /// Runtime identity of this record, which is how an active effect names its MGEF.
    public var key: ReferenceKey {
        ReferenceKey(resolved: id)
    }

    /// This effect's KWDA entries as runtime identities. A keyword the load
    /// order does not carry is dropped, so the answer is never a superset.
    public func keywordKeys(in store: MagicEffectStore) -> Set<ReferenceKey> {
        Set(effect.keywords.keywords.compactMap { keyword in
            store.resolvedID(keyword, fromPlugin: sourcePlugin).map(ReferenceKey.init(resolved:))
        })
    }

    public var displayName: String {
        switch effect.name {
        case let .inline(value): value
        case let .tableID(id): effect.editorID ?? "string #\(id)"
        case nil: effect.editorID ?? id.description
        }
    }
}

nonisolated public struct MagicEffectStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedMagicEffect>
    /// The same records under the identity the active-effect component keys them by.
    private let effectsByKey: [ReferenceKey: ResolvedMagicEffect]

    public var effects: [ResolvedFormID: ResolvedMagicEffect] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["MGEF"],
            decode: Self.decode,
            editorID: \.editorID,
            resolve: { ResolvedMagicEffect(id: $0, effect: $1, sourcePlugin: $2) }
        )
        effectsByKey = Dictionary(
            table.values.values.map { ($0.key, $0) },
            uniquingKeysWith: { _, later in later }
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["MGEF"]))
    }

    public func effect(_ id: ResolvedFormID) -> ResolvedMagicEffect? {
        table.value(id)
    }

    /// The record behind a stored runtime identity, or nil when this load order
    /// no longer carries it — which is what a save written under a different
    /// load order hands back.
    public func effect(key: ReferenceKey) -> ResolvedMagicEffect? {
        effectsByKey[key]
    }

    public func effect(editorID: String) -> ResolvedMagicEffect? {
        table.value(editorID: editorID)
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedMagicEffect? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return effect(resolvedID)
    }

    public func resolve(
        _ itemEffect: MagicItemEffect,
        fromPlugin pluginName: String
    ) -> ResolvedMagicEffect? {
        resolve(itemEffect.effect, fromPlugin: pluginName)
    }

    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
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
    public func resolved(
        fromPlugin pluginName: String,
        using store: MagicEffectStore
    ) -> ResolvedMagicEffect? {
        store.resolve(self, fromPlugin: pluginName)
    }
}

nonisolated public enum MagicEffectStoreLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> MagicEffectStore {
        MagicEffectStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
