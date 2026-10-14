// NIFMeshGapCensus: block types, shader types and flags, and failures over synthetic
// meshes (docs/tools/gaps.md).

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFMeshGapCensusTests {
    @Test func countsBlockTypesShaderTypesAndFlags() {
        var census = NIFMeshGapCensus()
        census.record(data: NIFFixture.file(blocks: [
            .init("BSTriShape", NIFFixture.staticTriangleShape(shaderPropertyRef: 1)),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty(
                shaderType: 7, shaderFlags1: 0x2001, shaderFlags2: 0
            )),
            .init("BSXFlags", Data(count: 8))
        ]))

        #expect(census.fileCount == 1)
        #expect(census.blockTypes.uses["BSXFlags"] == 1)
        #expect(census.blockTypes.left(where: NIFBlockTypes.handled.contains).map(\.name)
            == ["BSXFlags"])
        #expect(census.lightingTypes.uses == ["7 Parallax Occ": 1])
        #expect(!NIFMeshGapCensus.readLightingTypes.contains("7 Parallax Occ"))
        #expect(census.lightingFlags.uses.keys.sorted()
            == ["SLSF1 0 Specular", "SLSF1 13 Non_Projective_Shadows"])
        #expect(census.lightingFlags.done(where: NIFMeshGapCensus.readLightingFlags.contains) == 1)
    }

    @Test func everyFlagTheVanillaMeshesSetCountsAsDone() {
        let vanilla: [(word: Int, bit: Int)] = [
            (1, 1), (1, 3), (1, 8), (1, 9), (1, 10), (1, 16), (1, 18), (1, 19), (1, 21),
            (1, 25), (1, 26), (1, 27), (1, 29), (1, 31), (2, 0), (2, 1), (2, 2), (2, 3),
            (2, 5), (2, 7), (2, 15), (2, 21), (2, 28), (2, 31)
        ]
        for flag in vanilla.map({ NIFShaderFlag(word: $0.word, bit: $0.bit) }) {
            #expect(NIFMeshGapCensus.readLightingFlags.contains(flag.name), "\(flag.name)")
        }
        #expect(NIFMeshGapCensus.readLightingTypes.isSuperset(of: [
            "14 Sparkle Snow", "18 LOD Landscape Noise"
        ]))
    }

    @Test func aFileThatDoesNotOpenIsOneFailure() {
        var census = NIFMeshGapCensus()
        census.record(data: Data("not a mesh".utf8))
        #expect(census.failures.total == 1)
        #expect(census.blockTypes.total == 0)
    }

    @Test func flagNamesFollowNifXML() {
        let flags = NIFShaderFlag.set(in: 0x8000_0000, 0x2000_0010)
        #expect(flags.map(\.name) == [
            "SLSF1 31 ZBuffer_Test", "SLSF2 4 Double_Sided", "SLSF2 29 Tree_Anim"
        ])
        #expect(NIFLightingShaderType.name(16) == "16 Eye Envmap")
        #expect(NIFLightingShaderType.name(40) == "40 unknown")
    }
}
