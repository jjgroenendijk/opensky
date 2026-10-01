// The system menu shell over the real MenuModeController and a fake world.

import Foundation
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import Testing

@MainActor
private final class FakeSystemMenuWorld: SystemMenuWorld {
    var renderer: Renderer?
    var audioEnabled = true
    var audioMasterVolume: Float = 0.5
    var quitCount = 0
    var events: [MenuInputEvent] = []

    func quitApplication() {
        quitCount += 1
    }

    func handleMenuInput(_ event: MenuInputEvent) {
        events.append(event)
    }
}

@MainActor
private struct Harness {
    let menuMode = MenuModeController()
    let world = FakeSystemMenuWorld()
    let menu: SystemMenuCoordinator

    init() {
        let movies = SWFMovieSource()
        menu = SystemMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: HUDCoordinator(movies: movies)
        )
        menu.attach(world: world)
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
        #expect(harness.world.quitCount == 0)
    }

    @Test @MainActor
    func acceptOnQuitClosesAndQuits() {
        let harness = Harness()
        harness.menu.open()
        harness.menu.route(.move(.up))
        harness.menu.route(.button(.accept))
        #expect(!harness.menu.isOpen)
        #expect(harness.world.quitCount == 1)
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
    func volumeAndAudioStateComeFromTheWorld() {
        let harness = Harness()
        harness.menu.masterVolume = 0.25
        #expect(harness.world.audioMasterVolume == 0.25)
        harness.world.audioEnabled = false
        #expect(!harness.menu.snapshot.audioEnabled)
    }
}
