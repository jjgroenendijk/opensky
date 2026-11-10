// Load-order-wide ARTO lookup above RecordIndex, plus the typed art links of
// MGEF and DUAL. A link resolves relative to the plugin that authored it.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated struct ResolvedArtObject: Equatable, Sendable {
    let id: ResolvedFormID
    let art: ArtObject
    let sourcePlugin: String
}

/// The three ARTO links in MGEF DATA, each nil when unset or not in the load order.
nonisolated struct MagicEffectArt: Equatable, Sendable {
    let casting: ResolvedArtObject?
    let hitEffect: ResolvedArtObject?
    let enchant: ResolvedArtObject?
}

nonisolated struct ArtObjectStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedArtObject>

    var artObjects: [ResolvedFormID: ResolvedArtObject] {
        table.values
    }

    var skippedRecords: SkippedRecords {
        table.skipped
    }

    init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["ARTO"],
            decode: { try ArtObject(record: $0.record) },
            editorID: \.editorID,
            resolve: { ResolvedArtObject(id: $0, art: $1, sourcePlugin: $2) }
        )
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["ARTO"]))
    }

    func artObject(_ id: ResolvedFormID) -> ResolvedArtObject? {
        table.value(id)
    }

    func artObject(editorID: String) -> ResolvedArtObject? {
        table.value(editorID: editorID)
    }

    func resolve(_ id: FormID?, fromPlugin pluginName: String) -> ResolvedArtObject? {
        index.resolvedID(id, fromPlugin: pluginName).flatMap { artObject($0) }
    }

    /// Nil when the effect has no DATA.
    func art(of effect: ResolvedMagicEffect) -> MagicEffectArt? {
        guard let data = effect.effect.data else { return nil }
        return MagicEffectArt(
            casting: resolve(data.castingArt, fromPlugin: effect.sourcePlugin),
            hitEffect: resolve(data.hitEffectArt, fromPlugin: effect.sourcePlugin),
            enchant: resolve(data.enchantArt, fromPlugin: effect.sourcePlugin)
        )
    }

    /// The hit-effect art a dual cast uses in place of the effect's own.
    func hitEffectArt(
        of dual: DualCastData,
        fromPlugin pluginName: String
    ) -> ResolvedArtObject? {
        resolve(dual.art?.hitEffectArt, fromPlugin: pluginName)
    }
}
