// With the movie up, the System page runs its own Save, Load, Controls, and Quit pages,
// as in the game. This answers the calls it makes and keeps the engine page in step
// with the movie's state, so the readout and the key capture follow it.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

extension SystemMenuCoordinator {
    /// `SystemPage` state numbers, measured from the movie's class constants.
    static let moviePages: [Int: SystemMenuPage] = [
        0: .main, 3: .settings, 4: .settings, 5: .settings, 6: .controls,
        7: .quit, 8: .quit, 9: .quit
    ]
    static let movieSaveLoadStates: Set = [1, 2, 10, 16, 17]

    /// Settings stays with the engine model, which the movie mirrors. Cancel on the
    /// main page is Resume.
    func sendsToMovie(_ event: MenuInputEvent) -> Bool {
        guard movieLoaded else { return false }
        switch model.page {
        case .settings:
            return false
        case .main:
            if case .move = event {
                return true
            }
            guard event == .button(.accept) else { return false }
            let entry = renderer?.swfRuntime.flatMap(SystemMenuMovieBridge.selectedEntry)
            return entry != .settings
        case .save, .load, .controls, .quit:
            return true
        }
    }

    func sendToMovie(_ event: MenuInputEvent) {
        guard let renderer else { return }
        do {
            try SystemMenuMovieBridge.send(event, renderer: renderer)
        } catch {
            movieError = String(describing: error)
        }
        answerMovieCalls()
        followMovieState()
    }

    /// Steps the movie, so its fades and timers run, then answers its calls.
    public func tick(now: Double) {
        guard movieLoaded, let renderer else {
            framePacer = MenuMovieFramePacer()
            return
        }
        let rate = Double(renderer.swfRuntime?.movie.frameRate ?? 0)
        do {
            for _ in 0 ..< framePacer.ticks(at: now, frameRate: rate) where movieLoaded {
                try renderer.advanceSWFRuntime()
            }
        } catch {
            movieError = String(describing: error)
        }
        answerMovieCalls()
        followMovieState()
    }

    /// File actions run even when the movie closed itself in the same frame, as
    /// it does after Save.
    func answerMovieCalls() {
        let calls = pendingMovieCalls
        pendingMovieCalls = []
        for call in calls {
            answer(call)
        }
    }

    private func answer(_ call: SystemMenuMovieBridge.Call) {
        switch call.request {
        case .quicksave: quicksave()
        case .saveList, .loadList: fillSaveList(saving: call.request == .saveList)
        case .characters, .characterSelected: answerCharacters(call)
        case .screenshot: showScreenshot(row: movieRow(call.index))
        case .confirmLoad: updateMovie { $0.callMovie("ConfirmOKToLoad") }
        case .saveGame: saveFromMovie(listIndex: call.index)
        case .loadGame: loadFromMovie(row: movieRow(call.index))
        case .deleteSave: deleteFromMovie(index: call.index)
        case .inputMappings, .resetControls: answerMappings(call.request)
        case .startRemap: beginMovieRemap(call.text)
        case .quitToMainMenu:
            close()
            world?.quitToMainMenu()
        case .quitToDesktop:
            close()
            world?.quitApplication()
        }
    }

    // MARK: - Save and Load

    private func fillSaveList(saving: Bool) {
        let rows = saves?.saveRows ?? []
        movieListSaving = saving
        movieSaveRows = SaveLoadPageModel.sorted(saving ? rows.filter { !$0.isImport } : rows)
        let request: SystemMenuMovieBridge.Request = saving ? .saveList : .loadList
        let shown = movieSaveRows
        updateMovie { SystemMenuMovieBridge.fillSaveList(shown, request: request, runtime: $0) }
    }

    private func answerCharacters(_ call: SystemMenuMovieBridge.Call) {
        let rows = saves?.saveRows ?? []
        let names = TitleMenuLoadBridge.characters(rows)
        let path = SystemMenuMovieBridge.saveLoadListPath
        guard call.request == .characterSelected else {
            updateMovie { TitleMenuLoadBridge.fillCharacters(names, runtime: $0, listPath: path) }
            return
        }
        let name = call.index.flatMap { names.indices.contains($0) ? names[$0] : nil }
        movieListSaving = false
        movieSaveRows = name.map { TitleMenuLoadBridge.saves(of: $0, in: rows) } ?? []
        let shown = movieSaveRows
        updateMovie { TitleMenuLoadBridge.fillSaves(shown, runtime: $0, listPath: path) }
    }

