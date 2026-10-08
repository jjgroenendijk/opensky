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

        func failingFunction(
            in conditions: ConditionList,
            sourcePlugin _: String,
            temperingEnchanted: Bool?
        ) -> String? {
            var context = ConditionContext(subject: .player)
            context.tempering = TemperingConditionResolution(isEnchanted: temperingEnchanted)
            let stacks = inventory.inventory(of: .player).stacks
            context.inventory = InventoryConditionResolution(counts: [
                .player: stacks.reduce(into: [:]) { $0[$1.item, default: 0] += $1.count }
            ])
            var evaluator = ConditionEvaluator(context: context)
            return evaluator.firstFailure(in: conditions.conditions)
                .map(evaluator.functionName(of:))
        }

        func skillLevel(at _: Int32) -> Float? {
            15
        }
    }

    private struct Bench {
        let session: CraftingSession
        let inventory: InventoryRuntime
        let recipe: CraftingRecipe
        let stationName: String
    }

    /// A session at the first vanilla station that offers the recipe `editorID`.
    private func bench(offering editorID: String) throws -> Bench {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let catalog = CraftingCatalog(
            recipes: RecipeStoreLoader.load(root: root, baseFile: file),
            itemPlugin: FormIDResolver(pluginName: "Skyrim.esm", masters: []),
            file: file
        )
        let wanted = try #require(catalog.recipes.recipe(editorID: editorID))
        let keyword = try #require(wanted.workbenchKeyword)
        let station = try #require(catalog.stations.first { choice in
            catalog.station(workbench: choice.workbench, keywords: choice.keywords)
                .keywords.contains(keyword)
        })
        let inventory = InventoryRuntime(
            store: WorldStateStore(), baselines: InventoryBaselineResolver.build(from: file)
        )
        let interaction = PlacedInteraction(
            reference: station.base, base: station.base, position: .zero,
            name: station.editorID, action: .use, actionLabel: "Activate", sounds: nil,
            station: CraftingStation(workbench: station.workbench, keywords: station.keywords)
        )
        let session = try CraftingSession(
            event: #require(CraftingActivationEvent(interaction: interaction)),
            catalog: catalog,
            inventory: inventory,
            conditions: PlayerConditions(inventory: inventory),
            skills: nil
        )
        let recipe = try #require(session.recipes.first { $0.id == wanted.id })
        return Bench(
            session: session, inventory: inventory, recipe: recipe, stationName: station.editorID
        )
    }

    private func addParts(of recipe: CraftingRecipe, to inventory: InventoryRuntime) throws {
        for part in CraftingCatalog.required(recipe) {
            try inventory.add(#require(part.item), count: part.count, to: .player)
        }
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aForgeCraftsAnIronSwordFromItsParts() throws {
        let bench = try bench(offering: "RecipeWeaponIronSword")
        let recipe = bench.recipe
        #expect(!bench.session.recipes.isEmpty)
        #expect(!bench.session.eligibility(of: recipe).isEligible)
        try addParts(of: recipe, to: bench.inventory)
        let verdict = bench.session.eligibility(of: recipe)
        #expect(verdict.isEligible, "verdict: \(verdict)")

        let parts = CraftingCatalog.required(recipe)
        let outcome = try bench.session.craft(recipe.id)
        #expect(outcome.consumed.map(\.item) == parts.compactMap(\.item))
        #expect(outcome.consumed.map(\.count) == parts.map(\.count))
        #expect(bench.inventory.inventory(of: .player).stacks == [outcome.created])
        #expect(outcome.created.item == recipe.created)
        try writeReport(station: bench.stationName, recipes: bench.session.statuses)
    }

    /// `TemperArmorIronCuirass`: one iron ingot, gated by `EPTemperingItemIsEnchanted != 1`
    /// or `HasPerk`. A plain cuirass passes the first condition.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func anArmorTableImprovesACarriedIronCuirass() throws {
        let bench = try bench(offering: "TemperArmorIronCuirass")
        let cuirass = try #require(bench.recipe.created)
        #expect(bench.session.station.improves)
        #expect(bench.session.statuses.isEmpty)
        try bench.inventory.add(cuirass, count: 1, to: .player)
        try addParts(of: bench.recipe, to: bench.inventory)
        let status = try #require(bench.session.statuses.first { $0.recipe.id == bench.recipe.id })
        #expect(status.isReady, "verdict: \(status.eligibility)")

        let outcome = try bench.session.craft(bench.recipe.id)
        #expect(outcome.improved == TemperStep(from: 0, to: 1))
        #expect(bench.inventory.count(of: cuirass, in: .player) == 1)
        #expect(bench.inventory.temperLevel(of: cuirass, in: .player) == 1)
        #expect(bench.inventory.inventory(of: .player).stacks.map(\.item) == [cuirass])
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
