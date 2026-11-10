// The shapes an `NiPSysMeshEmitter` births on. Layout: docs/formats/nif-particles.md.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFMeshEmitterGeometryTests {
    @Test func readsTheShapeBehindAnEmitterMeshRef() throws {
        var record = Data()
        for value: Float in [1, 2, 3, 0] {
            record.appendFloat32(value)
        }
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSTriShape", NIFFixture.bsTriShape(
                attributes: 0x401, // vertex|full precision
                strideDwords: 4,
                vertexRecords: [record]
            ))
        ]))

        let shape = try NIFMeshEmitterGeometry.shape(file.blocks[1], file)
        #expect(shape?.positions == [SIMD3(1, 2, 3)])
        #expect(try NIFMeshEmitterGeometry.shape(file.blocks[0], file) == nil)
    }
}
