import Foundation

// The places of resident references, which every condition build reads, are built once
// per set of resident cells and player cell.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkySessionAdapters
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct RuntimeStateReferencePlacesTests {
    private let host = SessionHost()

    private func world() -> RuntimeStateWorldAdapter {
        host.fakeStreamer.residents.residentReferencePlacesResult = ReferencePlaces()
        return RuntimeStateWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
    }

    @Test func buildsWithTheSameCellsReuseThePlaces() {
        let world = world()
        _ = world.conditionData()
        _ = world.conditionData()
        #expect(host.fakeStreamer.residents.residentReferencePlacesCallCount == 1)
    }

    @Test func aNewPlayerCellOrReferenceCountBuildsThePlacesAgain() {
        let world = world()
        _ = world.conditionData()
        host.fakeStreamer.currentCellLocation = .interior(FormID(0x60))
        _ = world.conditionData()
        host.fakeStreamer.residentReferenceCount = 3
        _ = world.conditionData()
        #expect(host.fakeStreamer.residents.residentReferencePlacesCallCount == 3)
    }
}
