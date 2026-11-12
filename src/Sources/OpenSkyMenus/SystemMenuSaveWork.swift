// The system menu's save, load, and delete work, and the save list its movie shows.
// One file job runs at a time; its message is what the readout shows.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyRendering
import simd

/// Runs a change to the movie, when the movie is up.
typealias SystemMenuMovieUpdate = ((SWFMovieRuntime) -> Void) -> Void

/// The save work of `SystemMenuCoordinator`. It holds the save service and the HUD,
/// not the menu; a finished load closes the menu through the closure it is given.
final class SystemMenuSaveWork {
    weak let saves: (any SaveGameService)?
    let hud: HUDCoordinator
    /// The Save or Load page while one is up.
    var page: SaveLoadPageModel?
    /// The result of the last save, load, or remap, for the readout.
    var message: String?
    /// The running save, load, or delete; one at a time.
    var work: Task<Void, Never>?
    /// The movie's save list in its own order, without the New Save row.
    var movieRows: [SaveSlotRow] = []
    var movieListSaving = false

    init(saves: (any SaveGameService)?, hud: HUDCoordinator) {
        self.saves = saves
        self.hud = hud
    }

    var texts: SaveTexts {
        saves?.saveTexts ?? .vanilla
    }

    /// Opens the Save or Load page on the rows the service knows now.
    func openPage(saving: Bool) {
        page = SaveLoadPageModel(
            mode: saving ? .save : .load, rows: saves?.saveRows ?? [], texts: texts
        )
        refreshRows()
    }

    /// Follows the movie onto its Save or Load page, with the rows it shows.
    func followPage(saving: Bool) {
        page = SaveLoadPageModel(mode: saving ? .save : .load, rows: movieRows, texts: texts)
    }

    func quicksave() {
        save(slot: AutosavePolicy.quicksaveSlot, running: texts.quickSaving)
    }

    /// Writes `slot`, or a new slot for nil, unless `SetInChargen` turned saving off.
    func save(slot: String?, running: String = "Saving") {
        guard saves?.isSavingDisabled != true else {
            report(texts.cannotSaveNow)
            return
        }
        let done = slot == AutosavePolicy.quicksaveSlot ? texts.quickSaved : texts.saved
        perform(running, then: (done, nil)) { _ = try await $0.saveGame(slot: slot) }
    }

    /// Loads `slot`. A changed load order asks `sSaveGameContentIsMissing` first.
    func load(
        slot: String, acceptingChangedContent: Bool = false, close: @escaping () -> Void
    ) {
        perform(texts.loading, then: ("Loaded", close), slot: slot) {
            try await $0.loadGame(slot: slot, acceptingChangedContent: acceptingChangedContent)
        }
    }

    func report(_ message: String) {
        self.message = message
        hud.showNotification(message)
    }

    /// Routes a key on the Save or Load page. True when the page went back.
    func route(_ event: MenuInputEvent, close: @escaping () -> Void) -> Bool {
        guard var page else { return false }
        let action = page.handle(event)
        self.page = page
        switch action {
        case let .save(slot):
            save(slot: slot)
        case let .load(slot):
            load(slot: slot, close: close)
        case let .loadChangedContent(slot):
            load(slot: slot, acceptingChangedContent: true, close: close)
        case let .delete(slot):
            perform("Deleting", then: (texts.deleted, nil)) { try await $0.deleteSave(slot: slot) }
        case .exportSkyrim:
            perform("Exporting", then: ("Exported", nil)) { _ = try await $0.exportSkyrimSave() }
        case .back:
            self.page = nil
            return true
        case nil:
            break
        }
        return false
    }

    func refreshRows() {
        guard let saves else { return }
        Task {
            let rows = await saves.refreshSaveRows()
            self.page?.replaceRows(rows)
        }
    }

    /// Shows `running` until the file work ends, then `finish.done`. A finish with a
    /// close closes the menu, as a finished load does.
    func perform(
        _ running: String, then finish: (done: String, close: (() -> Void)?),
        slot: String? = nil,
        _ body: @escaping @MainActor (any SaveGameService) async throws -> Void
    ) {
        guard let saves else {
            message = "Saving unavailable"
            return
        }
        guard work == nil else { return }
        message = running
        work = Task {
            do {
                try await body(saves)
                self.message = finish.done
                finish.close?()
            } catch let failure as SaveFailure {
                self.report(self.texts.text(for: failure))
                if failure == .contentMissing, let slot {
                    self.page?.askToLoadChangedContent(slot: slot)
                }
            } catch {
                self.message = "\(self.texts.saveFailed) \(error)"
            }
            self.work = nil
            self.refreshRows()
        }
    }

    // MARK: - The movie's list

    func fillSaveList(saving: Bool, update: SystemMenuMovieUpdate) {
        let rows = saves?.saveRows ?? []
        movieListSaving = saving
        movieRows = SaveLoadPageModel.sorted(saving ? rows.filter { !$0.isImport } : rows)
        let request: SystemMenuMovieBridge.Request = saving ? .saveList : .loadList
        let shown = movieRows
        update { SystemMenuMovieBridge.fillSaveList(shown, request: request, runtime: $0) }
    }

    func answerCharacters(_ call: SystemMenuMovieBridge.Call, update: SystemMenuMovieUpdate) {
        let rows = saves?.saveRows ?? []
        let names = TitleMenuLoadBridge.characters(rows)
        let path = SystemMenuMovieBridge.saveLoadListPath
        guard call.request == .characterSelected else {
            update { TitleMenuLoadBridge.fillCharacters(names, runtime: $0, listPath: path) }
            return
        }
        let name = call.index.flatMap { names.indices.contains($0) ? names[$0] : nil }
        movieListSaving = false
        movieRows = name.map { TitleMenuLoadBridge.saves(of: $0, in: rows) } ?? []
        let shown = movieRows
        update { TitleMenuLoadBridge.fillSaves(shown, runtime: $0, listPath: path) }
    }

    /// A row of the list as the movie numbers it, without its New Save row.
    private func movieRow(_ index: Int?) -> SaveSlotRow? {
        index.flatMap { movieRows.indices.contains($0) ? movieRows[$0] : nil }
    }

    func showScreenshot(
        index: Int?, renderer: (any RendererPort)?, update: SystemMenuMovieUpdate
    ) {
        let row = movieRow(index)
        renderer?.replaceSWFImage(
            TitleMenuLoadBridge.screenshotSlot,
            rgba: TitleMenuLoadBridge.screenshotPixels(row?.picture),
            width: TitleMenuLoadBridge.screenshotWidth,
            height: TitleMenuLoadBridge.screenshotHeight
        )
        update { $0.callMovie("ScreenshotReady") }
    }

    /// `SaveGame` passes the list row, and row 0 is New Save.
    func saveFromMovie(listIndex: Int?) {
        guard let listIndex else { return }
        let slot = listIndex == 0 ? nil : movieRow(listIndex - 1)?.slot
        guard listIndex == 0 || slot != nil else { return }
        save(slot: slot)
    }

    func loadFromMovie(index: Int?, close: @escaping () -> Void) {
        guard let row = movieRow(index), row.error == nil else { return }
        load(slot: row.slot, close: close)
    }

    /// The movie already took the row out of its list.
    func deleteFromMovie(index: Int?) {
        guard let row = movieRow(index), !row.isImport else { return }
        movieRows.removeAll { $0.slot == row.slot }
        perform("Deleting", then: (texts.deleted, nil)) {
            try await $0.deleteSave(slot: row.slot)
        }
    }
}
