// With the movie up, the System page runs its own Save, Load, Controls, and Quit pages,
// as in the game. This answers the calls it makes and keeps the engine page in step
// with the movie's state, so the readout and the key capture follow it.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
public import OpenSkyMenusInterface
import OpenSkyRendering

extension SystemMenuCoordinator {
    /// `SystemPage` state numbers, measured from the movie's class constants.
    static let moviePages: [Int: SystemMenuPage] = [
        0: .main, 3: .settings, 4: .settings, 5: .settings, 6: .controls,
        7: .quit, 8: .quit, 9: .quit, 11: .installedContent, 12: .installedContent,
        13: .help, 14: .help
    ]
    static let movieSaveLoadStates: Set = [1, 2, 10, 16, 17]
    /// `CREATIONS_LIST_STATE` and `HELP_LIST_STATE`: the list, with no topic open.
    static let movieTopicListStates: Set = [11, 13]
    static let movieTopicTextStates: Set = [12, 14]

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
        case .save, .load, .controls, .quit, .installedContent, .help:
            return true
        }
    }

    func sendToMovie(_ event: MenuInputEvent) {
        guard let renderer else { return }
        do {
            try SystemMenuMovieBridge.send(event, renderer: renderer)
        } catch {
            movie.record(error)
        }
        answerMovieCalls()
        followMovieState()
    }

    /// Steps the movie, so its fades and timers run, then answers its calls.
    public func tick(now: Double) {
        guard movie.advance(now: now) else { return }
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
        case .saveList, .loadList:
            saving.fillSaveList(saving: call.request == .saveList, update: updateMovie)
        case .characters, .characterSelected: saving.answerCharacters(call, update: updateMovie)
        case .screenshot:
            saving.showScreenshot(index: call.index, renderer: renderer, update: updateMovie)
        case .confirmLoad: updateMovie { $0.callMovie("ConfirmOKToLoad") }
        case .saveGame: saving.saveFromMovie(listIndex: call.index)
        case .loadGame: saving.loadFromMovie(index: call.index) { [weak self] in self?.close() }
        case .deleteSave: saving.deleteFromMovie(index: call.index)
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

    private func answerMappings(_ request: SystemMenuMovieBridge.Request) {
        if request == .resetControls {
            settings.resetBindings()
            lastMessage = "Controls reset"
        }
        refreshMovieMappings(request)
    }

    /// The movie sorts and redraws the list itself after a remap; after a plain
    /// request it has already drawn the empty list, so it is redrawn here.
    func refreshMovieMappings(_ request: SystemMenuMovieBridge.Request) {
        let rows = SystemMenuMovieBridge.mappingRows(settings.bindings, keyName: settings.keyName)
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
            ? (saving.movieListSaving ? .save : .load)
            : Self.moviePages[state]
        if
            Self.movieTopicListStates.contains(state), let last = lastMovieState, last != state,
            Self.movieTopicTextStates.contains(last)
        {
            topicPage?.showList()
        }
        lastMovieState = state
        defer {
            if
                Self.movieTopicListStates.contains(state),
                let row = SystemMenuMovieBridge.selectedTopicRow(model.page, runtime: runtime)
            {
                topicPage?.select(row)
            }
        }
        guard let page, page != model.page else { return }
        switch page {
        case .main:
            topicPage = nil
            model.showMain()
        case .save, .load:
            model.show(page)
            saving.followPage(saving: page == .save)
        case .quit:
            model.show(page)
            quitPage = ConfirmationModel(question: "Quit", options: Self.quitOptions)
        case .settings, .controls:
            model.show(page)
        case .installedContent, .help:
            showTopicPage(page)
        }
    }

    /// The movie's `SystemPage` state and its script faults, for the readout.
    public var movieDiagnostics: SystemMenuMovieDiagnostics? {
        guard movieLoaded, let runtime = renderer?.swfRuntime else { return nil }
        return SystemMenuMovieDiagnostics(runtime)
    }

    /// The System rows the movie shows, by engine title, and its highlighted row.
    /// Nil without the movie or off the main page.
    public var movieMainPage: SystemMenuPageSnapshot? {
        guard movieLoaded, model.page == .main, let runtime = renderer?.swfRuntime else {
            return nil
        }
        let rows = SystemMenuMovieBridge.entryLabels(runtime: runtime).map {
            SystemMenuMovieBridge.rowEntries[$0]?.title ?? $0
        }
        let selected = SystemMenuMovieBridge.selectedRow(runtime: runtime) ?? -1
        return SystemMenuPageSnapshot(rows: rows, selectedIndex: selected)
    }

    private func updateMovie(_ body: (SWFMovieRuntime) -> Void) {
        guard movieLoaded, let renderer else { return }
        attempt { try renderer.updateSWFRuntime(body) }
    }
}

extension SystemMenuMovieDiagnostics {
    init(_ runtime: SWFMovieRuntime) {
        self.init(
            state: SystemMenuMovieBridge.pageState(runtime: runtime),
            faults: runtime.tally.faultTotal,
            missingNames: runtime.tally.missingNames.keys.sorted()
        )
    }
}
