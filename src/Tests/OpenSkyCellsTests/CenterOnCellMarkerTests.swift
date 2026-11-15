// `coc` takes a COCMarkerHeading, an XMarkerHeading, an XMarker, a door's arrival, a
// static, then any reference (docs/engine/center-on-cell.md).

import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import Testing

struct CenterOnCellMarkerTests {
    private static func marker(_ base: UInt32, id: UInt32, x: Float) -> PlacedReference {
        PlacedReference(
            spawnedBase: FormID(base),
            placement: .init(position: SIMD3(x, 0, 0), rotation: SIMD3(0, 0, x / 100)),
            scale: 1,
            count: 1,
            formID: FormID(id)
        )
    }

    /// Base 0x500 is a static, and the door 0x700 leads in at x = 70.
    private static let records = CenterOnCellMarker.Records(
        isStatic: { $0 == FormID(0x500) },
        arrival: { door in
            door.formID == FormID(0x700)
                ? .init(position: SIMD3(70, 0, 0), rotation: SIMD3(0, 0, 1)) : nil
        }
    )

    @Test func theCOCMarkerHeadingWinsOverNewerXMarkers() {
        let references = [
            Self.marker(0x3B, id: 0x900, x: 1),
            Self.marker(0x32, id: 0x100, x: 2),
            Self.marker(0x34, id: 0x901, x: 3)
        ]
        let spot = CenterOnCellMarker.placement(in: references)
        #expect(spot?.position.x == 2)
        #expect(spot?.rotation.z == 0.02)
    }

    @Test func anXMarkerHeadingWinsOverANewerXMarker() {
        let references = [
            Self.marker(0x34, id: 0x500, x: 1),
            Self.marker(0x34, id: 0x400, x: 5),
            Self.marker(0x3B, id: 0x700, x: 2),
            Self.marker(0x99, id: 0x800, x: 4)
        ]
        let spot = CenterOnCellMarker.placement(in: references)
        #expect(spot?.position.x == 1)
        #expect(spot?.rotation.z == 0.01)
    }

    @Test func anXMarkerGivesItsPositionFacingNorth() {
        let references = [
            Self.marker(0x3B, id: 0x700, x: 2),
            Self.marker(0x3B, id: 0x600, x: 3)
        ]
        let spot = CenterOnCellMarker.placement(in: references, records: Self.records)
        #expect(spot?.position.x == 2)
        #expect(spot?.rotation == .zero)
    }

    @Test func withoutMarkersADoorsArrivalWins() {
        let references = [
            Self.marker(0x500, id: 0x900, x: 9),
            Self.marker(0x77, id: 0x700, x: 7)
        ]
        let spot = CenterOnCellMarker.placement(in: references, records: Self.records)
        #expect(spot?.position.x == 70)
        #expect(spot?.rotation == .zero)
    }

    @Test func withoutDoorsTheNewestStaticWins() {
        let references = [
            Self.marker(0x500, id: 0x300, x: 3),
            Self.marker(0x500, id: 0x400, x: 4),
            Self.marker(0x99, id: 0x900, x: 9)
        ]
        let spot = CenterOnCellMarker.placement(in: references, records: Self.records)
        #expect(spot?.position.x == 4)
        #expect(spot?.rotation == .zero)
    }

    @Test func withoutStaticsAnyReferenceCounts() {
        let references = [
            Self.marker(0x99, id: 0x800, x: 8),
            Self.marker(0x98, id: 0x900, x: 9)
        ]
        #expect(CenterOnCellMarker.placement(in: references)?.position.x == 9)
    }

    @Test func anEmptyCellHasNoSpot() {
        #expect(CenterOnCellMarker.placement(in: []) == nil)
    }
}
