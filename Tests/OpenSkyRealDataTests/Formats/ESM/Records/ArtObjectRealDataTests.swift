// ARTO sweep over the five masters: every record decodes, the total is pinned,
// and every ARTO link on MGEF and DUAL resolves in the store.
// Run with `make test-real T='ArtObjectRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct ArtObjectRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryArtObjectAndResolvesEveryMagicArtLink() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = try VanillaMasters.load(root: root)
        var failures: [String] = []
        var types: [String: Int] = [:]
        var skipped = FieldTally()
        let records = VanillaMasters.liveRecords(of: "ARTO", in: plugins)
        for entry in records {
            do {
                let art = try ArtObject(record: entry.record)
                types[art.artType.map { "\($0)" } ?? "-", default: 0] += 1
                skipped.merge(art.skipped)
            } catch {
                failures.append("\(FormID(entry.record.formID)): \(error)")
            }
        }
        #expect(failures.isEmpty, "records that threw: \(failures.prefix(5))")
        #expect(records.count == 318, "ARTO count drift")

        let index = RecordIndex(plugins: plugins, recordTypes: ["ARTO", "MGEF", "DUAL"])
        let store = ArtObjectStore(index: index)
        #expect(store.skippedRecords.isEmpty)
        #expect(store.artObject(editorID: "AbsorbBlueHandFX01")?.art.artType == .magicCasting)
        #expect(store.artObject(editorID: "AbsorbSpellHitEffect01")?.art.artType == .magicHitEffect)
        #expect(store.artObject(editorID: "BoundSwordEnchEffects")?.art
            .artType == .enchantmentEffect)

        let links = Self.unresolvedLinks(index: index, store: store)
        #expect(links.unresolved.isEmpty, "unresolved art links: \(links.unresolved.prefix(5))")
        #expect(links.total > 0)

        let report = ([
            "[INFO] ARTO records \(records.count), store \(store.artObjects.count)",
            "[INFO] art types \(types.sorted { $0.key < $1.key })",
            "[INFO] art links on MGEF and DUAL: \(links.total), "
                + "unresolved \(links.unresolved.count)",
            "[INFO] unread fields:"
        ] + skipped.ranked.map { "  \($0.name): \($0.count)" }).joined(separator: "\n")
        print(report)
        try? report.write(
            to: RepositoryLogs.directory().appending(path: "art-object-sweep.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func unresolvedLinks(
        index: RecordIndex,
        store: ArtObjectStore
    ) -> (total: Int, unresolved: [String]) {
        var total = 0
        var unresolved: [String] = []
        func check(_ link: FormID?, _ resolved: ResolvedArtObject?, _ owner: String) {
            guard link != nil else { return }
            total += 1
            if resolved == nil {
                unresolved.append(owner)
            }
        }
        for effect in MagicEffectStore(index: index).effects.values {
            guard let data = effect.effect.data, let art = store.art(of: effect) else { continue }
            let owner = "MGEF \(effect.id)"
            check(data.castingArt, art.casting, owner + " casting")
            check(data.hitEffectArt, art.hitEffect, owner + " hit")
            check(data.enchantArt, art.enchant, owner + " enchant")
        }
        for id in index.orderedRecordIDs(of: ["DUAL"]) {
            guard
                let indexed = index.records[id],
                let dual = try? DualCastData(record: indexed.record)
            else { continue }
            check(
                dual.art?.hitEffectArt,
                store.hitEffectArt(of: dual, fromPlugin: indexed.sourcePlugin),
                "DUAL \(id)"
            )
        }
        return (total, unresolved)
    }
}
