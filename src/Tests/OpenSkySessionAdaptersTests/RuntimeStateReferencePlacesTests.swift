import Foundation

// The places of resident references, which every condition build reads, are built once
// per set of resident cells and player cell.

import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkySessionAdapters
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

    @Test func theEditorLocationIsTheResidentCellsLocationWithoutThePlayer() {
        let guardKey = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
        let town = ResolvedFormID(plugin: "Base.esm", objectID: 0x10)
        var places = ReferencePlaces()
        places.locations = [guardKey: town, .player: town]
        let locations = RuntimeStateCoreAdapter.editorLocations(places: places, store: nil)
        #expect(locations == [guardKey: town])
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
