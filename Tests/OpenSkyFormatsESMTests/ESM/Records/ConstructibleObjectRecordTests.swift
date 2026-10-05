// COBJ over synthetic records. Layout: docs/formats/recipes.md.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ConstructibleObjectRecordTests {
    private static let hasPerk: UInt16 = 448

    @Test func decodesRecipe() throws {
        let bytes = RecipeFixture.recordBytes(
            formID: 0x42,
            editorID: "RecipeWeaponIronSword",
            components: [(0x0005_ACE4, 1), (0x0008_00E4, 2)],
            conditions: [DialogueFixture.condition(
                functionIndex: Self.hasPerk, comparisonValue: 1, parameter1: 0x000C_B40D
            )],
            createdObject: 0x0001_2EB7,
            workbenchKeyword: 0x0008_8105,
            createdCount: 3
        )
        let recipe = try ConstructibleObject(record: ESMFixture.parseRecord(bytes))
        #expect(recipe.formID == FormID(0x42))
        #expect(recipe.editorID == "RecipeWeaponIronSword")
        #expect(recipe.components == [
            .init(item: FormID(0x0005_ACE4), count: 1),
            .init(item: FormID(0x0008_00E4), count: 2)
        ])
        #expect(recipe.declaredComponentCount == 2)
        #expect(recipe.conditions.conditions.count == 1)
        #expect(recipe.conditions.conditions.first?.functionIndex == Self.hasPerk)
        #expect(recipe.conditions.conditions.first?.parameter1.asFormID == FormID(0x000C_B40D))
        #expect(recipe.createdObject == FormID(0x0001_2EB7))
        #expect(recipe.workbenchKeyword == FormID(0x0008_8105))
        #expect(recipe.createdCount == 3)
        #expect(recipe.effectiveCreatedCount == 3)
        #expect(recipe.skipped.isEmpty)
    }

    @Test func missingCreatedCountMeansOne() throws {
        let bytes = RecipeFixture.recordBytes(formID: 1, editorID: "Plain", createdObject: 0x10)
        let recipe = try ConstructibleObject(record: ESMFixture.parseRecord(bytes))
        #expect(recipe.createdCount == nil)
        #expect(recipe.effectiveCreatedCount == 1)
        #expect(recipe.components.isEmpty)
        #expect(recipe.workbenchKeyword == nil)
    }

    @Test func rejectsOtherRecordTypes() throws {
        let record = try ESMFixture.parseRecord(ESMFixture.record("FLOR", formID: 1, data: Data()))
        #expect(throws: ESMError.self) {
            try ConstructibleObject(record: record)
        }
    }

    /// A short CNTO or NAM1 costs only itself; the rest of the recipe decodes.
    @Test func survivesTruncatedFields() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Short"))
        fields += ESMFixture.field("CNTO", Data([1, 2, 3]))
        fields += InventoryFixture.formIDField("CNAM", 0x20)
        fields += ESMFixture.field("NAM1", Data([1]))
        fields += ESMFixture.field("ZZZZ", Data())
        let record = try ESMFixture.parseRecord(ESMFixture.record("COBJ", formID: 1, data: fields))
        let recipe = try ConstructibleObject(record: record)
        #expect(recipe.editorID == "Short")
        #expect(recipe.components.isEmpty)
        #expect(recipe.createdObject == FormID(0x20))
        #expect(recipe.createdCount == nil)
        #expect(recipe.skipped.counts == [
            .malformedField("CNTO"): 1, .malformedField("NAM1"): 1, .unknownField("ZZZZ"): 1
        ])
    }
}
