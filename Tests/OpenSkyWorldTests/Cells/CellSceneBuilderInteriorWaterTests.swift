// Interior cell water and the interior room/portal graph. Synthetic plugin and
// NIF fixtures only.

import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

extension CellSceneBuilderTests {
    private static let interiorID: UInt32 = 0x0001_38CA

    private func waterNIF() -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSTriShape", NIFFixture.bsTriShape(
                shaderPropertyRef: 2,
                attributes: Self.staticAttributes,
                strideDwords: Self.staticStrideDwords,
                vertexRecords: [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0)]
                    .map(vertexRecord(position:)),
                triangles: [0, 1, 2]
            )),
            .init("BSWaterShaderProperty", Data(count: 16))
        ])
    }

    private func waterHeightField(_ height: Float) -> Data {
        var bytes = Data()
        bytes.appendFloat32(height)
        return ESMFixture.field("XCLW", bytes)
    }

    /// Two unit meshes span x 0...101, y 0...201, z 0...101.
    private func interiorScene(
        waterHeight: Float?,
        hasWater: Bool = true,
        extraRefs: Data = Data()
    ) throws -> CellScene {
        try writeLooseFile("meshes/arch/unit.nif", unitNIF())
        try writeLooseFile("meshes/water/plane.nif", waterNIF())
        let refs = refrRecord(formID: 0x300, base: 0x100, position: .zero)
            + refrRecord(formID: 0x301, base: 0x100, position: SIMD3(100, 200, 100))
            + extraRefs
        let bytes = plugin(
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\unit.nif")
                + statRecord(formID: 0x101, modelPath: "water\\plane.nif")
                + statRecord(formID: 0x102, modelPath: nil),
            interiorRecords: interiorCellGroup(
                formID: Self.interiorID, refs: refs,
                cellFlags: hasWater ? Cell.Flags.hasWater.rawValue : 0,
                cellFields: waterHeight.map(waterHeightField) ?? Data()
            )
        )
        let builder = try makeBuilder(pluginData: bytes, device: #require(Self.device))
        return try builder.buildInteriorScene(cellFormID: FormID(Self.interiorID))
    }

    @Test(.enabled(if: Self.hasDevice)) func interiorWaterSpansThePlacedGeometry() throws {
        let scene = try interiorScene(waterHeight: 50)
        #expect(scene.renderScene.water.count == 1)
        #expect(scene.waterHeight == 50)
        #expect(scene.summary.waterPlaneCount == 1)
        let bounds = try #require(scene.renderScene.water.first?.bounds)
        #expect(bounds.min == SIMD3(-64, -64, 50))
        #expect(bounds.max == SIMD3<Float>(101 + 64, 201 + 64, 50))
        let corner = scene.renderScene.water[0].modelMatrix
            * SIMD4(TerrainMeshBuilder.cellSize, TerrainMeshBuilder.cellSize, 0, 1)
        #expect(simd_distance(SIMD3(corner.x, corner.y, corner.z), bounds.max) < 0.01)
    }

    @Test(.enabled(if: Self.hasDevice)) func interiorWaterNeedsAHeightInsideTheGeometry() throws {
        #expect(try interiorScene(waterHeight: 0).renderScene.water.isEmpty)
        #expect(try interiorScene(waterHeight: 500).renderScene.water.isEmpty)
        #expect(try interiorScene(waterHeight: nil).renderScene.water.isEmpty)
        #expect(try interiorScene(waterHeight: 50, hasWater: false).renderScene.water.isEmpty)
        #expect(try interiorScene(waterHeight: .greatestFiniteMagnitude).renderScene.water.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func placedWaterAtTheCellHeightIsNotDrawnTwice() throws {
        let scene = try interiorScene(
            waterHeight: 50,
            extraRefs: refrRecord(formID: 0x302, base: 0x101, position: SIMD3(20, 20, 50))
        )
        #expect(scene.renderScene.water.count == 1)
        #expect(scene.summary.waterPlaneCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func interiorRoomsAndPortalsBecomeTheGraph() throws {
        let box = PrimitiveFixture(halfExtents: SIMD3(150, 150, 150), type: .box)
        var portalRooms = Data()
        portalRooms.appendUInt32(0x400)
        portalRooms.appendUInt32(0x401)
        let rooms = primitiveRefrRecord(
            formID: 0x400, base: 0x102, position: SIMD3(-100, -100, 0), primitive: box,
            extraFields: ESMFixture.field("XRMR", Data([0, 0, 0, 0]))
        ) + primitiveRefrRecord(
            formID: 0x401, base: 0x102, position: SIMD3(-100, 400, 0), primitive: box,
            extraFields: ESMFixture.field("XRMR", Data([0, 0, 0, 0]))
        ) + primitiveRefrRecord(
            formID: 0x402, base: 0x102, position: SIMD3(-100, 150, 0),
            primitive: PrimitiveFixture(halfExtents: SIMD3(50, 1, 50), type: .portalBox),
            extraFields: ESMFixture.field("XPOD", portalRooms)
        )
        let scene = try interiorScene(waterHeight: nil, extraRefs: rooms)
        let graph = try #require(scene.renderScene.rooms)
        #expect(graph.rooms.count == 2)
        #expect(graph.portals.map(\.rooms) == [SIMD2(0, 1)])
        let placedRooms = (scene.renderScene.opaque + scene.renderScene.alphaTested)
            .flatMap(\.instances).map(\.room).sorted()
        // The mesh at the origin sits in the first room; the other is outside both.
        #expect(placedRooms == [0, RoomPortalGraph.noRoom])
        #expect(scene.triggerVolumes.volumes.isEmpty)
    }
}
