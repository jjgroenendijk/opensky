// CellSceneBuilder integration for the runtime reference index (issue #158):
// a reference decoded during a build must be addressable on the finished
// CellScene by ReferenceKey and by raw FormID, tagged with the children group
// it was stored in. Plugin bytes come from the synthetic ESMFixture helpers on
// CellSceneBuilderTests; a Metal device is still needed because buildScene
// uploads whatever geometry resolves.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct CellSceneBuilderReferenceIndexTests {
    private let fixtures: CellSceneBuilderTests
    private let dataURL: URL

    init() throws {
        fixtures = try CellSceneBuilderTests()
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-refindex-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    private func skyrimKey(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    // MARK: - Exterior

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func indexesReferencesByKeyAndRawFormID() throws {
        let scene = try fixtures.build(pluginData: fixtures.plugin(
            persistentRefs: fixtures.refrRecord(formID: 0x200, base: 0x100),
            temporaryRefs: fixtures.refrRecord(formID: 0x201, base: 0x100),
            statRecords: fixtures.statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        #expect(scene.references.count == 2)
        let byKey = try #require(scene.references[skyrimKey(0x200)])
        #expect(byKey.formID == FormID(0x200))
        let byFormID = try #require(scene.references.entry(for: FormID(0x201)))
        #expect(byFormID.key == skyrimKey(0x201))
        // The decoded record travels with the entry, not just its identity.
        #expect(byFormID.placedReference?.base == FormID(0x100))
        #expect(scene.references.sortedKeys() == [skyrimKey(0x200), skyrimKey(0x201)])
    }

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func tagsPersistenceFromTheOwningChildrenGroup() throws {
        let scene = try fixtures.build(pluginData: fixtures.plugin(
            persistentRefs: fixtures.refrRecord(formID: 0x200, base: 0x100),
            temporaryRefs: fixtures.refrRecord(formID: 0x201, base: 0x100)
                + fixtures.refrRecord(formID: 0x202, base: 0x100),
            statRecords: fixtures.statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        let persistent = try #require(scene.references.entry(for: FormID(0x200)))
        #expect(persistent.isPersistent)
        for raw: UInt32 in [0x201, 0x202] {
            let temporary = try #require(scene.references.entry(for: FormID(raw)))
            #expect(temporary.isPersistent == false)
        }
    }

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func indexesActorsBesideReferences() throws {
        // The ACHR has no resolvable NPC_ chain, so it never renders. It still
        // exists at runtime and must still be addressable.
        let scene = try fixtures.build(pluginData: fixtures.plugin(
            persistentRefs: fixtures.achrRecord(formID: 0x300, base: 0x400),
            temporaryRefs: fixtures.refrRecord(formID: 0x200, base: 0x100)
        ))
        #expect(scene.summary.actorDrawnCount == 0)
        #expect(scene.references.count == 2)
        let actor = try #require(scene.references[skyrimKey(0x300)])
        #expect(actor.isPersistent)
        #expect(actor.placedActor?.base == FormID(0x400))
        #expect(actor.placedReference == nil)
        #expect(scene.references.entry(for: FormID(0x200))?.placedActor == nil)
    }

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func keysUseTheBuildersPluginName() throws {
        let device = try #require(CellSceneBuilderTests.device)
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let builder = try CellSceneBuilder(
            file: ESMFile(data: fixtures.plugin(
                temporaryRefs: fixtures.refrRecord(formID: 0x201, base: 0x100)
            )),
            meshes: meshes,
            textures: textures,
            fileSystem: vfs,
            pluginName: "MyMod.esp"
        )
        let scene = try builder.buildScene(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)
        // No MAST entries in the fixture header, so every record resolves to
        // the plugin itself — lowercased by ReferenceKey.
        #expect(scene.references[.plugin(name: "mymod.esp", objectID: 0x201)] != nil)
        #expect(scene.references[skyrimKey(0x201)] == nil)
    }

    // MARK: - Interior

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func indexesInteriorReferences() throws {
        let interiorFormID: UInt32 = 0x0000_1234
        let device = try #require(CellSceneBuilderTests.device)
        let pluginData = fixtures.plugin(
            interiorRecords: fixtures.interiorCellGroup(
                formID: interiorFormID,
                refs: fixtures.refrRecord(formID: 0x210, base: 0x100)
            )
        )
        let builder = try fixtures.makeBuilder(pluginData: pluginData, device: device)
        let scene = try builder.buildInteriorScene(cellFormID: FormID(interiorFormID))
        #expect(scene.references.count == 1)
        let entry = try #require(scene.references.entry(for: FormID(0x210)))
        #expect(entry.key == skyrimKey(0x210))
        // The fixture stores interior refs in the temporary children group.
        #expect(entry.isPersistent == false)
    }

    // MARK: - Main-thread query surface

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func compositionResolvesEntriesAcrossResidentCells() throws {
        let scene = try fixtures.build(pluginData: fixtures.plugin(
            temporaryRefs: fixtures.refrRecord(formID: 0x201, base: 0x100)
        ))
        var composition = CellSceneComposition()
        composition.setCell(scene, at: CellCoordinate(x: 6, y: -2))
        #expect(composition.referenceEntry(formID: FormID(0x201))?.key == skyrimKey(0x201))
        #expect(composition.referenceEntry(key: skyrimKey(0x201))?.formID == FormID(0x201))
        #expect(composition.referenceEntry(formID: FormID(0x999)) == nil)
        composition.removeCell(at: CellCoordinate(x: 6, y: -2))
        #expect(composition.referenceEntry(key: skyrimKey(0x201)) == nil)
    }
}
