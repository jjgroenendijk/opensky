// The preview of a light, an actor, and a mesh that fails, and where the preview puts
// the camera: the cell that holds a reference, the floor of an interior, and the eye of
// a player who arrives through a door. Synthetic plugin only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTagsTesting
import OpenSkyTerrain
import OpenSkyWorldTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderPreviewPlacesTests: CellSceneBuilderFixture {
    let dataURL: URL
    private let spot = PlacedReference.Placement(position: SIMD3(10, 20, 30), rotation: .zero)
    private let room: UInt32 = 0x5000
    private let emptyRoom: UInt32 = 0x5001

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    /// A lamp with the wall as its model: radius 256, no flags, 48 bytes of DATA.
    private func lightRecord(formID: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: -1))
        data.appendUInt32(256)
        data.append(contentsOf: [255, 200, 100, 0])
        data.appendUInt32(0)
        data.appendFloat32(1)
        data.append(Data(count: 8))
        data.append(Data(count: 12))
        data.appendUInt32(0)
        data.appendFloat32(0)
        var fnam = Data()
        fnam.appendFloat32(1)
        return ESMFixture.record("LIGH", formID: formID, data: ESMFixture.field(
            "MODL", ESMFixture.zstring("arch\\wall.nif")
        ) + ESMFixture.field("DATA", data) + ESMFixture.field("FNAM", fnam))
    }

    private func makeBuilder() throws -> CellSceneBuilder {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        let door = refrRecord(
            formID: 0x201, base: 0x100, position: SIMD3(-5, -5, 0),
            teleport: TeleportFixture(
                door: 0x300, position: SIMD3(1, 2, 3), rotation: SIMD3(0, 0, 0.5)
            )
        )
        var records = actorChainRecords(npc: 0x800)
        records["LIGH"] = lightRecord(formID: 0x700)
        let device = try #require(Self.device)
        return try makeBuilder(
            pluginData: plugin(
                temporaryRefs: refrRecord(formID: 0x200, base: 0x100, position: SIMD3(5, 5, 0))
                    + door,
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
                    + statRecord(formID: 0x102, modelPath: "arch\\missing.nif"),
                modelBaseRecords: records,
                interiorRecords: interiorCellGroup(
                    formID: room,
                    refs: refrRecord(formID: 0x300, base: 0x100, position: SIMD3(0, 0, 100))
                ) + interiorCellGroup(formID: emptyRoom, refs: Data())
            ),
            device: device
        )
    }

    @Test func anActorIsFramedAsAStandingBox() {
        let tall = ModelBounds(min: SIMD3(-10, -10, 0), max: SIMD3(10, 10, 500))
        let box = CellSceneBuilder.CellPreviewBuilder.standingBox(tall, feet: .zero)
        #expect(box.min == SIMD3(-45, -45, 0))
        #expect(box.max == SIMD3(45, 45, 160))
        let short = ModelBounds(min: .zero, max: SIMD3(1, 1, 20))
        #expect(CellSceneBuilder.CellPreviewBuilder.standingBox(short, feet: .zero).max.z == 64)
    }

    @Test func aFramingBoxReplacesThePlacementsBounds() {
        var subject = PreviewSubject()
        #expect(subject.bounds == nil)
        let framing = ModelBounds(min: .zero, max: SIMD3(1, 2, 3))
        subject.framing = framing
        #expect(subject.bounds == framing)
    }

    @Test(.enabled(if: Self.hasDevice)) func aLightDrawsItsModelAndItsLight() throws {
        let preview = try makeBuilder().previewBuilder
        let subject = try #require(preview.previewObject(base: FormID(0x700), placement: spot))
        #expect(subject.placements.count == 1)
        #expect(subject.pointLights.count == 1)
        #expect(subject.pointLights.first?.position == spot.position)
        #expect(subject.pointLights.first?.radius == 256)
    }

    @Test(.enabled(if: Self.hasDevice)) func aMissingMeshIsAFailure() throws {
        let preview = try makeBuilder().previewBuilder
        let subject = try #require(preview.previewObject(base: FormID(0x102), placement: spot))
        #expect(subject.placements.isEmpty)
        #expect(subject.modelPath == "arch\\missing.nif")
        #expect(subject.failures.contains { $0.hasPrefix("mesh arch\\missing.nif") })
    }

    @Test(.enabled(if: Self.hasDevice)) func anActorStandsOnItsFeet() throws {
        let preview = try makeBuilder().previewBuilder
        let subject = preview.previewActor(base: FormID(0x800), placement: spot)
        #expect(subject.placements.count == 1)
        let framing = try #require(subject.framing)
        #expect(framing.min.z == spot.position.z)
        #expect(framing.max.z >= spot.position.z + 64)
    }

    @Test(.enabled(if: Self.hasDevice)) func theCellOfAReferenceIsFoundInsideOrOutside() throws {
        let preview = try makeBuilder().previewPlaces
        #expect(preview.previewCell(holding: FormID(0x200)) == .exterior(
            cell: FormID(0x2B), worldspace: "Tamriel", grid: CellCoordinate(x: 0, y: 0)
        ))
        #expect(preview.previewCell(holding: FormID(0x300)) == .interior(
            cell: FormID(room), entryDoor: nil
        ))
        #expect(preview.previewCell(holding: FormID(0x999)) == nil)
    }

    @Test(.enabled(if: Self.hasDevice)) func aDoorGivesTheEyeOfAnArrivingPlayer() throws {
        let preview = try makeBuilder().previewPlaces
        let eye = try #require(preview.previewEntryEye(door: FormID(0x201)))
        #expect(eye.position.x == 1)
        #expect(eye.position.y == 2)
        #expect(eye.position.z > 3)
        #expect(eye.rotation == SIMD3(0, 0, 0.5))
        #expect(preview.previewEntryEye(door: FormID(0x200)) == nil)
    }

    @Test(.enabled(if: Self.hasDevice)) func anInteriorSpotStandsInTheMiddleOfTheRoom() throws {
        let builder = try makeBuilder()
        let scene = try builder.interiorBuilder.buildInteriorScene(cellFormID: FormID(room))
        let bounds = try #require(scene.bounds)
        let placement = builder.previewPlaces.previewSpot(in: scene)
        let middle = (bounds.min + bounds.max) * 0.5
        #expect(placement.position.x == middle.x)
        #expect(placement.position.y == middle.y)
        #expect(placement.position.z == bounds.min.z)

        let empty = try builder.interiorBuilder.buildInteriorScene(cellFormID: FormID(emptyRoom))
        #expect(builder.previewPlaces.previewSpot(in: empty).position == .zero)
    }
}
