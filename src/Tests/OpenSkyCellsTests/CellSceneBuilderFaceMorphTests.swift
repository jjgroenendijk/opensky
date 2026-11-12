// An NPC with a baked FaceGen head gets an expression morph buffer when a head part's
// editor ID names a skinned head shape and its expression TRI has the shape's vertex
// count. A head built from its parts pairs each part's TRI of the same vertex count.
// Each other case is a miss with a reason. Synthetic plugin, NIF, and TRI only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyTagsTesting
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderFaceMorphTests: CellSceneBuilderFixture {
    let dataURL: URL
    private let tri = "meshes\\actors\\character\\facegendata\\test.tri"

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    /// A root, a bone, and one skinned head shape named `MaleHeadTest`; the TRI fixture
    /// has three vertices.
    private func faceGenHead(vertexCount: Int) -> Data {
        let positions = Array([
            SIMD3<Float>(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(0, 1, 0),
            SIMD3(1, 1, 0)
        ]
        .prefix(vertexCount))
        let records = positions.map { NIFFixture.skinnedVertex(position: $0) }
        let shape = NIFFixture.bsTriShape(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 2),
            skinRef: 3, shaderPropertyRef: 6, attributes: 0x43, strideDwords: 8,
            vertexCountOverride: positions.count
        )
        let blocks = NIFFixture.dynamicSkinBlocks(
            root: NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0),
                children: [1, 2]
            ),
            bone: NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(nameIndex: 1)),
            inherited: shape,
            positions: positions,
            partition: NIFFixture.skinPartition(
                vertexRecords: records, topLevelVertexRecords: [], triangles: [0, 1, 2],
                bonePalette: [0],
                skin: (
                    Array(repeating: SIMD4(1, 0, 0, 0), count: vertexCount),
                    Array(repeating: .zero, count: vertexCount)
                )
            )
        )
        return NIFFixture.file(blocks: blocks, strings: ["Root", "Head", "MaleHeadTest"])
    }

    private func formIDField(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }

    /// The actor chain with a FaceGen-head race and an NPC_ that names head part 0x400.
    private func records(headPartName: String) -> [String: Data] {
        var records = actorChainRecords(npc: 0x800)
        var acbs = Data(count: 4)
        acbs.append(Data(count: 20))
        records["NPC_"] = ESMFixture.record("NPC_", formID: 0x800, data: ESMFixture.field(
            "ACBS", acbs
        ) + formIDField("RNAM", 0x100) + formIDField("PNAM", 0x400))
        var raceData = Data(count: 0x20)
        raceData.appendUInt32(0x102)
        records["RACE"] = ESMFixture.record(
            "RACE",
            formID: 0x100,
            data: formIDField("WNAM", 0x200)
                + ESMFixture.field("DATA", raceData)
                + ESMFixture.field("MNAM", Data())
                + ESMFixture.field("ANAM", ESMFixture.zstring("skel_m.nif"))
        )
        var expression = Data()
        expression.appendUInt32(1)
        records["HDPT"] = ESMFixture.record(
            "HDPT",
            formID: 0x400,
            data: ESMFixture.field(
                "EDID", ESMFixture.zstring(headPartName)
            ) + ESMFixture.field("MODL", ESMFixture.zstring("actors\\character\\head.nif"))
                + ESMFixture.field("NAM0", expression)
                + ESMFixture.field(
                    "NAM1",
                    ESMFixture.zstring("actors\\character\\facegendata\\test.tri")
                )
        )
        return records
    }

    /// The actor 0x900 draws its head from its head parts.
    private let assembledHead = WorldStateSnapshot(
        entries: [WorldStateSnapshotEntry(
            key: .plugin(name: "skyrim.esm", objectID: 0x900),
            delta: ReferenceStateDelta(components: [
                .actorPresentation: ActorPresentationState(headSource: .assembled).erased
            ])
        )],
        nextGeneratedSequence: 1, sequence: 1
    )

    private func faceMorph(
        headPartName: String = "MaleHeadTest",
        triFile: Data = TRIFixture.file(),
        headVertices: Int = 3,
        state: WorldStateSnapshot = .empty
    ) throws -> FaceMorphPlayback? {
        let head = faceGenHead(vertexCount: headVertices)
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        try writeLooseFile(
            "meshes/actors/character/facegendata/facegeom/skyrim.esm/00000800.nif",
            head
        )
        try writeLooseFile("meshes/actors/character/head.nif", head)
        try writeLooseFile("meshes/actors/character/facegendata/test.tri", triFile)
        let scene = try build(
            pluginData: plugin(
                temporaryRefs: achrRecord(formID: 0x900, base: 0x800),
                modelBaseRecords: records(headPartName: headPartName)
            ),
            state: state
        )
        return scene.renderScene.animations.lazy.compactMap { $0 as? FaceMorphPlayback }.first
    }

    @Test(.enabled(if: Self.hasDevice)) func aMatchingHeadPartPairsItsTRI() throws {
        let playback = try #require(try faceMorph(
            headPartName: "MaleHeadTest",
            triFile: TRIFixture.file()
        ))
        #expect(playback.pairedPaths == [tri])
        #expect(playback.misses.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func aHeadPartWithoutAShapeIsAMiss() throws {
        let playback = try #require(try faceMorph(
            headPartName: "OtherHead",
            triFile: TRIFixture.file()
        ))
        #expect(playback.pairedPaths.isEmpty)
        #expect(playback.misses.map(\.reason) == ["no FaceGen shape named OtherHead"])
    }

    @Test(.enabled(if: Self.hasDevice)) func aBrokenTRIIsAMiss() throws {
        let playback = try #require(try faceMorph(
            headPartName: "MaleHeadTest",
            triFile: Data([1, 2])
        ))
        #expect(playback.pairedPaths.isEmpty)
        #expect(playback.misses.first?.reason.hasPrefix("invalid expression TRI \(tri)") == true)
    }

    @Test(.enabled(if: Self.hasDevice)) func aHeadWithOtherVerticesIsAMiss() throws {
        let playback = try #require(try faceMorph(headVertices: 4))
        #expect(playback.pairedPaths.isEmpty)
        #expect(playback.misses.map(\.reason) == [
            "vertex count mismatch for MaleHeadTest: TRI 3, mesh 4"
        ])
    }

    @Test(.enabled(if: Self.hasDevice)) func anAssembledHeadPairsTheTRIOfItsHeadPart() throws {
        let playback = try #require(try faceMorph(state: assembledHead))
        #expect(playback.pairedPaths == [tri])
        #expect(playback.misses.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func anAssembledHeadWithOtherVerticesHasNoMorphs() throws {
        #expect(try faceMorph(headVertices: 4, state: assembledHead) == nil)
    }
}
