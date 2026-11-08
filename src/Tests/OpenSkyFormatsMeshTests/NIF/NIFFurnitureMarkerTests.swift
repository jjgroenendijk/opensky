// `BSFurnitureMarkerNode` over synthetic files: where an actor sits on furniture.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFFurnitureMarkerTests {
    private func markerBlock(
        count: UInt32,
        markers: [NIFFurnitureMarker]
    ) -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendUInt32(count)
        for marker in markers {
            data.appendFloat32(marker.offset.x)
            data.appendFloat32(marker.offset.y)
            data.appendFloat32(marker.offset.z)
            data.appendFloat32(marker.heading)
            data.appendUInt16(marker.animationType)
            data.appendUInt16(marker.entryPoints)
        }
        return data
    }

    @Test func readsEachMarker() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("BSFadeNode", Data(count: 4)),
                .init("BSFurnitureMarkerNode", markerBlock(count: 2, markers: [
                    NIFFurnitureMarker(
                        offset: .zero,
                        heading: 0,
                        animationType: 1,
                        entryPoints: 0x2
                    ),
                    NIFFurnitureMarker(
                        offset: SIMD3(68.5, 87.5, 0), heading: 4.5, animationType: 1,
                        entryPoints: 0x4
                    )
                ]))
            ],
            strings: ["FRN"]
        ))
        let markers = NIFFurnitureMarker.markers(in: file)
        #expect(markers.count == 2)
        #expect(markers[1].offset == SIMD3(68.5, 87.5, 0))
        #expect(markers[1].heading == 4.5)
        #expect(markers[1].animationType == 1)
        #expect(markers[1].entryPoints == 0x4)
    }

    @Test func aCountPastTheBlockGivesNoMarkers() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [.init("BSFurnitureMarkerNode", markerBlock(count: 3, markers: []))],
            strings: ["FRN"]
        ))
        #expect(NIFFurnitureMarker.markers(in: file).isEmpty)
    }
}
