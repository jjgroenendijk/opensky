// COBJ sweep over the five masters: every recipe decodes, its links resolve, and
// the per-workbench, component-type, and condition-function censuses go to `logs/`.
// Run with `make test-real T='RecipeRealDataTests'`.

import Foundation
import OpenSkyConditions
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorld
import Testing

struct RecipeRealDataTests {
    /// COBJ, its link targets, and the component targets xEdit allows.
    private static let indexTypes: Set<FourCC> = [
        "COBJ", "KYWD", "FLST", "LVLI", "ALCH", "AMMO", "APPA", "ARMO", "BOOK", "INGR",
        "KEYM", "LIGH", "MISC", "SCRL", "SLGM", "WEAP"
    ]

    private struct Census {
        var byWorkbench: [String: Int] = [:]
        var componentTypes: [String: Int] = [:]
        var functions: [String: Int] = [:]
        var unresolved: [String] = []
        /// Vanilla ships a few recipes with a null CNAM, for items that were cut.
        var nullCreatedObject = 0
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryRecipeAndResolvesItsLinks() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = try VanillaMasters.load(root: root)
        let records = VanillaMasters.liveRecords(of: "COBJ", in: plugins)
        var failures: [String] = []
        var skipped = FieldTally()
        for entry in records {
            do {
                try skipped.merge(ConstructibleObject(record: entry.record).skipped)
            } catch {
                failures.append("\(FormID(entry.record.formID)): \(error)")
            }
        }
        #expect(failures.isEmpty, "records that threw: \(failures.prefix(5))")
        #expect(records.count == 1387, "COBJ count drift")

        let index = RecordIndex(plugins: plugins, recordTypes: Self.indexTypes)
        let store = RecipeStore(index: index)
        #expect(store.skippedRecords.isEmpty)
        let census = Self.census(store: store, index: index)
        #expect(census.unresolved.isEmpty, "unresolved links: \(census.unresolved.prefix(5))")
        #expect(census.nullCreatedObject == 7)

        let sword = try #require(store.recipe(editorID: "RecipeWeaponIronSword"))
        #expect(Self.editorID(sword.createdObject, index) == "IronSword")
        #expect(Self.editorID(sword.workbenchKeyword, index) == "CraftingSmithingForge")
        #expect(try store.recipes(creating: #require(sword.createdObject)).contains(sword))

        let supported = ConditionFunctionRegistry.standard
        let report = ([
            "[INFO] COBJ records \(records.count), store \(store.recipes.count)",
            "[INFO] recipes with a null created object: \(census.nullCreatedObject)",
            "[INFO] recipes per workbench keyword:"
        ] + Self.lines(census.byWorkbench) + ["[INFO] component target types:"]
            + Self.lines(census.componentTypes)
            + ["[INFO] condition functions (supported by the evaluator: yes/no):"]
            + census.functions.sorted { $0.value > $1.value }.map { name, count in
                let index = UInt16(name.split(separator: "#").last.flatMap { Int($0) } ?? 0)
                return "  \(name): \(count) \(supported[index] == nil ? "no" : "yes")"
            }
            + ["[INFO] unread fields:"] + skipped.ranked.map { "  \($0.name): \($0.count)" })
            .joined(separator: "\n")
        print(report)
        try? report.write(
            to: RepositoryLogs.directory().appending(path: "recipe-sweep.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func census(store: RecipeStore, index: RecordIndex) -> Census {
        var census = Census()
        let registry = ConditionFunctionRegistry.standard
        for recipe in store.recipes.values {
            let keyword = editorID(recipe.workbenchKeyword, index) ?? "NULL"
            census.byWorkbench[keyword, default: 0] += 1
            if
                recipe.recipe.workbenchKeyword != nil,
                type(recipe.workbenchKeyword, index) != "KYWD"
            {
                census.unresolved.append("\(recipe.id) workbench")
            }
            if recipe.recipe.createdObject == nil {
                census.nullCreatedObject += 1
            } else if type(recipe.createdObject, index) == nil {
                census.unresolved.append("\(recipe.id) created object")
            }
            for component in recipe.components {
                guard let kind = type(component.item, index) else {
                    census.unresolved.append("\(recipe.id) component")
                    continue
                }
                census.componentTypes[kind, default: 0] += 1
            }
            for condition in recipe.recipe.conditions.conditions {
                let index = condition.functionIndex
                let name = "\(registry.name(for: index)) #\(index)"
                census.functions[name, default: 0] += 1
            }
        }
        return census
    }

    private static func type(_ id: ResolvedFormID?, _ index: RecordIndex) -> String? {
        guard let id, case let .record(indexed) = index.lookup(id) else { return nil }
        return indexed.record.type.description
    }

    private static func editorID(_ id: ResolvedFormID?, _ index: RecordIndex) -> String? {
        guard let id, case let .record(indexed) = index.lookup(id) else { return nil }
        return ESMWalk.editorID(of: indexed.record)
    }

    private static func lines(_ counts: [String: Int]) -> [String] {
        counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "  \($0.key): \($0.value)" }
    }
}
