// `coc` lands on the cell's COCMarkerHeading, else on the newest XMarker or XMarkerHeading.

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

    @Test func withoutACOCMarkerTheNewestXMarkerWins() {
        let references = [
            Self.marker(0x34, id: 0x500, x: 1),
            Self.marker(0x3B, id: 0x700, x: 2),
            Self.marker(0x3B, id: 0x600, x: 3),
            Self.marker(0x99, id: 0x800, x: 4)
        ]
        #expect(CenterOnCellMarker.placement(in: references)?.position.x == 2)
    }

    @Test func aCellWithoutMarkersHasNoSpot() {
        let references = [Self.marker(0x99, id: 0x800, x: 4)]
        #expect(CenterOnCellMarker.placement(in: references) == nil)
    }
}
