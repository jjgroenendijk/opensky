// The HUD shell without a renderer, and its load failure with one.

import EngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import OpenSkyWorldInterface
import TagsTesting
import Testing

@MainActor
final class FakeSWFLayerWorld: SWFLayerWorld {
    var renderer: Renderer?

    init(renderer: Renderer? = nil) {
        self.renderer = renderer
    }
}

@Suite(.tags(.gpu))
struct HUDCoordinatorTests {
    private static let canvas = OffscreenCanvas(width: 64, height: 64, shaders: .packageFixture)

    @Test @MainActor
    func newTargetMarksPromptAndMarkersForTheNextFrame() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        hud.updateTarget(HUDCoreTests.target())
        #expect(hud.interactionTarget?.interaction.reference == FormID(1))
        #expect(hud.sync.promptNeedsUpdate)
        #expect(hud.sync.markersNeedUpdate)
        #expect(hud.effectivePrompt == "Open Test Door")
    }

    @Test @MainActor
    func aPresentedSubtitleStaysUntilItIsCleared() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        hud.presentSubtitle("Hello there.")
        #expect(hud.shownSubtitle == "Hello there.")
        hud.presentSubtitle(nil)
        #expect(hud.shownSubtitle == nil)
    }

    @Test @MainActor
    func sameTargetAgainChangesNothing() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        hud.updateTarget(HUDCoreTests.target())
        hud.updateTarget(HUDCoreTests.target())
        #expect(!hud.sync.promptNeedsUpdate)
        #expect(!hud.sync.markersNeedUpdate)
    }

    @Test @MainActor
    func panelChangesClampTheScaleWithoutARenderer() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        hud.update { $0.scale = 9 }
        hud.update { $0.promptEnabled = false }
        #expect(hud.settings.scale == 2)
        hud.updateTarget(HUDCoreTests.target())
        #expect(hud.controlSnapshot.prompt == nil)
        #expect(hud.controlSnapshot.scale == 2)
        #expect(hud.controlSnapshot.cameraHeading == nil)
    }

    @Test @MainActor
    func startWithoutARendererDoesNothing() {
        let hud = HUDCoordinator(movies: SWFMovieSource())
        hud.start()
        #expect(!hud.isLoaded)
        #expect(hud.loadError == nil)
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device)) @MainActor
    func startWithoutGameDataReportsTheMissingLoader() throws {
        let world = try FakeSWFLayerWorld(renderer: Self.canvas.makeRenderer())
        let hud = HUDCoordinator(movies: SWFMovieSource())
        hud.attach(world: world)
        hud.start()
        #expect(!hud.isLoaded)
        #expect(hud.loadError == String(describing: HUDMovieError.movieLoaderUnavailable))
        #expect(hud.controlSnapshot.cameraHeading != nil)
    }
}
