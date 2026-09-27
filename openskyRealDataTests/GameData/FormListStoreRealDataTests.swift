// Env-gated FLST decode and nesting census over the user's read-only load order.

import Foundation
@testable import opensky
import Testing

struct FormListStoreRealDataTests {
    private struct NestedCandidate {
        let editorID: String
        let rawCount: Int
        let flatCount: Int
        let leaves: [String]
    }

    private struct Measurements {
        var deepest = 0
        var deepestEditorID = "-"
        var largest = 0
        var largestEditorID = "-"
        var winningNullEntries = 0
        var allDefinitionCount = 0
        var allDefinitionNullEntries = 0
        var nestedLists: [NestedCandidate] = []
    }

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesVanillaListsAndMeasuresNesting() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let store = FormListStore(plugins: plugins)
        let measurements = try Self.measure(store: store, plugins: plugins)

        #expect(store.formLists.count >= 1000)
        let pinned = try #require(store.formList(editorID: "AtrFrgAtronachForgeRecipeList"))
        let pinnedMember = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x03AD5E)
        #expect(store.contains(pinnedMember, in: pinned.id))
        #expect(
            !pinned.list.entries.compactMap(\.self).contains { rawID in
                store.resolvedID(rawID, fromPlugin: pinned.sourcePlugin) == pinnedMember
            }
        )
        Self.report(measurements, winningCount: store.formLists.count)
    }

    private static func measure(
        store: FormListStore,
        plugins: [(name: String, file: ESMFile)]
    ) throws -> Measurements {
        var result = Measurements()
        for resolved in store.formLists.values {
            if resolved.list.entries.count > result.largest {
                result.largest = resolved.list.entries.count
                result.largestEditorID = resolved.list.editorID ?? resolved.id.description
            }
            result.winningNullEntries += resolved.list.entries.count { $0 == nil }
            let flattened = try #require(store.flattened(resolved.id))
            if flattened.maximumDepth > result.deepest {
                result.deepest = flattened.maximumDepth
                result.deepestEditorID = resolved.list.editorID ?? resolved.id.description
            }
            #expect(!flattened.hitDepthCap)
            let nestedCount = resolved.list.entries.compactMap(\.self).count { rawID in
                store.resolvedID(rawID, fromPlugin: resolved.sourcePlugin)
                    .flatMap(store.formList) != nil
            }
            if nestedCount > 0, let editorID = resolved.list.editorID {
                result.nestedLists.append(
                    NestedCandidate(
                        editorID: editorID,
                        rawCount: resolved.list.entries.count,
                        flatCount: flattened.entries.count,
                        leaves: flattened.entries.prefix(6).map { $0?.description ?? "NULL" }
                    )
                )
            }
        }
        for plugin in plugins {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                guard record.type == "FLST", let list = try? FormList(record: record)
                else { return true }
                result.allDefinitionCount += 1
                result.allDefinitionNullEntries += list.entries.count { $0 == nil }
                return true
            }
        }
        return result
    }

    private static func report(_ result: Measurements, winningCount: Int) {
        print(
            "[INFO] FLST records \(winningCount), "
                + "largest \(result.largest) (\(result.largestEditorID)), "
                + "deepest \(result.deepest) (\(result.deepestEditorID)), "
                + "winning null entries \(result.winningNullEntries), "
                + "definitions \(result.allDefinitionCount), "
                + "all-definition null entries \(result.allDefinitionNullEntries)"
        )
        let candidates = result.nestedLists.sorted { $0.editorID < $1.editorID }.prefix(20)
        for candidate in candidates {
            print(
                "[INFO] nested FLST \(candidate.editorID): raw \(candidate.rawCount), "
                    + "flat \(candidate.flatCount), "
                    + "leaves \(candidate.leaves.joined(separator: ", "))"
            )
        }
    }
}
