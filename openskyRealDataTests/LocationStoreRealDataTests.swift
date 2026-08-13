// Env-gated LCTN/LCRT, parent-chain, keyword and alias-fill acceptance over
// the user's read-only load order. No game bytes leave the run.

import Foundation
@testable import opensky
import Testing

struct LocationStoreRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func resolvesPinnedLocationAndMeasuresAliasFill() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let store = LocationStore(index: index)

        #expect(index.collectedCount(of: "LCTN") >= 829)
        #expect(index.collectedCount(of: "LCRT") >= 481)
        #expect(store.locations.count == index.count(of: "LCTN"))
        #expect(store.refTypes.count == index.count(of: "LCRT"))

        let pinned = try #require(store.location(editorID: "WhiterunLocation"))
        var chain: [String] = []
        var current: ResolvedLocation? = pinned
        var visited: Set<ResolvedFormID> = []
        while let resolved = current, visited.insert(resolved.id).inserted {
            chain.append(resolved.location.editorID ?? resolved.id.description)
            guard let parent = resolved.location.parent else { break }
            current = store.resolve(parent, fromPlugin: resolved.sourcePlugin)
        }
        print("[INFO] Whiterun location chain \(chain)")
        #expect(chain == ["WhiterunLocation", "WhiterunHoldLocation", "TamrielLocation"])
        let keywords = KeywordStore(index: index)
        let directKeywords = pinned.location.keywords.displayStrings(
            fromPlugin: pinned.sourcePlugin,
            using: keywords
        )
        print("[INFO] Whiterun direct keywords \(directKeywords)")
        #expect(!directKeywords.contains("LocTypeHold"))
        #expect(store.hasKeyword(editorID: "LocTypeHold", in: pinned.id))

        let skyrim = try #require(plugins.first {
            $0.name.caseInsensitiveCompare("Skyrim.esm") == .orderedSame
        })
        let quests = QuestStore(file: skyrim.file, pluginName: skyrim.name)
        var skipped = QuestAliasTally()
        var filledLocations = 0
        for quest in quests.sortedQuests() {
            let result = QuestAliasFiller.fill(
                quest,
                resolver: quests.resolver,
                locations: store
            )
            skipped.merge(result.skipped)
            filledLocations += result.state.locationFills.count
        }
        let remaining = skipped.counts[.locationAlias, default: 0]
        print(
            "[INFO] location aliases baseline 892, filled \(filledLocations), "
                + "remaining \(remaining)"
        )
        #expect(filledLocations == 162)
        #expect(remaining == 730)
    }
}
