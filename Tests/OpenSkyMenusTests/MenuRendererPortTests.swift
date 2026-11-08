// Menu code that reaches the renderer only through its port, over a fake port, so it
// runs on a runner without Metal 4.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRendering
import Testing

/// Hands every request the same one-frame movie at once.
@MainActor
final class ImmediateMovies: MenuMovieLoading {
    private let scene: SWFMovieScene
    private(set) var paths: [String] = []

    var isAvailable: Bool {
        true
    }

    init() throws {
        scene = try SWFMovieScene(movie: SWFDisplayFixture
            .movie(tags: [SWFDisplayFixture.showFrameTag]))
    }

    func request(
        _ path: String,
        while isWanted: @escaping () -> Bool,
        then use: @escaping (Result<SWFMovieScene, AssetLoadFailure>) -> Void
    ) {
        paths.append(path)
        guard isWanted() else { return }
        use(.success(scene))
    }
}

@MainActor
struct MenuRendererPortTests {
    @Test func eachListBridgeSendsAKeyDownAndUpThroughThePort() throws {
        let port = try #require(FakeRendererPort())
        #expect(try InventoryMenuMovieBridge.send(.button(.accept), renderer: port) == false)
        #expect(try ContainerMenuMovieBridge.send(.move(.up), renderer: port) == false)
        #expect(try DialogueMenuMovieBridge.send(.button(.cancel), renderer: port) == false)
        #expect(port.swfInputs.count == 6)
        #expect(try DialogueMenuMovieBridge.send(.move(.left), renderer: port) == false)
        #expect(port.swfInputs.count == 6)
    }

    @Test func theSystemBridgeAsksTheRunningMovie() throws {
        let port = try #require(FakeRendererPort())
        #expect(try SystemMenuMovieBridge.send(.button(.accept), renderer: port) == false)
        port.swfRuntime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        #expect(try SystemMenuMovieBridge.send(.button(.accept), renderer: port) == false)
    }

    @Test func anOverlayTheRendererRefusesStaysUnloaded() throws {
        let port = try #require(FakeRendererPort())
        let overlay = try MenuMovieOverlay(movies: ImmediateMovies()) { port }
        var activations = 0
        overlay.start(path: "Interface/Overlay.swf") { _ in activations += 1 }
        #expect(port.swfOverlays.count == 1)
        #expect(!overlay.isLoaded)
        #expect(activations == 0)
    }

    @Test func theHUDStartsAndRepublishesThroughThePort() throws {
        let port = try #require(FakeRendererPort())
        let harness = try HUDMovieBridgeTests.makeRuntime()
        port.swfRuntime = harness.runtime
        let world = FakeSWFLayerWorld(renderer: port)
        let hud = try HUDCoordinator(movies: ImmediateMovies(), world: world)
        hud.start()
        #expect(hud.isLoaded)
        let published = harness.log.calls["SetCrosshairEnabled"]?.count ?? 0
        #expect(published > 0)
        hud.update { $0.crosshairEnabled = false }
        #expect(harness.log.calls["SetCrosshairEnabled"]?.count == published + 1)
    }

    @Test func aHUDWithoutAMovieLoaderFailsThroughThePort() throws {
        let port = try #require(FakeRendererPort())
        let world = FakeSWFLayerWorld(renderer: port)
        let hud = HUDCoordinator(movies: SWFMovieSource(), world: world)
        hud.start()
        #expect(!hud.isLoaded)
        #expect(hud.loadError == String(describing: HUDMovieError.movieLoaderUnavailable))
    }

    @Test func theSkillsMenuPublishesOnlyWithAModel() throws {
        let port = try #require(FakeRendererPort())
        port.swfRuntime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        let menu = SkillsMenuCoordinator(menuMode: MenuModeController())
        menu.publish(renderer: port)
        #expect(port.overlayUpdates == 0)
        menu.model = SkillsMenuModel(
            player: SkillsMenuModelTests.player(picks: 1), skills: SkillsMenuModelTests.allSkills
        )
        menu.publish(renderer: port)
        #expect(port.overlayUpdates == (menu.model?.page == .levelUp ? 1 : 0))
    }
}
