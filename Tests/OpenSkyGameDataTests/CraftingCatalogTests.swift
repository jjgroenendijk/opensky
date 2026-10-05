// Station query, recipe listing, and eligibility verdicts over synthetic recipes.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct CraftingCatalogTests {
    static let forge: UInt32 = 0x0008_8105
    static let tanningRack: UInt32 = 0x0007_866A
    static let ingot: UInt32 = 0x0005_ACE4
    static let leather: UInt32 = 0x0008_00E4
    static let sword: UInt32 = 0x0001_2EB7

    static func catalog() throws -> CraftingCatalog {
        let file = try ESMFixture.plugin(records: [
            RecipeFixture.recordBytes(
                formID: 0x10, editorID: "RecipeIronSword",
                components: [(ingot, 1), (leather, 1), (ingot, 1)],
                createdObject: sword, workbenchKeyword: forge
            ),
            RecipeFixture.recordBytes(
                formID: 0x11, editorID: "RecipeLeather",
                createdObject: leather, workbenchKeyword: tanningRack, createdCount: 4
            )
        ])
        return CraftingCatalog(
            recipes: RecipeStore(plugins: [("Base.esm", file)]),
            itemPlugin: FormIDResolver(pluginName: "Base.esm", masters: []),
            stations: []
        )
    }

    static let forgeBench = Workbench(benchType: .createObject, skillIndex: 10)

    @Test func aStationOffersOnlyTheRecipesOfItsKeywords() throws {
        let catalog = try Self.catalog()
        let station = catalog.station(
            workbench: Self.forgeBench, keywords: [FormID(0x99), FormID(Self.forge)]
        )
        #expect(station.keywords == [ResolvedFormID(plugin: "Base.esm", objectID: Self.forge)])
        #expect(station.skill == ActorValueIdentity.index(named: "Smithing"))
        let recipes = catalog.recipes(at: station)
        #expect(recipes.map(\.editorID) == ["RecipeIronSword"])
        #expect(recipes.first?.created == FormID(Self.sword))
    }

    @Test func aStationWithNoRecipeKeywordListsNothing() throws {
        let catalog = try Self.catalog()
        let station = catalog.station(
            workbench: Workbench(benchType: .alchemy, skillIndex: 16), keywords: [FormID(0x99)]
        )
        #expect(station.keywords.isEmpty)
        #expect(catalog.recipes(at: station).isEmpty)
    }

    @Test func requiredPartsMergeRepeatedComponents() throws {
        let recipe = try #require(Self.catalog().recipes(at: Self.forgeStation()).first)
        let required = CraftingCatalog.required(recipe)
        #expect(required.map(\.item) == [FormID(Self.ingot), FormID(Self.leather)])
        #expect(required.map(\.count) == [2, 1])
    }

    @Test func theVerdictNamesShortfallsAndTheFailingFunction() throws {
        let recipe = try #require(Self.catalog().recipes(at: Self.forgeStation()).first)
        let known: (FormID) -> Bool = { _ in true }
        let short = CraftingCatalog.eligibility(
            of: recipe, held: { $0 == FormID(Self.ingot) ? 1 : 0 },
            isKnownItem: known, failingFunction: nil
        )
        #expect(!short.isEligible)
        #expect(short.shortfalls == [
            ComponentShortfall(item: FormID(Self.ingot), required: 2, held: 1),
            ComponentShortfall(item: FormID(Self.leather), required: 1, held: 0)
        ])
        let gated = CraftingCatalog.eligibility(
            of: recipe, held: { _ in 9 }, isKnownItem: known, failingFunction: "HasPerk"
        )
        #expect(gated.failingFunction == "HasPerk")
        #expect(gated.shortfalls.isEmpty)
        #expect(!gated.isEligible)
        let ready = CraftingCatalog.eligibility(
            of: recipe, held: { _ in 9 }, isKnownItem: known, failingFunction: nil
        )
        #expect(ready.isEligible)
        let unknown = CraftingCatalog.eligibility(
            of: recipe, held: { _ in 9 }, isKnownItem: { _ in false }, failingFunction: nil
        )
        #expect(unknown.hasUnresolvedItem)
    }

    @Test func localFormIDInvertsResolution() {
        let resolver = FormIDResolver(pluginName: "Mod.esp", masters: ["Skyrim.esm"])
        let master = ResolvedFormID(plugin: "skyrim.esm", objectID: 0x12EB7)
        let own = ResolvedFormID(plugin: "Mod.esp", objectID: 0x801)
        #expect(resolver.localFormID(of: master) == FormID(0x0001_2EB7))
        #expect(resolver.localFormID(of: own) == FormID(0x0100_0801))
        #expect(resolver.localFormID(of: ResolvedFormID(plugin: "Other.esp", objectID: 1)) == nil)
        #expect(resolver.localFormID(of: own).flatMap(resolver.resolve) == own)
    }

    static func forgeStation() throws -> CraftingStationInfo {
        try catalog().station(workbench: forgeBench, keywords: [FormID(forge)])
    }
}

extension CraftingCatalogTests {
    @Test func aTemperingBenchListsNothing() throws {
        let station = try Self.catalog().station(
            workbench: Workbench(benchType: .smithingWeapon, skillIndex: 10),
            keywords: [FormID(Self.forge)]
        )
        #expect(station.keywords.isEmpty)
    }
}
