// `NiTriShape`, `BSLODTriShape`, and `NiTriShapeData` over synthetic blocks
// (docs/formats/nif.md#nitrishape).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFLegacyTriShapeTests {
    private static let positions: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)]

    @Test(arguments: ["NiTriShape", "BSLODTriShape"])
    func legacyShapeFlattensLikeABSTriShape(type: String) throws {
        let lod: [UInt32] = type == "BSLODTriShape" ? [1, 0, 0] : []
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init(type, NIFBlockFixture.legacyTriShape(dataRef: 2, lodSizes: lod)),
            .init("NiTriShapeData", NIFBlockFixture.triShapeData(
                positions: Self.positions, uvs: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1)],
                triangles: [0, 1, 2]
            ))
        ]))
        let mesh = try #require(file.model().meshes.first)
        #expect(mesh.positions == Self.positions)
        #expect(mesh.indices.count == 3)
        for block in file.blocks {
            #expect(throws: Never.self) { try NIFBlockDecoders.decode(block, header: file.header) }
        }
    }

    @Test func indexPastTheVerticesThrows() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiTriShapeData", NIFBlockFixture.triShapeData(
                positions: Self.positions, uvs: [.zero, .zero, .zero], triangles: [0, 1, 9]
            ))
        ]))
        let block = file.blocks[0]
        #expect(throws: NIFError.self) { try NIFBlockDecoders.decode(block, header: file.header) }
    }
}
