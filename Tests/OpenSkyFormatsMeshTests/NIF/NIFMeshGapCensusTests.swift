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
                shaderType: 14, shaderFlags1: 0x1, shaderFlags2: 0x2
            )),
            .init("BSXFlags", Data(count: 8))
        ]))

        #expect(census.fileCount == 1)
        #expect(census.blockTypes.uses["BSXFlags"] == 1)
        #expect(census.blockTypes.left(where: NIFBlockTypes.handled.contains).map(\.name)
            == ["BSXFlags"])
        #expect(census.lightingTypes.uses == ["14 Sparkle Snow": 1])
        #expect(!NIFMeshGapCensus.readLightingTypes.contains("14 Sparkle Snow"))
        #expect(census.lightingFlags.uses.keys.sorted()
            == ["SLSF1 0 Specular", "SLSF2 1 LOD_Landscape"])
        #expect(census.lightingFlags.done(where: NIFMeshGapCensus.readLightingFlags.contains) == 1)
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
