// Random doors: a free door in a destination links both ways, a saved link is
// followed, and a door with no free target fails. Synthetic plugin only.

import Foundation
import Metal
@testable import OpenSkyCells
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

extension CellSceneBuilderTests {
    private static let cellar: UInt32 = 0x0001_38CA
    private static let cave: UInt32 = 0x0001_38CB
    private static let otherCave: UInt32 = 0x0001_38CC

    private func randomDoorBase(formID: UInt32, destinations: [UInt32]) -> Data {
        var tnam = Data()
        for destination in destinations {
            var data = Data()
            data.appendUInt32(destination)
            tnam += ESMFixture.field("TNAM", data)
        }
        return modelBaseRecord(
            type: "DOOR", formID: formID, modelPath: "arch\\door.nif", extraFields: tnam
        )
    }

    /// A cellar door to the caves, and a cave door back. `caveListsCellar` false
    /// makes the cave door list another cell, so the cellar door finds nothing.
    private func randomDoorBuilder(caveListsCellar: Bool = true) throws -> CellSceneBuilder {
        try writeLooseFile("meshes/arch/door.nif", unitNIF())
        let bytes = plugin(
            modelBaseRecords: [
                "DOOR": randomDoorBase(formID: 0x101, destinations: [Self.cave])
                    + randomDoorBase(
                        formID: 0x102,
                        destinations: [caveListsCellar ? Self.cellar : Self.otherCave]
                    )
            ],
            interiorRecords: interiorCellGroup(
                formID: Self.cellar,
                refs: refrRecord(formID: 0x300, base: 0x101, position: SIMD3(10, 0, 0))
            ) + interiorCellGroup(
                formID: Self.cave,
                refs: refrRecord(
                    formID: 0x400, base: 0x102, position: SIMD3(500, 0, 0),
                    rotation: SIMD3(0, 0, .pi / 2)
                )
            )
        )
        return try makeBuilder(pluginData: bytes, device: #require(Self.device))
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    @Test(.enabled(if: Self.hasDevice)) func aRandomDoorLinksToAFreeDoorBothWays() throws {
        let builder = try randomDoorBuilder()
        let cellar = try builder.interiorBuilder.buildInteriorScene(cellFormID: FormID(Self.cellar))
        #expect(cellar.doors.map(\.reference) == [FormID(0x300)])
        #expect(cellar.doors.first?.destination == nil)

        let transition = try builder.doorTransitions.buildDoorTransition(
            from: FormID(0x300), worldspaceEditorID: "Tamriel"
        )
        #expect(transition.destinationDoor == FormID(0x400))
        #expect(transition.scene.location == .interior(FormID(Self.cave)))
        // The cave door faces +X at heading pi/2, so the player lands 150 units east.
        #expect(simd_distance(transition.destinationPlacement.position, SIMD3(650, 0, 0)) < 0.01)
        #expect(transition.newDoorLinks.map(\.key) == [Self.key(0x300), Self.key(0x400)])
        #expect(transition.newDoorLinks.map(\.link.door) == [Self.key(0x400), Self.key(0x300)])
    }

    @Test(.enabled(if: Self.hasDevice)) func aLinkedRandomDoorFollowsItsLink() throws {
        let builder = try randomDoorBuilder()
        let state = WorldStateSnapshot(
            entries: [
                WorldStateSnapshotEntry(
                    key: Self.key(0x400),
                    delta: ReferenceStateDelta(
                        components: [.doorLink: ReferenceDoorLink(door: Self.key(0x300)).erased]
                    )
                )
            ],
            nextGeneratedSequence: 1, sequence: 1
        )
        let transition = try builder.doorTransitions.buildDoorTransition(
            from: FormID(0x400), worldspaceEditorID: "Tamriel", state: state
        )
        #expect(transition.destinationDoor == FormID(0x300))
        #expect(transition.newDoorLinks.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func aRandomDoorWithNoFreeTargetLeadsNowhere() throws {
        let builder = try randomDoorBuilder(caveListsCellar: false)
        #expect {
            try builder.doorTransitions.buildDoorTransition(
                from: FormID(0x300), worldspaceEditorID: "Tamriel"
            )
        } throws: { error in
            if case .randomDoorLeadsNowhere? = error as? CellSceneError {
                return true
            }
            return false
        }
    }
}
