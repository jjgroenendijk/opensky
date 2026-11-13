// Saving, loading, autosaves, and the save contents read the clock and the records through
// their ports.

import Foundation
import OpenSkyConditions
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkySaveInterface
import OpenSkySessionAdapters
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct SaveSessionFlowTests {
    private let host = SessionHost()
    private static let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func saves() -> SaveGameWorldAdapter {
        host.fakeMenuWorld.playerNameAndRace = (name: "Lydia", race: "Nord")
        host.fakePlayerSettings.store = PlayerSettingsStore(persistence: nil)
        return SaveGameWorldAdapter(game: host, now: { Self.start })
    }

    @Test func aSaveNamesItsSlotAndStampsTheClock() async throws {
        let saves = saves()
        let name = try await saves.saveGame(slot: nil)
        #expect(name == "Save 1")
        #expect(saves.lastSaveDate == Self.start)
        #expect(host.fakeRuntimeStateWorld.saveSessionCalls.map(\.slot) == ["Save 1"])
    }

    @Test func aLoadReadsTheSlotAndRestartsThePlayClock() async throws {
        let saves = saves()
        try await saves.loadGame(slot: "Save 1")
        #expect(saves.lastSaveDate == Self.start)
        #expect(host.fakeRuntimeStateWorld.loadSessionSlotChecksLoadOrderCalls.map(\.slot)
            == ["Save 1"])
    }

    @Test func aPauseAutosaveReadsTheClock() {
        let saves = saves()
        saves.autosave(.pause)
        #expect(host.fakeRuntimeStateWorld.saveSessionCalls.isEmpty)
    }

    @Test func conditionDataAndSaveContentsReadThePorts() {
        let world = RuntimeStateWorldAdapter(game: host, now: { Self.start })
        host.fakeStreamer.residents.residentReferencePlacesResult = ReferencePlaces()
        let data = world.core.conditionData()
        #expect(data.formLists == nil)
        host.fakeWorldState.snapshotResult = .empty
        let contents = world.saveContents.sessionContents(summary: nil, thumbnail: nil)
        #expect(contents.metadata.creationTimestamp == UInt64(Self.start.timeIntervalSince1970))
    }
}
