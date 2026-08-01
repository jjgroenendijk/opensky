// ItemDefinitionStore indexing across the seven carryable families plus the
// separate container index. Fixtures are synthetic plugins built in code —
// never extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct ItemDefinitionStoreTests {
    @Test func indexesEveryCarryableFamilyUnderOneView() throws {
        let store = try makeStore()
        #expect(store.definitions.count == 7)
        #expect(store.definition(FormID(0x100))?.family == .miscellaneous)
        #expect(store.definition(FormID(0x200))?.family == .book)
        #expect(store.definition(FormID(0x300))?.family == .ingestible)
        #expect(store.definition(FormID(0x400))?.family == .ingredient)
        #expect(store.definition(FormID(0x500))?.family == .weapon)
        #expect(store.definition(FormID(0x600))?.family == .ammunition)
        #expect(store.definition(FormID(0x700))?.family == .armor)
        #expect(store.definition(FormID(0x999)) == nil)
    }

    @Test func unifiedViewCarriesNameValueWeightAndKeywords() throws {
        let store = try makeStore()
        let weapon = try #require(store.definition(FormID(0x500)))
        #expect(weapon.editorID == "IronSword")
        #expect(weapon.name == .inline("Iron Sword"))
        #expect(weapon.value == 25)
        #expect(weapon.weight == 9)
        #expect(weapon.keywords == [FormID(0x0001_E713)])
    }

    /// ALCH's gold value lives in ENIT and its weight in DATA; the unified
    /// view must not expose that split.
    @Test func ingestibleValueAndWeightComeFromDifferentFields() throws {
        let store = try makeStore()
        let potion = try #require(store.definition(FormID(0x300)))
        #expect(potion.value == 36)
        #expect(potion.weight == 0.5)
    }

    @Test func armorReachesTheStoreThroughItsOwnDecoder() throws {
        let store = try makeStore()
        let armor = try #require(store.definition(FormID(0x700)))
        #expect(armor.editorID == "ArmorIronCuirass")
        #expect(armor.value == 125)
        #expect(armor.weight == 30)
    }

    /// v1 stacking: two instances of the same base FormID stack, and two
    /// different bases never do. Per-instance data will break this later —
    /// see docs/formats/records.md.
    @Test func stackKeyIsTheBaseFormIDInV1() throws {
        let store = try makeStore()
        let first = try #require(store.definition(FormID(0x100)))
        let second = try #require(store.definition(FormID(0x100)))
        let other = try #require(store.definition(FormID(0x200)))
        #expect(first.stackKey == second.stackKey)
        #expect(first.stackKey != other.stackKey)
    }

    /// Containers are indexed separately: a CONT is not carryable, but its
    /// starting contents are what the inventory runtime needs.
    @Test func containersAreIndexedApartFromItems() throws {
        let store = try makeStore()
        #expect(store.containers.count == 1)
        #expect(store.definition(FormID(0x800)) == nil)
        let container = try #require(store.container(FormID(0x800)))
        #expect(container.base.editorID == "ChestSmall")
        #expect(container.entries.map(\.item) == [FormID(0x100), FormID(0x200)])
        #expect(container.entries.map(\.count) == [3, 1])
    }

    @Test func definitionsOfFamilyAreSortedByFormID() throws {
        let store = try makeStore()
        #expect(store.definitions(of: .miscellaneous).map(\.formID) == [FormID(0x100)])
        #expect(store.definitions(of: .book).count == 1)
    }

    @Test func malformedRecordIsSkippedAndCounted() throws {
        // A MISC whose DATA is too short to hold value + weight.
        let broken = ESMFixture.record(
            "MISC", formID: 0x101, data: ESMFixture.field("DATA", Data(count: 4))
        )
        var contents = ESMFixture.tes4()
        contents += ESMFixture.topGroup("MISC", contents: broken)
        let store = try ItemDefinitionStore(file: ESMFile(data: contents))
        #expect(store.definitions.isEmpty)
        #expect(store.skippedCounts[.miscellaneous] == 1)
        #expect(store.skippedCounts[.weapon] == 0)
    }

    @Test func emptyPluginYieldsEmptyStore() throws {
        let store = try ItemDefinitionStore(file: ESMFile(data: ESMFixture.tes4()))
        #expect(store.definitions.isEmpty)
        #expect(store.containers.isEmpty)
    }

    // MARK: - Fixture plugin

    private func makeStore() throws -> ItemDefinitionStore {
        var contents = ESMFixture.tes4()
        contents += ESMFixture.topGroup("MISC", contents: miscRecord())
        contents += ESMFixture.topGroup("BOOK", contents: bookRecord())
        contents += ESMFixture.topGroup("ALCH", contents: ingestibleRecord())
        contents += ESMFixture.topGroup("INGR", contents: ingredientRecord())
        contents += ESMFixture.topGroup("WEAP", contents: weaponRecord())
        contents += ESMFixture.topGroup("AMMO", contents: ammunitionRecord())
        contents += ESMFixture.topGroup("ARMO", contents: armorRecord())
        contents += ESMFixture.topGroup("CONT", contents: containerRecord())
        return try ItemDefinitionStore(file: ESMFile(data: contents))
    }

    private func miscRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Gold001"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Gold"))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: 1, weight: 0)
        )
        return ESMFixture.record("MISC", formID: 0x100, data: fields)
    }

    private func bookRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("SkillBook"))
        fields += ESMFixture.field(
            "DATA",
            InventoryFixture.bookData(
                flags: 0x01, kind: 0, teaches: 0x12, value: 50, weight: 1
            )
        )
        return ESMFixture.record("BOOK", formID: 0x200, data: fields)
    }

    private func ingestibleRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("PotionHealth"))
        var weight = Data()
        weight.appendUInt32(Float(0.5).bitPattern)
        fields += ESMFixture.field("DATA", weight)
        fields += ESMFixture.field(
            "ENIT", InventoryFixture.enitData(value: 36, flags: 0)
        )
        return ESMFixture.record("ALCH", formID: 0x300, data: fields)
    }

    private func ingredientRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("MountainFlower"))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: 2, weight: 0.1)
        )
        return ESMFixture.record("INGR", formID: 0x400, data: fields)
    }

    private func weaponRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("IronSword"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Iron Sword"))
        fields += InventoryFixture.keywordFields([0x0001_E713])
        fields += ESMFixture.field(
            "DATA", InventoryFixture.weaponData(value: 25, weight: 9, damage: 7)
        )
        return ESMFixture.record("WEAP", formID: 0x500, data: fields)
    }

    private func ammunitionRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("IronArrow"))
        fields += ESMFixture.field(
            "DATA",
            InventoryFixture.ammoData(
                projectile: 0x0003_4182, flags: 0x04, damage: 8, value: 1, weight: 0.1
            )
        )
        return ESMFixture.record("AMMO", formID: 0x600, data: fields)
    }

    private func armorRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("ArmorIronCuirass"))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: 125, weight: 30)
        )
        return ESMFixture.record("ARMO", formID: 0x700, data: fields)
    }

    private func containerRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("ChestSmall"))
        fields += ESMFixture.field("CNTO", InventoryFixture.cntoData(item: 0x100, count: 3))
        fields += ESMFixture.field("CNTO", InventoryFixture.cntoData(item: 0x200, count: 1))
        return ESMFixture.record("CONT", formID: 0x800, data: fields)
    }
}
