// COBJ lookup and the workbench-keyword and created-object indexes over synthetic plugins.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct RecipeStoreTests {
    private static let forge: UInt32 = 0x0008_8105
    private static let tanningRack: UInt32 = 0x0007_866A
    private static let ironSword: UInt32 = 0x0001_2EB7

    private static func id(_ objectID: UInt32, _ plugin: String = "Base.esm") -> ResolvedFormID {
        ResolvedFormID(plugin: plugin, objectID: objectID)
    }

    private static func store() throws -> RecipeStore {
        let file = try ESMFixture.plugin(records: [
            RecipeFixture.recordBytes(
                formID: 0x10, editorID: "RecipeIronSword",
                components: [(0x0005_ACE4, 1)],
                createdObject: ironSword, workbenchKeyword: forge
            ),
            RecipeFixture.recordBytes(
                formID: 0x11, editorID: "TemperIronSword",
                createdObject: ironSword, workbenchKeyword: 0x0008_8108
            ),
            RecipeFixture.recordBytes(
                formID: 0x12, editorID: "RecipeLeatherStrips",
                createdObject: 0x0008_00E4, workbenchKeyword: tanningRack, createdCount: 4
            ),
            RecipeFixture.recordBytes(
                formID: 0x13, editorID: "RecipeIronDagger",
                createdObject: 0x0001_394D, workbenchKeyword: forge
            )
        ])
        return RecipeStore(plugins: [("Base.esm", file)])
    }

    @Test func looksUpRecipesAndResolvesTheirLinks() throws {
        let store = try Self.store()
        #expect(store.recipes.count == 4)
        let recipe = try #require(store.recipe(editorID: "recipeironsword"))
        #expect(recipe.id == Self.id(0x10))
        #expect(recipe.createdObject == Self.id(Self.ironSword))
        #expect(recipe.workbenchKeyword == Self.id(Self.forge))
        #expect(recipe.components.map(\.item) == [Self.id(0x0005_ACE4)])
        #expect(recipe.components.map(\.count) == [1])
        #expect(store.recipe(Self.id(0x12))?.recipe.effectiveCreatedCount == 4)
        #expect(store.skippedRecords.isEmpty)
    }

    @Test func indexesRecipesByWorkbenchKeyword() throws {
        let store = try Self.store()
        let forgeRecipes = store.recipes(workbenchKeyword: Self.id(Self.forge))
        #expect(forgeRecipes.map(\.recipe.editorID) == ["RecipeIronSword", "RecipeIronDagger"])
        #expect(store.recipes(workbenchKeyword: Self.id(Self.tanningRack)).count == 1)
        #expect(store.recipes(workbenchKeyword: Self.id(0x999)).isEmpty)
    }

    @Test func indexesRecipesByCreatedObject() throws {
        let store = try Self.store()
        let swordRecipes = store.recipes(creating: Self.id(Self.ironSword))
        #expect(swordRecipes.map(\.recipe.editorID) == ["RecipeIronSword", "TemperIronSword"])
        #expect(store.recipes(creating: Self.id(0x999)).isEmpty)
    }

    /// An override moves the recipe to its new station and drops it from the old one.
    @Test func overrideReindexesTheRecipe() throws {
        let base = try ESMFixture.plugin(records: [RecipeFixture.recordBytes(
            formID: 0x10, editorID: "RecipeIronSword",
            createdObject: Self.ironSword, workbenchKeyword: Self.forge
        )])
        let patch = try ESMFixture.plugin(masters: ["Base.esm"], records: [
            RecipeFixture.recordBytes(
                formID: 0x10, editorID: "RecipeIronSword",
                createdObject: Self.ironSword, workbenchKeyword: Self.tanningRack
            )
        ])
        let store = RecipeStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])
        #expect(store.recipes(workbenchKeyword: Self.id(Self.forge)).isEmpty)
        #expect(store.recipes(workbenchKeyword: Self.id(Self.tanningRack)).first?.sourcePlugin
            == "Patch.esp")
    }
}
