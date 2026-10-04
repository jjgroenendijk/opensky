// The system menu shell over the real MenuModeController and a fake world.

import Foundation
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import Testing

@MainActor
private final class FakeSystemMenuWorld: @MainActor SystemMenuWorld {
    var renderer: Renderer?
    var audioEnabled = true
    var quitCount = 0
    var mainMenuCount = 0
    var events: [MenuInputEvent] = []

    func quitApplication() {
        quitCount += 1
    }

    func quitToMainMenu() {
        mainMenuCount += 1
    }

    func handleMenuInput(_ event: MenuInputEvent) {
        events.append(event)
    }
}

@MainActor
private final class FakeSaves: SaveGameService {
    var rows: [SaveSlotRow] = []
    var saved: [String?] = []
    var loaded: [String] = []
    var deleted: [String] = []

    func saveRows() -> [SaveSlotRow] {
        rows
    }

    func saveGame(slot: String?) throws -> String {
        saved.append(slot)
        return slot ?? "Save\(saved.count)"
    }

    func loadGame(slot: String) throws {
        loaded.append(slot)
    }

    func deleteSave(slot: String) throws {
        deleted.append(slot)
    }
}

@MainActor
private struct Harness {
    let menuMode = MenuModeController()
    let world = FakeSystemMenuWorld()
    let saves = FakeSaves()
    let settings = PlayerSettingsCoordinator(store: PlayerSettingsStore(persistence: nil))
    let menu: SystemMenuCoordinator

    init() {
        let movies = SWFMovieSource()
        menu = SystemMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: HUDCoordinator(movies: movies)
        )
        menu.attach(world: world)
        menu.attach(settings: settings)
        menu.saves = saves
    }

    func open(_ entry: SystemMenuEntry) {
        menu.open()
        menu.sendSelect(entry)
        menu.route(.button(.accept))
    }
}

@MainActor
extension SystemMenuCoordinator {
    fileprivate func sendSelect(_ entry: SystemMenuEntry) {
        model.select(entry)
    }
}

struct SystemMenuCoordinatorTests {
    @Test @MainActor
    func openPushesTheStackAndRoutesInputToTheWorld() {
        let harness = Harness()
        harness.menu.open()
        #expect(harness.menu.isOpen)
        #expect(harness.menuMode.topMenu == SystemMenuCoordinator.identifier)
        #expect(harness.menuMode.isWorldSimPaused)
        #expect(harness.menuMode.inputConsumer === harness.world)

        harness.menu.close()
        #expect(!harness.menu.isOpen)
        #expect(!harness.menuMode.isMenuMode)
    }

    @Test @MainActor
    func acceptOnResumeCloses() {
        let harness = Harness()
        harness.menu.open()
        harness.menu.route(.button(.accept))
        #expect(!harness.menu.isOpen)
        #expect(!harness.menuMode.isMenuMode)
        #expect(harness.world.quitCount == 0)
    }

    @Test @MainActor
    func cancelOnTheMainPageLeavesTheMenuStack() {
        let harness = Harness()
        harness.menu.open()
        harness.menu.route(.button(.cancel))
        #expect(!harness.menu.isOpen)
        #expect(!harness.menuMode.isMenuMode)
        #expect(!harness.menuMode.isWorldSimPaused)
    }

    @Test @MainActor
    func quitAsksThenQuitsToDesktop() {
        let harness = Harness()
        harness.open(.quit)
        #expect(harness.menu.isOpen, "Quit asks first")
        #expect(harness.menu.snapshot.page.rows == ["Main Menu", "Desktop", "Cancel"])
        #expect(harness.menu.snapshot.page.selectedIndex == 2, "the safe option is selected")
        harness.menu.route(.move(.up))
        harness.menu.route(.button(.accept))
        #expect(!harness.menu.isOpen)
        #expect(harness.world.quitCount == 1)
        #expect(harness.world.mainMenuCount == 0)
    }

    @Test @MainActor
    func quitToMainMenuAndCancel() {
        let harness = Harness()
        harness.open(.quit)
        harness.menu.route(.button(.cancel))
        #expect(harness.menu.model.page == .main)
        harness.open(.quit)
        harness.menu.route(.move(.down))
        harness.menu.route(.button(.accept))
        #expect(harness.world.mainMenuCount == 1)
        #expect(harness.world.quitCount == 0)
    }

