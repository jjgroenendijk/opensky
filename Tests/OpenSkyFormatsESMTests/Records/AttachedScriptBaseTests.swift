@testable import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite("Reference scripts over base scripts", .tags(.parser))
struct AttachedScriptBaseTests {
    @Test("a base script runs on a reference without one")
    func aBaseScriptRunsAlone() throws {
        let base = try scripts(.init("OreVeinScript", properties: [.init("Count", .integer(3))]))
        let merged = [AttachedScript]().overlaying(base: base)
        #expect(merged == base)
    }

    @Test("a same-named reference script overrides one base property and keeps the rest")
    func aReferenceOverridesOneProperty() throws {
        let base = try scripts(.init("OreVeinScript", properties: [
            .init("Count", .integer(3)), .init("Ore", .string("Iron"))
        ]))
        let own = try scripts(.init("oreveinscript", properties: [.init("Count", .integer(9))]))
        let merged = own.overlaying(base: base)
        #expect(merged.count == 1)
        #expect(merged.first?.name == "oreveinscript")
        let values = Dictionary(uniqueKeysWithValues: merged[0].properties
            .map { ($0.name, $0.value) })
        #expect(values == ["Count": .integer(9), "Ore": .string("Iron")])
    }

    @Test("other scripts of both records are kept, and a removed flag wins")
    func otherScriptsStay() throws {
        let base = try scripts(.init("BaseOnly", properties: []), .init("Dropped", properties: []))
        let own = try scripts(
            .init("RefOnly", properties: []),
            .init("Dropped", flags: 2, properties: [])
        )
        let merged = own.overlaying(base: base)
        #expect(merged.map(\.name) == ["BaseOnly", "Dropped", "RefOnly"])
        #expect(merged.filter { !$0.isRemoved }.map(\.name) == ["BaseOnly", "RefOnly"])
    }

    private func scripts(_ entries: VMADFixture.Script...) throws -> [AttachedScript] {
        var data = ScriptData()
        let field = ESMField(type: "VMAD", data: VMADFixture.payload(scripts: entries))
        _ = try data.decode(field: field)
        return data.scripts
    }
}
