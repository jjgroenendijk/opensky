// Env-gated vendor acceptance over the user's own read-only load order (issue
// #506, roadmap item 21.7): Belethor resolves to his vendor faction, merchant
// chest, hours and negated buy/sell list through his `SNAM` run; a Thieves
// Guild fence buys the stolen goods Belethor refuses.
//
// Editor IDs, flags and counts only — no game bytes leave the run (AGENTS.md
// "Legal & IP boundary").

import Foundation
@testable import OpenSky
import Testing

struct VendorRulesRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let pawnbrokerEditorID = "Belethor"
    private static let pawnbrokerFactionEditorID = "ServicesWhiterunBelethorsGoods"
    private static let fenceFactionEditorID = "ServicesThievesGuildTonilia"
    /// A keyword the pawnbroker's negated `VendorItemsMisc` list names.
    private static let excludedKeywordEditorID = "VendorItemKey"

    @Test(.enabled(if: Self.dataRoot != nil))
    func belethorTradesByHisListAndOnlyTheFenceBuysStolenGoods() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(plugins: plugins, recordTypes: RecordIndex.referenceRecordTypes)
        let factions = FactionStore(index: index)
        let resolver = VendorResolver(factions: factions, formLists: FormListStore(index: index))

        let belethor = try #require(resolver.vendor(
            memberships: memberships(of: Self.pawnbrokerEditorID, root: root, store: factions)
        ))
        print(
            "[INFO] \(Self.pawnbrokerEditorID) vendor \(belethor.factionName), chest "
                + "\(belethor.merchantChest.map(\.description) ?? "-"), hours "
                + "\(belethor.hours.map { "\($0.start)-\($0.end)" } ?? "-"), list keywords "
                + "\(belethor.listKeywords?.count ?? -1), negated \(belethor.negatesList)"
        )
        let pawnbroker = try #require(factions.faction(editorID: Self.pawnbrokerFactionEditorID))
        #expect(belethor.faction == ReferenceKey(resolved: pawnbroker.id))
        #expect(belethor.merchantChest != nil)
        #expect(belethor.negatesList)
        #expect(!belethor.buysStolen)
        #expect(belethor.isOpen(atHour: 12))
        #expect(!belethor.isOpen(atHour: 22))

        let excluded = try #require(
            KeywordStore(index: index).keyword(editorID: Self.excludedKeywordEditorID)
        )
        #expect(!belethor.trades(keywords: [ReferenceKey(resolved: excluded.id)]))
        #expect(belethor.trades(keywords: []))

        let fence = try resolver.vendor(
            faction: #require(factions.faction(editorID: Self.fenceFactionEditorID))
        )
        #expect(fence.buysStolen)
        #expect(fence.isOpen(atHour: 22))
    }

    /// One `Skyrim.esm` NPC_'s faction memberships through its template chain,
    /// as the runtime seeds them.
    private func memberships(
        of editorID: String,
        root: GameDataRoot,
        store: FactionStore
    ) throws -> ActorFactionState {
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let file = try ESMFile(url: esmURL)
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let resolver = ActorTemplateResolver.build(from: file, localized: localized)
        let base = try #require(resolver.actors.values.first { $0.editorID == editorID })
        let resolved = try resolver.resolveFactions(base: base.formID)
        let rows = store.memberships(resolved.factions.value, fromPlugin: esmURL.lastPathComponent)
        return ActorFactionState(memberships: rows.compactMap { row in
            row.faction.map {
                ActorFactionMembership(faction: ReferenceKey(resolved: $0.id), rank: row.rank)
            }
        })
    }
}
