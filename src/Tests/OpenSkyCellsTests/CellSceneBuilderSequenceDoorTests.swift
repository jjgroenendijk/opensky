// A door whose mesh holds `Open` and `Close` sequences gets its own posed copy and a
// playback in the cell build. A load door and a container lid keep their kind.
// Synthetic plugin and NIF only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import OpenSkyObjectAnimation
import OpenSkyTagsTesting
import OpenSkyWorldTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderSequenceDoorTests: CellSceneBuilderFixture {
    let dataURL: URL

    /// A load door belongs to the cell its position falls in: here the built cell (6, -2).
    private let insideTheCell = SIMD3<Float>(6 * 4096 + 100, -2 * 4096 + 100, 0)

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    /// One triangle under the leaf, so the build keeps the door.
    private func leafShape(shaderRef: Int32) -> Data {
        NIFFixture.bsTriShape(
            shaderPropertyRef: shaderRef,
            attributes: Self.staticAttributes,
            strideDwords: Self.staticStrideDwords,
            vertexRecords: [SIMD3<Float>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 1)]
                .map(vertexRecord(position:)),
            triangles: [0, 1, 2]
        )
    }

    private func build(refs: Data) throws -> CellScene {
        try writeLooseFile("meshes/arch/gate.nif", SequenceDoorFixture.file(leafShape: leafShape))
        try writeLooseFile(
            "meshes/arch/plain.nif",
            SequenceDoorFixture.file(withClose: false, leafShape: leafShape)
        )
        return try build(pluginData: plugin(
            temporaryRefs: refs,
            modelBaseRecords: [
                "CONT": modelBaseRecord(type: "CONT", formID: 0x110, modelPath: "arch\\gate.nif"),
                "DOOR": modelBaseRecord(type: "DOOR", formID: 0x100, modelPath: "arch\\gate.nif")
                    + modelBaseRecord(type: "DOOR", formID: 0x101, modelPath: "arch\\plain.nif")
            ]
        ))
    }

    @Test(.enabled(if: Self.hasDevice)) func eachSequenceMeshBecomesAnAnimatedDoor() throws {
        let scene = try build(refs: refrRecord(formID: 0x200, base: 0x100)
            + refrRecord(
                formID: 0x201, base: 0x100, position: insideTheCell,
                teleport: TeleportFixture(door: 0x999, position: .zero, rotation: .zero)
            )
            + refrRecord(formID: 0x202, base: 0x110, position: SIMD3(200, 0, 0))
            + refrRecord(formID: 0x203, base: 0x101, position: SIMD3(300, 0, 0)))
        let kinds = Dictionary(uniqueKeysWithValues: scene.sequenceDoors.map {
            ($0.reference, $0.kind)
        })
        #expect(kinds == [0x200: .door, 0x201: .loadDoor, 0x202: .containerLid])
    }
}
