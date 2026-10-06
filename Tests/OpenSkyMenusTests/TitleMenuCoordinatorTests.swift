// The title menu over the real menu stack, a fake world, and fake saves.

import Foundation
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyRendering
import Testing

@MainActor
private final class FakeTitleWorld: TitleMenuWorld, MenuInputConsumer, SaveGameService {
    let menuMode = MenuModeController()
    var saveRows: [SaveSlotRow] = []
    var newGames = 0
    var starts: [NewGameStart] = []
    var quits = 0
    var loaded: [String] = []

    var menuInputConsumer: (any MenuInputConsumer)? {
        self
    }

    var renderer: Renderer? {
        nil
    }

    func showTitleBackdrop(_: Bool) {}

    func handleMenuInput(_ event: MenuInputEvent) {}

    func startNewGame(at start: NewGameStart) {
        newGames += 1
        starts.append(start)
    }

    func quitApplication() {
        quits += 1
    }

    func refreshSaveRows() async -> [SaveSlotRow] {
        saveRows
    }

    func saveGame(slot: String?) async throws -> String {
        slot ?? "New"
    }

    func loadGame(slot: String) async throws {
        loaded.append(slot)
    }

    func deleteSave(slot: String) async throws {}
}

struct TitleMenuCoordinatorTests {
    @MainActor
    private static func make() -> (TitleMenuCoordinator, FakeTitleWorld) {
        let world = FakeTitleWorld()
        let menuMode = world.menuMode
        let menu = TitleMenuCoordinator(menuMode: menuMode)
        menu.attach(world: world)
        menu.saves = world
        return (menu, world)
    }

    @Test @MainActor
    func continueShowsOnlyWithSavesAndLoadsTheNewest() async {
        let (menu, world) = Self.make()
        let menuMode = world.menuMode
        #expect(menu.entries == [.new, .load, .quit])
        world.saveRows = [
            SaveSlotRow(
                slot: "Old",
                title: "Old",
                detail: "",
                savedAt: Date(timeIntervalSince1970: 1)
            ),
            SaveSlotRow(
                slot: "New",
                title: "New",
                detail: "",
                savedAt: Date(timeIntervalSince1970: 2)
            )
        ]
        menu.open()
        #expect(menuMode.isWorldSimPaused)
        #expect(menu.snapshot.rows == ["Continue", "New", "Load", "Quit"])
        menu.route(.button(.accept))
        #expect(menu.snapshot.lastResult == "Loading New")
        await menu.loadWork?.value
        #expect(world.loaded == ["New"])
        #expect(!menu.isOpen)
    }

    @Test @MainActor
    func continueNeverPicksASkyrimImport() async {
        let (menu, world) = Self.make()
        let newest = Date(timeIntervalSince1970: 9)
        world.saveRows = [SaveSlotRow(
            slot: "ess:/a.ess",
            title: "A",
            detail: "",
            savedAt: newest,
            isImport: true
        )]
        #expect(menu.entries == [.new, .load, .quit])
        world.saveRows.append(SaveSlotRow(
            slot: "Own",
            title: "Own",
            detail: "",
            savedAt: Date(timeIntervalSince1970: 1)
        ))
        menu.open()
        menu.route(.button(.accept))
        await menu.loadWork?.value
        #expect(world.loaded == ["Own"])
    }

    @Test func importRowsLoadButAreNeverSavedOverOrDeleted() {
        let rows = [
            SaveSlotRow(
                slot: "ess:/a.ess",
                title: "A",
                detail: "",
                savedAt: Date(),
                isImport: true
            ),
            SaveSlotRow(
                slot: "Own",
                title: "Own",
                detail: "",
                savedAt: Date(timeIntervalSince1970: 1)
            )
        ]
        #expect(SaveLoadPageModel(mode: .save, rows: rows).rows.map(\.slot) == ["Own"])
        var load = SaveLoadPageModel(mode: .load, rows: rows)
        #expect(load.rows.map(\.slot) == ["ess:/a.ess", "Own"])
        load.requestDelete()
        #expect(load.confirmation == nil)
        #expect(load.handle(.button(.accept)) == .load(slot: "ess:/a.ess"))
    }

    @Test @MainActor
    func newGameClosesAndStartsTheSession() {
        let (menu, world) = Self.make()
        let menuMode = world.menuMode
        menu.open()
        menu.route(.button(.accept))
        #expect(world.newGames == 1)
        #expect(!menuMode.isMenuMode)
    }

    @Test @MainActor
    func loadPageListsSavesAndBacksOut() {
        let (menu, world) = Self.make()
        world.saveRows = [SaveSlotRow(slot: "A", title: "A", detail: "", savedAt: Date())]
        menu.open()
        menu.route(.move(.down))
        menu.route(.move(.down))
        menu.route(.button(.accept))
        #expect(menu.snapshot.isLoadPageOpen)
        menu.route(.button(.cancel))
        #expect(!menu.snapshot.isLoadPageOpen)
        menu.route(.move(.down))
        menu.route(.button(.accept))
        #expect(world.quits == 1)
    }

    @Test @MainActor
    func withoutARendererTheEngineRowsStayInCharge() async {
        let (menu, world) = Self.make()
        menu.open()
        await menu.openWork?.value
        #expect(menu.movieEnabled)
        #expect(!menu.movieLoaded)
        #expect(menu.snapshot.movie.error == "No game data located.")
        menu.route(.button(.accept))
        #expect(world.newGames == 1)
    }

    @Test @MainActor
    func aMovieRequestRunsTheMatchingRow() {
        let (menu, world) = Self.make()
        menu.open()
        menu.apply(.credits)
        #expect(menu.isOpen)
        #expect(menu.snapshot.lastResult == "Credits: not shown")
        menu.apply(.quit)
        #expect(world.quits == 1)
        menu.apply(.new)
        #expect(world.newGames == 1)
        #expect(!menu.isOpen)
    }

    @Test func thePropertiesShowQuitAndContinueAndSkipTheLogin() {
        let flags = TitleMenuMovieBridge.menuProperties(hasSaves: true, version: "OpenSky")
        #expect(flags.count == 14)
        #expect(flags[0] == .boolean(true))
        #expect(flags[1] == .boolean(true))
        #expect(flags[2] == .string("OpenSky"))
        #expect(flags[9] == .boolean(true))
        #expect(flags.enumerated().filter { $0.element == .boolean(true) }.count == 3)
    }
}
