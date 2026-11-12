// The save list the system menu's movie shows, and the file jobs a row starts.

import Foundation
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
@testable import OpenSkyRendering
import Testing

@MainActor
struct SystemMenuSaveWorkTests {
    private static let rows = [
        SaveSlotRow(slot: "Old", title: "Old", detail: "", savedAt: Date(timeIntervalSince1970: 1)),
        SaveSlotRow(slot: "New", title: "New", detail: "", savedAt: Date(timeIntervalSince1970: 2))
    ]

    private static func work(_ saves: FakeSaves) -> SystemMenuSaveWork {
        let movies = SWFMovieSource()
        return SystemMenuSaveWork(saves: saves, hud: HUDCoordinator(movies: movies))
    }

    @Test func theMovieListHoldsTheSavesAndThePageFollowsIt() {
        let saves = FakeSaves()
        saves.saveRows = Self.rows
        let work = Self.work(saves)
        var updates = 0
        work.fillSaveList(saving: true) { _ in updates += 1 }
        #expect(updates == 1)
        #expect(work.movieListSaving)
        #expect(Set(work.movieRows.map(\.slot)) == ["Old", "New"])
        work.followPage(saving: false)
        #expect(work.page?.mode == .load)
    }

    @Test func aCharacterListAndAScreenshotEachUpdateTheMovieOnce() {
        let saves = FakeSaves()
        saves.saveRows = Self.rows
        let work = Self.work(saves)
        var updates = 0
        let list = SystemMenuMovieBridge.Call(request: .characters, index: nil, text: nil)
        work.answerCharacters(list) { _ in updates += 1 }
        let picked = SystemMenuMovieBridge.Call(request: .characterSelected, index: 9, text: nil)
        work.answerCharacters(picked) { _ in updates += 1 }
        #expect(work.movieRows.isEmpty)
        work.showScreenshot(index: nil, renderer: nil) { _ in updates += 1 }
        #expect(updates == 3)
    }

    @Test func aRowStartsItsFileJob() {
        let saves = FakeSaves()
        saves.saveRows = Self.rows
        let work = Self.work(saves)
        work.fillSaveList(saving: false) { _ in }
        work.deleteFromMovie(index: 0)
        #expect(work.movieRows.count == 1)
        #expect(work.message == "Deleting")
        work.work?.cancel()
        work.work = nil
        work.loadFromMovie(index: 0) {}
        #expect(work.message == work.texts.loading)
        work.work = nil
        work.saveFromMovie(listIndex: 0)
        #expect(work.message == "Saving")
        work.saveFromMovie(listIndex: nil)
    }

    @Test func aReportBecomesTheMessage() {
        let work = Self.work(FakeSaves())
        work.report("Saved")
        #expect(work.message == "Saved")
    }
}

/// The settings readouts the system menu shows.
@MainActor
struct PlayerSettingsReadoutTests {
    @Test func theVolumeAndControlsRowsReadTheStore() {
        let settings = PlayerSettingsCoordinator(store: PlayerSettingsStore(persistence: nil))
        settings.masterVolume = 0.25
        #expect(settings.masterVolume == 0.25)
        #expect(settings.controlsRows.last == ControlsPageModel.resetTitle)
        let rows = settings.store.movieRows([.masterVolume])
        #expect(rows.first?.value == 0.25)
    }
}
