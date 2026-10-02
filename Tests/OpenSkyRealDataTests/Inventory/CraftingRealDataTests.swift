// A crafting session at a vanilla forge for a fresh player: a non-empty recipe
// list, `RecipeWeaponIronSword` eligible once its parts are added, and a craft
// that consumes exactly its parts. Run with `make test-real T='CraftingRealDataTests'`.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorld
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CraftingRealDataTests {
    /// Recipe conditions for the player, with `GetItemCount` read from `inventory`.
    final class PlayerConditions: RecipeConditionChecking {
        let inventory: InventoryRuntime

        init(inventory: InventoryRuntime) {
            self.inventory = inventory
        }

        func failingFunction(in conditions: ConditionList, sourcePlugin _: String) -> String? {
            var context = ConditionContext(subject: .player)
            let stacks = inventory.inventory(of: .player).stacks
            context.inventory = InventoryConditionResolution(counts: [
                .player: stacks.reduce(into: [:]) { $0[$1.item, default: 0] += $1.count }
            ])
            var evaluator = ConditionEvaluator(context: context)
            return evaluator.firstFailure(in: conditions.conditions)
                .map(evaluator.functionName(of:))
        }
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aForgeCraftsAnIronSwordFromItsParts() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let catalog = CraftingCatalog(
            recipes: RecipeStoreLoader.load(root: root, baseFile: file),
            itemPlugin: FormIDResolver(pluginName: "Skyrim.esm", masters: []),
            file: file
        )
        let sword = try #require(catalog.recipes.recipe(editorID: "RecipeWeaponIronSword"))
        let forgeKeyword = try #require(sword.workbenchKeyword)
        let station = try #require(catalog.stations.first { choice in
            catalog.station(workbench: choice.workbench, keywords: choice.keywords)
                .keywords.contains(forgeKeyword)
        })

        let inventory = InventoryRuntime(
            store: WorldStateStore(), baselines: InventoryBaselineResolver.build(from: file)
        )
        let conditions = PlayerConditions(inventory: inventory)
        let interaction = PlacedInteraction(
            reference: station.base, base: station.base, position: .zero,
            name: station.editorID, action: .use, actionLabel: "Activate", sounds: nil,
            station: CraftingStation(workbench: station.workbench, keywords: station.keywords)
        )
        let session = try CraftingSession(
            event: #require(CraftingActivationEvent(interaction: interaction)),
            catalog: catalog,
            inventory: inventory,
            conditions: conditions,
            skills: nil
        )
        #expect(!session.recipes.isEmpty)
        let recipe = try #require(session.recipes.first { $0.id == sword.id })
        #expect(!session.eligibility(of: recipe).isEligible)

        let parts = CraftingCatalog.required(recipe)
        for part in parts {
            try inventory.add(#require(part.item), count: part.count, to: .player)
        }
        let verdict = session.eligibility(of: recipe)
        #expect(verdict.isEligible, "verdict: \(verdict)")

        let outcome = try session.craft(recipe.id)
        #expect(outcome.consumed.map(\.item) == parts.compactMap(\.item))
        #expect(outcome.consumed.map(\.count) == parts.map(\.count))
        #expect(inventory.inventory(of: .player).stacks == [outcome.created])
        #expect(outcome.created.item == recipe.created)
        try writeReport(station: station.editorID, recipes: session.statuses)
    }

    private func writeReport(station: String, recipes: [CraftingRecipeStatus]) throws {
        let ready = recipes.count(where: \.eligibility.isEligible)
        var functions: [String: Int] = [:]
        for status in recipes {
            if let name = status.eligibility.failingFunction {
                functions[name, default: 0] += 1
            }
        }
        let report = (["[INFO] station \(station): \(recipes.count) recipes, \(ready) ready"]
            + functions.sorted { $0.key < $1.key }.map { "failing \($0.key): \($0.value)" })
            .joined(separator: "\n")
        let logs = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try report.write(
            to: logs.appending(path: "crafting-forge.txt"), atomically: true, encoding: .utf8
        )
    }
}
