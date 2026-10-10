// Ref ids onto the current load order: each kind, light plugins, and a missing or
// reordered plugin.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyFormatsTesting
@testable import OpenSkySave
import Testing

struct ESSLoadOrderMappingTests {
    private static func file(
        plugins: [String] = ["Skyrim.esm", "Update.esm", "Dawnguard.esm"],
        light: [String] = ["ccQDRSSE001-SurvivalMode.esl"],
        formIDs: [UInt32] = [0x0200_0D62, 0xFE00_0801, 0x0100_0ABC]
    ) throws -> ESSFile {
        var fixture = ESSFixture()
        fixture.plugins = plugins
        fixture.lightPlugins = light
        fixture.formIDArray = formIDs
        return try ESSFile(data: fixture.build())
    }

    @Test func resolvesEachRefIDKind() throws {
        let current = ["Skyrim.esm", "Update.esm", "Dawnguard.esm", "ccQDRSSE001-SurvivalMode.esl"]
        let mapping = try ESSLoadOrderMapping(file: Self.file(), currentPlugins: current)
        #expect(mapping.resolve(ESSRefID(kind: .formIDArray, value: 1))
            == .form(ResolvedFormID(plugin: "Dawnguard.esm", objectID: 0xD62)))
        #expect(mapping.resolve(ESSRefID(kind: .formIDArray, value: 2))
            == .form(ResolvedFormID(plugin: "ccQDRSSE001-SurvivalMode.esl", objectID: 0x801)))
        #expect(mapping.resolve(ESSRefID(kind: .default, value: 0x14))
            == .form(ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x14)))
        #expect(mapping.resolve(ESSRefID(kind: .created, value: 0x22)) == .created(0x22))
        #expect(mapping.resolve(ESSRefID(raw: 0)) == .null)
        #expect(mapping.resolve(ESSRefID(kind: .formIDArray, value: 9))
            == .unmapped(.formIDArrayIndexOutOfRange(9)))
        #expect(mapping.resolve(ESSRefID(kind: .unknown, value: 1)) == .unmapped(.unknownRefIDKind))
    }

    @Test func pluginNotLoadedIsCountedNotFatal() throws {
        let mapping = try ESSLoadOrderMapping(
            file: Self.file(), currentPlugins: ["Skyrim.esm", "Update.esm"]
        )
        #expect(mapping.resolve(ESSRefID(kind: .formIDArray, value: 1))
            == .unmapped(.pluginNotLoaded("Dawnguard.esm")))
        #expect(mapping.comparison.missing == ["Dawnguard.esm", "ccQDRSSE001-SurvivalMode.esl"])
        #expect(mapping.resolve(runtimeFormID: 0x0900_0001) == .unmapped(.pluginIndexOutOfRange(9)))
        #expect(mapping.resolve(runtimeFormID: 0xFE00_5001)
            == .unmapped(.lightPluginIndexOutOfRange(5)))
    }

    @Test func reorderedPluginMapsByNameAndIsReported() throws {
        let current = ["Skyrim.esm", "Dawnguard.esm", "Update.esm", "HearthFires.esm"]
        let mapping = try ESSLoadOrderMapping(file: Self.file(light: []), currentPlugins: current)
        let resolved = ResolvedFormID(plugin: "Dawnguard.esm", objectID: 0xD62)
        #expect(mapping.resolve(ESSRefID(kind: .formIDArray, value: 1)) == .form(resolved))
        #expect(mapping.currentFormID(resolved) == FormID(0x0100_0D62))
        #expect(mapping.comparison.isReordered)
        #expect(mapping.comparison.added == ["HearthFires.esm"])
        #expect(mapping.comparison.rows.map(\.currentPosition) == [0, 2, 1])
    }
}
