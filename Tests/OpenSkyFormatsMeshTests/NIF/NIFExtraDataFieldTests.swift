// Each field of the extra data values, read by name rather than through `==`
// (docs/formats/nif-extra-data.md).

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFExtraDataFieldTests {
    private func extra(
        _ type: String,
        _ payload: Data,
        strings: [String] = []
    ) throws -> NIFExtraData {
        let data = NIFBlockFixture.extraData(nameIndex: strings.isEmpty ? 0xFFFF_FFFF : 0, payload)
        let file = try NIFFile(data: NIFFixture.file(blocks: [.init(type, data)], strings: strings))
        return try #require(NIFBlockDecoders.decode(
            file.blocks[0],
            header: file.header
        ) as? NIFExtraData)
    }

    @Test func keepsTheBlockName() throws {
        let named = try extra("NiFloatExtraData", NIFBlockFixture.floats([2]), strings: ["Scale"])
        #expect(named.name == "Scale")
    }

    @Test func everyBSXBitHasItsName() throws {
        let decoded = try extra("BSXFlags", NIFBlockFixture.uint32(0x1FFF))
        guard case let .flags(flags) = decoded.value else {
            Issue.record("BSXFlags gave \(decoded.value)")
            return
        }
        let named: [NIFBSXFlags] = [
            .animated, .havok, .ragdoll, .complex, .addon, .editorMarker, .dynamic,
            .articulated, .needsTransformUpdates, .externalEmittance, .magicShaderParticles,
            .lights, .breakable
        ]
        #expect(named.map(\.rawValue) == (0 ..< 13).map { 1 << $0 })
        #expect(named.allSatisfy(flags.contains))
    }

    @Test func decalPlacementKeepsItsVectors() throws {
        var payload = NIFBlockFixture.floats([0.75])
        payload.appendUInt16(1)
        payload.appendUInt16(2)
        payload.append(NIFBlockFixture.floats([1, 2, 3, 4, 5, 6, 0, 1, 0, 1, 0, 0]))
        let decoded = try extra("BSDecalPlacementVectorExtraData", payload)
        guard case let .decalPlacement(decal) = decoded.value else {
            Issue.record("decal placement gave \(decoded.value)")
            return
        }
        #expect(decal.value == 0.75)
        #expect(decal.points == [SIMD3(1, 2, 3), SIMD3(4, 5, 6)])
        #expect(decal.normals == [SIMD3(0, 1, 0), SIMD3(1, 0, 0)])
    }

    @Test func boneLODKeepsDistanceAndBone() throws {
        var bones = NIFBlockFixture.uint32(1)
        bones.append(NIFBlockFixture.uint32(500))
        bones.append(NIFBlockFixture.uint32(0))
        let decoded = try extra("BSBoneLODExtraData", bones, strings: ["NPC Spine"])
        guard case let .boneLOD(entries) = decoded.value, let entry = entries.first else {
            Issue.record("bone LOD gave \(decoded.value)")
            return
        }
        #expect(entry.distance == 500)
        #expect(entry.boneName == "NPC Spine")
    }
}
