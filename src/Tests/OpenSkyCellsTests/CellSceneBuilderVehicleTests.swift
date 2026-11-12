// A cart that a horse tows draws its own posed copy when its mesh has wheel nodes, so
// its wheels can turn. A towed mesh without wheels and an untowed cart stay static.
// Synthetic plugin and NIF only (docs/engine/vehicles.md).

import Foundation
import OpenSkyActorPresentation
@testable import OpenSkyCells
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderVehicleTests: CellSceneBuilderFixture {
    let dataURL: URL

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    /// One triangle and a back wheel node 50 units above the floor.
    private func cartNIF() -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 3])),
            .init("BSTriShape", NIFFixture.bsTriShape(
                shaderPropertyRef: 2,
                attributes: Self.staticAttributes,
                strideDwords: Self.staticStrideDwords,
                vertexRecords: [SIMD3<Float>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 1)]
                    .map(vertexRecord(position:)),
                triangles: [0, 1, 2]
            )),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty()),
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0, translation: [-70, -215, 50])
            ))
        ], strings: ["WheelBackLeft"])
    }

    /// Each listed reference rides the horse 0x900.
    private func towed(_ objectIDs: [UInt32]) -> WorldStateSnapshot {
        let link = ReferenceVehicleLink(carrier: .plugin(name: "skyrim.esm", objectID: 0x900))
        return WorldStateSnapshot(
            entries: objectIDs.map { objectID in
                WorldStateSnapshotEntry(
                    key: .plugin(name: "skyrim.esm", objectID: objectID),
                    delta: ReferenceStateDelta(components: [.vehicleLink: link.erased])
                )
            },
            nextGeneratedSequence: 1, sequence: 1
        )
    }

    private func build(state: WorldStateSnapshot) throws -> CellScene {
        try writeLooseFile("meshes/arch/cart.nif", cartNIF())
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        return try build(
            pluginData: plugin(
                temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                    + refrRecord(formID: 0x201, base: 0x101, position: SIMD3(500, 0, 0)),
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\cart.nif")
                    + statRecord(formID: 0x101, modelPath: "arch\\wall.nif")
            ),
            state: state
        )
    }

    @Test(.enabled(if: Self.hasDevice)) func aTowedCartRigsItsWheels() throws {
        let scene = try build(state: towed([0x200, 0x201]))
        #expect(scene.animatedVehicles.map(\.reference) == [0x200])
        #expect(scene.animatedVehicles.first?.rig.skeleton.boneNames == ["WheelBackLeft"])
    }

    @Test(.enabled(if: Self.hasDevice)) func anUntowedCartStaysStatic() throws {
        #expect(try build(state: .empty).animatedVehicles.isEmpty)
    }
}
