// A cell holds the references of every plugin in the load order. `Mod.esp` lists
// only `Skyrim.esm` as master and loads third, so its own records are `01xxxxxx`
// in the file and `02xxxxxx` in the load order.

@testable import FormatsTesting
import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldState
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct CellSceneBuilderLoadOrderTests {
    private static let interior: UInt32 = 0x0000_1234
    private static let modInterior: UInt32 = 0x0200_1000
    private let fixtures: CellSceneBuilderTests

    init() throws {
        fixtures = try CellSceneBuilderTests()
    }

    private func makeBuilder(device: MTLDevice) throws -> CellSceneBuilder {
        let base = try ESMFile(data: fixtures.plugin(
            interiorRecords: fixtures.interiorCellGroup(
                formID: Self.interior,
                refs: fixtures.refrRecord(formID: 0x210, base: 0x100)
                    + fixtures.refrRecord(formID: 0x211, base: 0x100)
            )
        ))
        let deleted = ESMFixture.record(
            "REFR", formID: 0x211, flags: 0x20, data: Data()
        )
        let mod = try ESMFile(data: ESMFixture.tes4(masters: ["Skyrim.esm"])
            + ESMFixture.topGroup("CELL", contents: fixtures.interiorCellGroup(
                formID: Self.interior,
                refs: fixtures.refrRecord(formID: 0x210, base: 0x100, position: SIMD3(50, 0, 0))
                    + deleted
                    + fixtures.refrRecord(formID: 0x0100_0800, base: 0x0100_0900)
            ) + fixtures.interiorCellGroup(
                formID: 0x0100_1000,
                refs: fixtures.refrRecord(formID: 0x0100_0801, base: 0x0100_0900)
            ))
            + ESMFixture.topGroup(
                "STAT", contents: fixtures.statRecord(formID: 0x0100_0900, modelPath: "mod.nif")
            ))
        let other = try ESMFile(data: ESMFixture.tes4(masters: ["Skyrim.esm"]))
        let vfs = VirtualFileSystem(dataURL: fixtures.dataURL, archiveURLs: [])
        let textures = try TextureLibrary(fileSystem: vfs, device: device)
        return CellSceneBuilder(
            file: base,
            meshes: MeshLibrary(fileSystem: vfs, device: device, textures: textures),
            textures: textures,
            fileSystem: vfs,
            plugins: [("Skyrim.esm", base), ("Other.esm", other), ("Mod.esp", mod)]
        )
    }

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func aLaterPluginOverridesAddsAndDeletesReferences() throws {
        let builder = try makeBuilder(device: #require(CellSceneBuilderTests.device))
        let scene = try builder.buildInteriorScene(cellFormID: FormID(Self.interior))
        #expect(scene.references.count == 2)
        #expect(scene.summary.totalRefCount == 2)
        let moved = try #require(scene.references.entry(for: FormID(0x210)))
        #expect(moved.placedReference?.placement.position.x == 50)
        #expect(scene.references.entry(for: FormID(0x211)) == nil)
        let added = try #require(scene.references[.plugin(name: "mod.esp", objectID: 0x800)])
        #expect(added.formID == FormID(0x0200_0800))
        #expect(added.placedReference?.base == FormID(0x0200_0900))
    }

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func aCellOnlyALaterPluginDefinesBuilds() throws {
        let builder = try makeBuilder(device: #require(CellSceneBuilderTests.device))
        let scene = try builder.buildInteriorScene(cellFormID: FormID(Self.modInterior))
        #expect(scene.references.entry(for: FormID(0x0200_0801)) != nil)
    }

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func anUnloadedReferenceOfALaterPluginIsFound() throws {
        let builder = try makeBuilder(device: #require(CellSceneBuilderTests.device))
        let lookup = builder.placedRecords
        let entry = try #require(lookup.entry(for: .plugin(name: "mod.esp", objectID: 0x801)))
        #expect(entry.formID == FormID(0x0200_0801))
        #expect(lookup.interiorCell(holding: entry.formID) == FormID(Self.modInterior))
        #expect(builder.statIndexBuildingIfNeeded()[0x0200_0900]?.modelPath == "mod.nif")
    }
}