    /// A row of the list as the movie numbers it, without its New Save row.
    private func movieRow(_ index: Int?) -> SaveSlotRow? {
        index.flatMap { movieSaveRows.indices.contains($0) ? movieSaveRows[$0] : nil }
    }

    private func showScreenshot(row: SaveSlotRow?) {
        renderer?.replaceSWFImage(
            TitleMenuLoadBridge.screenshotSlot,
            rgba: TitleMenuLoadBridge.screenshotPixels(row?.picture),
            width: TitleMenuLoadBridge.screenshotWidth,
            height: TitleMenuLoadBridge.screenshotHeight
        )
        updateMovie { $0.callMovie("ScreenshotReady") }
    }

    /// `SaveGame` passes the list row, and row 0 is New Save.
    private func saveFromMovie(listIndex: Int?) {
        guard let listIndex else { return }
        let slot = listIndex == 0 ? nil : movieRow(listIndex - 1)?.slot
        guard listIndex == 0 || slot != nil else { return }
        perform("Saving", done: saveTexts.saved) { _ = try await $0.saveGame(slot: slot) }
    }

    private func loadFromMovie(row: SaveSlotRow?) {
        guard let row, row.error == nil else { return }
        perform(saveTexts.loading, done: "Loaded", closes: true) {
            try await $0.loadGame(slot: row.slot)
        }
    }

    /// The movie already took the row out of its list.
    private func deleteFromMovie(index: Int?) {
        guard let row = movieRow(index), !row.isImport else { return }
        movieSaveRows.removeAll { $0.slot == row.slot }
        perform("Deleting", done: saveTexts.deleted) {
            try await $0.deleteSave(slot: row.slot)
        }
    }

    // MARK: - Controls

    private var mappingRows: [[String: AS2Value]] {
        guard let settings else { return [] }
        return SystemMenuMovieBridge.mappingRows(settings.bindings, keyName: settings.keyName)
    }

    private func answerMappings(_ request: SystemMenuMovieBridge.Request) {
        if request == .resetControls {
            settings?.resetBindings()
            lastMessage = "Controls reset"
        }
        refreshMovieMappings(request)
    }

    /// The movie sorts and redraws the list itself after a remap; after a plain
    /// request it has already drawn the empty list, so it is redrawn here.
    func refreshMovieMappings(_ request: SystemMenuMovieBridge.Request) {
        let rows = mappingRows
        updateMovie { runtime in
            SystemMenuMovieBridge.fillMappings(rows, request: request, runtime: runtime)
            if request != .startRemap {
                runtime.callMovie("InvalidateData", atPath: SystemMenuMovieBridge.mappingListPath)
            }
        }
    }

    private func beginMovieRemap(_ event: String?) {
        guard let event else { return }
        model.show(.controls)
        controlsPage.beginRemap(event: event)
    }

    /// Ends the movie's wait after the engine took the key.
    func finishMovieRemap(succeeded: Bool) {
        guard movieLoaded else { return }
        refreshMovieMappings(.startRemap)
        updateMovie { SystemMenuMovieBridge.finishRemap(succeeded: succeeded, runtime: $0) }
    }

    // MARK: - Page

    /// The engine page follows the page the movie shows.
    func followMovieState() {
        guard
            movieLoaded, model.isOpen,
            let runtime = renderer?.swfRuntime,
            let state = SystemMenuMovieBridge.pageState(runtime: runtime)
        else { return }
        let page: SystemMenuPage? = Self.movieSaveLoadStates.contains(state)
            ? (movieListSaving ? .save : .load)
            : Self.moviePages[state]
        guard let page, page != model.page else { return }
        switch page {
        case .main:
            model.showMain()
        case .save, .load:
            model.show(page)
            let mode: SaveLoadMode = page == .save ? .save : .load
            saveLoadPage = SaveLoadPageModel(mode: mode, rows: movieSaveRows, texts: saveTexts)
        case .quit:
            model.show(page)
            quitPage = ConfirmationModel(question: "Quit", options: Self.quitOptions)
        case .settings, .controls:
            model.show(page)
        }
    }

    private func updateMovie(_ body: (SWFMovieRuntime) -> Void) {
        guard movieLoaded, let renderer else { return }
        try? renderer.updateSWFRuntime(body)
    }
}