    @Test @MainActor
    func settingsPageStepsTheStore() {
        let harness = Harness()
        harness.open(.settings)
        #expect(harness.menu.snapshot.page.rows == ["Gameplay", "Display", "Audio"])
        harness.menu.route(.move(.up))
        harness.menu.route(.button(.accept))
        #expect(harness.menu.settingsPage.openGroup == .audio)
        harness.menu.route(.move(.left))
        #expect(harness.settings.store.value(.masterVolume) < 1)
        harness.menu.route(.button(.cancel))
        harness.menu.route(.button(.cancel))
        #expect(harness.menu.model.page == .main)
        #expect(harness.menu.isOpen)
    }

    @Test @MainActor
    func quicksaveWritesTheQuicksaveSlot() {
        let harness = Harness()
        harness.open(.quicksave)
        #expect(harness.saves.saved == [AutosavePolicy.quicksaveSlot])
        #expect(harness.menu.lastMessage == "Quicksave")
        #expect(harness.menu.isOpen)
    }

    @Test @MainActor
    func savePageWritesANewSlotAndAsksBeforeOverwriting() {
        let harness = Harness()
        harness.saves.rows = [SaveSlotRow(
            slot: "Old", title: "Old", detail: "", savedAt: Date(timeIntervalSince1970: 1)
        )]
        harness.open(.save)
        harness.menu.route(.button(.accept))
        #expect(harness.saves.saved == [nil])
        harness.menu.route(.move(.down))
        harness.menu.route(.button(.accept))
        #expect(harness.saves.saved == [nil], "overwriting asks first")
        harness.menu.route(.move(.up))
        harness.menu.route(.button(.accept))
        #expect(harness.saves.saved == [nil, "Old"])
    }

    @Test @MainActor
    func loadPageLoadsAndClosesAndDeleteAsks() {
        let harness = Harness()
        harness.saves.rows = [SaveSlotRow(
            slot: "A", title: "A", detail: "", savedAt: Date(timeIntervalSince1970: 1)
        )]
        harness.open(.load)
        harness.menu.requestDeleteSelectedSave()
        harness.menu.route(.button(.accept))
        #expect(harness.saves.deleted.isEmpty, "No is selected first")
        harness.menu.requestDeleteSelectedSave()
        harness.menu.route(.move(.up))
        harness.menu.route(.button(.accept))
        #expect(harness.saves.deleted == ["A"])
        harness.menu.route(.button(.accept))
        #expect(harness.saves.loaded == ["A"])
        #expect(!harness.menu.isOpen)
    }

    @Test @MainActor
    func controlsPageRebindsTheNextKey() {
        let harness = Harness()
        harness.open(.controls)
        harness.menu.route(.button(.accept))
        #expect(harness.menu.isWaitingForKey)
        #expect(harness.menu.captureKey(scanCode: 0x48))
        #expect(harness.settings.bindings.scanCode(for: .forward) == 0x48)
        #expect(!harness.menu.captureKey(scanCode: 0x11), "not waiting any more")
    }

    @Test @MainActor
    func inputWhileClosedIsIgnored() {
        let harness = Harness()
        harness.menu.route(.move(.down))
        #expect(harness.menu.model.selectedIndex == 0)
    }

    @Test @MainActor
    func movieWithoutGameDataDegradesToAReadout() {
        let harness = Harness()
        harness.menu.setMovieEnabled(true)
        #expect(harness.menu.movieError == nil, "a closed menu starts no movie")
        harness.menu.open()
        #expect(!harness.menu.movieLoaded)
        #expect(harness.menu.movieError == "No game data located.")
        #expect(harness.menu.snapshot.movieEnabled)
    }

    @Test @MainActor
    func dataRootIsLocatedOnce() {
        let harness = Harness()
        var calls = 0
        harness.menu.locateDataRoot = {
            calls += 1
            return GameDataRoot(
                installURL: URL(filePath: "/tmp/Skyrim"),
                dataURL: URL(filePath: "/tmp/Skyrim/Data"),
                source: .userDefaults
            )
        }
        let snapshot = harness.menu.snapshot
        _ = harness.menu.snapshot
        #expect(calls == 1)
        #expect(snapshot.dataRootPath == "/tmp/Skyrim")
        #expect(snapshot.dataRootSource == "Settings")
    }

    @Test @MainActor
    func volumeGoesThroughTheSettingsStore() {
        let harness = Harness()
        harness.menu.masterVolume = 0.25
        #expect(harness.settings.store.value(.masterVolume) == 0.25)
        harness.world.audioEnabled = false
        #expect(!harness.menu.snapshot.audioEnabled)
    }
}
